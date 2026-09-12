# hdr.ps1 - turn HDR on/off, or toggle it automatically while a game window is open.
#   hdr.ps1 status | on | off
#   hdr.ps1 watch [-GamesFile games.txt] [-LogFile watch.log] [-StateFile hdr-owned.flag]
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
param(
    [ValidateSet('status', 'on', 'off', 'watch')]
    [string]$Command = 'status',
    [string]$GamesFile = (Join-Path $PSScriptRoot 'games.txt'),
    [string]$LogFile = (Join-Path $PSScriptRoot 'watch.log'),
    # Exists while HDR is on because watch turned it on, so a later run can still turn it off.
    [string]$StateFile = (Join-Path $PSScriptRoot 'hdr-owned.flag'),
    [int]$IntervalSeconds = 2,
    # How long no game window must be seen before HDR goes off; rides out window re-creation.
    [int]$OffDelaySeconds = 5
)

$ErrorActionPreference = 'Stop'

if (-not ('HdrToggle.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace HdrToggle {

public class Display {
    public LUID Adapter;
    public uint TargetId;
    public string Name;
    public bool HdrSupported;
    public bool HdrOn;
    public bool UsesInfo2;   // Windows 11 24H2+ API is available
    public uint RawValue;
    public uint ColorMode;   // 0 = SDR, 1 = WCG, 2 = HDR
}

[StructLayout(LayoutKind.Sequential)]
public struct LUID { public uint LowPart; public int HighPart; }

public static class Native {
    const uint QDC_ONLY_ACTIVE_PATHS = 2;
    const uint GET_TARGET_NAME = 2;
    const uint GET_ADVANCED_COLOR_INFO = 9;
    const uint SET_ADVANCED_COLOR_STATE = 10;
    const uint GET_ADVANCED_COLOR_INFO_2 = 15;
    const uint SET_HDR_STATE = 16;

    [StructLayout(LayoutKind.Sequential)]
    struct PATH_INFO {
        public LUID srcAdapter; public uint srcId; public uint srcModeIdx; public uint srcFlags;
        public LUID tgtAdapter; public uint tgtId; public uint tgtModeIdx; public uint outputTechnology;
        public uint rotation; public uint scaling; public uint refreshNum; public uint refreshDen;
        public uint scanLineOrdering; public int targetAvailable; public uint tgtFlags;
        public uint flags;
    }

    [StructLayout(LayoutKind.Sequential, Size = 64)]
    struct MODE_INFO { public uint infoType; }

    [StructLayout(LayoutKind.Sequential)]
    struct HEADER { public uint type; public uint size; public LUID adapterId; public uint id; }

    [StructLayout(LayoutKind.Sequential)]
    struct COLOR_INFO { public HEADER header; public uint value; public uint colorEncoding; public uint bitsPerColorChannel; }

    // value bits seen on this machine: 0 advancedColorSupported, 1 advancedColorActive,
    // 4 highDynamicRangeSupported, 5 highDynamicRangeUserEnabled, 6 wideColorSupported.
    [StructLayout(LayoutKind.Sequential)]
    struct COLOR_INFO_2 { public HEADER header; public uint value; public uint colorEncoding; public uint bitsPerColorChannel; public uint activeColorMode; }

    [StructLayout(LayoutKind.Sequential)]
    struct SET_STATE { public HEADER header; public uint value; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct TARGET_NAME {
        public HEADER header; public uint flags; public uint outputTechnology;
        public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string monitorFriendlyDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string monitorDevicePath;
    }

    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPaths, out uint numModes);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint numPaths, [Out] PATH_INFO[] paths, ref uint numModes, [Out] MODE_INFO[] modes, IntPtr topologyId);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref COLOR_INFO packet);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref COLOR_INFO_2 packet);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TARGET_NAME packet);
    [DllImport("user32.dll")] static extern int DisplayConfigSetDeviceInfo(ref SET_STATE packet);

    static HEADER Header(uint type, Type t, LUID adapter, uint id) {
        HEADER h = new HEADER();
        h.type = type;
        h.size = (uint)Marshal.SizeOf(t);
        h.adapterId = adapter;
        h.id = id;
        return h;
    }

    public static List<Display> GetDisplays() {
        uint numPaths, numModes;
        int err = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out numPaths, out numModes);
        if (err != 0) throw new Win32Exception(err);
        PATH_INFO[] paths = new PATH_INFO[numPaths];
        MODE_INFO[] modes = new MODE_INFO[numModes];
        err = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref numPaths, paths, ref numModes, modes, IntPtr.Zero);
        if (err != 0) throw new Win32Exception(err);

        List<Display> result = new List<Display>();
        for (int i = 0; i < numPaths; i++) {
            PATH_INFO p = paths[i];
            Display d = new Display();
            d.Adapter = p.tgtAdapter;
            d.TargetId = p.tgtId;

            TARGET_NAME name = new TARGET_NAME();
            name.header = Header(GET_TARGET_NAME, typeof(TARGET_NAME), p.tgtAdapter, p.tgtId);
            bool named = DisplayConfigGetDeviceInfo(ref name) == 0 && !String.IsNullOrEmpty(name.monitorFriendlyDeviceName);
            d.Name = named ? name.monitorFriendlyDeviceName : "target " + p.tgtId;

            // Prefer the 24H2+ query; its activeColorMode separates HDR from WCG.
            COLOR_INFO_2 info2 = new COLOR_INFO_2();
            info2.header = Header(GET_ADVANCED_COLOR_INFO_2, typeof(COLOR_INFO_2), p.tgtAdapter, p.tgtId);
            if (DisplayConfigGetDeviceInfo(ref info2) == 0) {
                d.UsesInfo2 = true;
                d.RawValue = info2.value;
                d.ColorMode = info2.activeColorMode;
                d.HdrSupported = (info2.value & (1u << 4)) != 0;
                d.HdrOn = info2.activeColorMode == 2;
            } else {
                COLOR_INFO info = new COLOR_INFO();
                info.header = Header(GET_ADVANCED_COLOR_INFO, typeof(COLOR_INFO), p.tgtAdapter, p.tgtId);
                if (DisplayConfigGetDeviceInfo(ref info) == 0) {
                    d.RawValue = info.value;
                    d.HdrSupported = (info.value & 1u) != 0;
                    d.HdrOn = (info.value & 2u) != 0;
                }
            }
            result.Add(d);
        }
        return result;
    }

    public static int SetHdr(Display d, bool on) {
        SET_STATE s = new SET_STATE();
        s.value = on ? 1u : 0u;
        if (d.UsesInfo2) {
            s.header = Header(SET_HDR_STATE, typeof(SET_STATE), d.Adapter, d.TargetId);
            if (DisplayConfigSetDeviceInfo(ref s) == 0) return 0;
        }
        s.header = Header(SET_ADVANCED_COLOR_STATE, typeof(SET_STATE), d.Adapter, d.TargetId);
        return DisplayConfigSetDeviceInfo(ref s);
    }
}
}
'@
}

