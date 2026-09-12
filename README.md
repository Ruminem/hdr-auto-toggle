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
- 게임은 창이 있을 때만 실행 중으로 친다. 최소화한 창은 포함하고, 창을 닫은 뒤 남은 프로세스(로블록스가 그렇다)는 제외한다.
- 게임 창이 사라져도 5초 동안은 기다렸다가 끈다. 전체 화면 모드를 바꿀 때 창이 다시 만들어지면서 HDR이 깜빡이는 것을 막는다.
- 최소화나 Alt+Tab으로는 끄지 않는다. 게임 도중 HDR을 바꾸면 게임에 따라 화면이 깨지거나 HDR 출력이 풀린다.
- 게임을 켤 때 HDR이 이미 켜져 있었다면 건드리지 않고, 게임이 끝나도 끄지 않는다.
- watch가 HDR을 켜면 `hdr-owned.flag`를 남긴다. 게임 도중 PC가 꺼져도, 다음에 watch가 시작될 때 게임 창이 없으면 이 파일을 보고 HDR을 끈다.
- `.ps1` 파일에는 ASCII만 쓴다. Windows PowerShell 5.1은 BOM이 없는 파일을 ANSI로 읽는다.
