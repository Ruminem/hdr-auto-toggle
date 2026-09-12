# hdr-auto-toggle

등록한 게임이 실행되면 HDR을 켜고, 전부 종료되면 다시 끈다.

> 끝의 정의: 등록한 게임 exe가 실행되면 HDR이 켜지고, 전부 종료되면 다시 꺼진다.

평소에는 HDR을 꺼두고(캡처도구로 찍으면 톤매핑 때문에 빛이 번지니까) 게임할 때만 켜려고 만들었다.

## 사용

```powershell
powershell -ExecutionPolicy Bypass -File hdr.ps1 status   # 현재 상태
powershell -ExecutionPolicy Bypass -File hdr.ps1 on
powershell -ExecutionPolicy Bypass -File hdr.ps1 off
powershell -ExecutionPolicy Bypass -File hdr.ps1 watch    # games.txt 감시
```

`games.txt`에 프로세스 이름을 한 줄에 하나씩 적는다. `.exe`는 붙여도 되고 안 붙여도 된다.

## 로그온 시 자동 실행

`install-task.ps1`을 한 번 실행하면 작업 스케줄러에 등록된다. 해제는 다음과 같이 한다.

```powershell
Unregister-ScheduledTask -TaskName hdr-auto-toggle -Confirm:$false
```

로그는 `watch.log`에 남는다.

## 메모

- Windows 11 24H2부터 HDR과 WCG가 분리됐다. 먼저 `DISPLAYCONFIG_DEVICE_INFO_SET_HDR_STATE`(16)로 시도하고, 실패하면 `SET_ADVANCED_COLOR_STATE`(10)로 넘어간다. 상태는 `GET_ADVANCED_COLOR_INFO_2`(15)의 `activeColorMode == 2`로 판단한다.
- 게임을 켤 때 HDR이 이미 켜져 있었다면 건드리지 않고, 게임이 끝나도 끄지 않는다.
- `.ps1` 파일에는 ASCII만 쓴다. Windows PowerShell 5.1은 BOM이 없는 파일을 ANSI로 읽는다.