$script:Logging = $false

function Write-Log([string]$Message) {
    $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
    $line
    if ($script:Logging) { Add-Content -Path $LogFile -Value $line }
}

function Get-HdrDisplays {
    [HdrToggle.Native]::GetDisplays() | Where-Object { $_.HdrSupported }
}

function Set-Hdr([bool]$On) {
    foreach ($d in Get-HdrDisplays) {
        $err = [HdrToggle.Native]::SetHdr($d, $On)
        if ($err -ne 0) { Write-Log ('{0}: setting HDR to {1} failed, error {2}' -f $d.Name, $On, $err) }
    }
}

function Read-Games([string]$Path) {
    Get-Content -Path $Path |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') } |
        ForEach-Object { $_ -replace '\.exe$', '' }
}

# A process only counts while it has a window. Minimized windows still count;
# a process left behind after its window closed (Roblox does this) does not.
function Get-RunningGames([string[]]$Names) {
    Get-Process -Name $Names -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }
}

function Test-HdrOn {
    @(Get-HdrDisplays | Where-Object { $_.HdrOn }).Count -gt 0
}

switch ($Command) {
    'status' {
        foreach ($d in [HdrToggle.Native]::GetDisplays()) {
            '{0,-24} supported={1,-5} on={2,-5} mode={3} api={4} raw=0x{5:X8}' -f `
                $d.Name, $d.HdrSupported, $d.HdrOn, $d.ColorMode,
                $(if ($d.UsesInfo2) { '24H2' } else { 'legacy' }), $d.RawValue
        }
    }
    'on' { Set-Hdr $true }
    'off' { Set-Hdr $false }
    'watch' {
        $script:Logging = $true
        $games = @(Read-Games $GamesFile)
        if ($games.Count -eq 0) { throw "no games listed in $GamesFile" }
        Write-Log ('watching {0} game(s): {1}' -f $games.Count, ($games -join ', '))

        # Only undo what we did: if HDR was already on when a game started, leave it on afterwards.
        # The state file carries that across restarts, e.g. a shutdown in the middle of a game.
        $weTurnedOn = Test-Path $StateFile
        if ($weTurnedOn) { Write-Log 'state file found: an earlier run left HDR on' }
        $lastGameSeen = [datetime]::MinValue

        while ($true) {
            $running = @(Get-RunningGames $games)
            if ($running.Count -gt 0) {
                $lastGameSeen = Get-Date
                if (-not $weTurnedOn -and -not (Test-HdrOn)) {
                    Write-Log ('{0} window open, HDR on' -f $running[0].ProcessName)
                    Set-Hdr $true
                    Set-Content -Path $StateFile -Value (Get-Date -Format s)
                    $weTurnedOn = $true
                }
            } elseif ($weTurnedOn -and ((Get-Date) - $lastGameSeen).TotalSeconds -ge $OffDelaySeconds) {
                Write-Log ('no game window for {0}s, HDR off' -f $OffDelaySeconds)
                Set-Hdr $false
                Remove-Item -Path $StateFile -ErrorAction SilentlyContinue
                $weTurnedOn = $false
            }
            Start-Sleep -Seconds $IntervalSeconds
        }
    }
}
