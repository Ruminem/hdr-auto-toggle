# hdr-auto-toggle

등록한 게임이 실행되면 HDR을 켜고, 모두 종료되면 다시 끔.

> 끝의 정의: 등록한 게임 창이 열리면 HDR이 켜지고, 모두 닫히면 다시 꺼짐.

평소에는 HDR을 꺼 두고 게임할 때만 켜려고 만듦. HDR이 켜진 상태에서 캡처 도구로 찍으면 톤 매핑 때문에 밝은 부분이 번짐.

## 요구 사항

- Windows 11. 25H2(빌드 26200)에서 확인함. 24H2 이전 버전에서는 구형 API로 넘어가게 해 뒀지만 확인하지 않음.
- Windows PowerShell 5.1 (Windows에 기본으로 포함됨)
- HDR을 지원하는 모니터

## 사용법

```powershell
powershell -ExecutionPolicy Bypass -File hdr.ps1 status   # 현재 상태
powershell -ExecutionPolicy Bypass -File hdr.ps1 on
powershell -ExecutionPolicy Bypass -File hdr.ps1 off
powershell -ExecutionPolicy Bypass -File hdr.ps1 watch    # games.txt 감시
```

`games.txt`에 프로세스 이름을 한 줄에 하나씩 적음. `.exe`는 붙여도 되고 안 붙여도 됨. 들어 있는 목록은 만든 사람의 게임이므로 본인 게임으로 바꿔서 쓰면 됨.

## 로그온 시 자동 실행

`install-task.ps1`을 한 번 실행하면 작업 스케줄러에 등록됨. 등록을 해제하려면 다음 명령을 실행함.

```powershell
Unregister-ScheduledTask -TaskName hdr-auto-toggle -Confirm:$false
```

로그는 `watch.log`에 남음.

## 동작 방식

- 게임은 창이 있을 때만 실행 중으로 봄. 최소화된 창은 포함하고, 창을 닫은 뒤 남은 프로세스(로블록스가 그럼)는 제외함.
- 게임 창이 사라져도 5초 동안 기다린 뒤 끔. 전체 화면 모드를 바꿀 때 창이 다시 만들어지면서 HDR이 깜빡이는 것을 막음.
- 최소화나 Alt+Tab으로는 끄지 않음. 게임 도중 HDR을 바꾸면 게임에 따라 화면이 깨지거나 HDR 출력이 풀림.
- 게임을 켤 때 HDR이 이미 켜져 있었다면 건드리지 않고, 게임이 끝나도 끄지 않음.
- watch가 HDR을 켜면 `hdr-owned.flag`를 남김. 게임 도중 PC가 꺼져도, 다음에 watch가 시작될 때 게임 창이 없으면 이 파일을 보고 HDR을 끔.

## 구현 메모

- Windows 11 24H2부터 HDR과 WCG가 분리됨. 먼저 `DISPLAYCONFIG_DEVICE_INFO_SET_HDR_STATE`(16)로 시도하고, 실패하면 `SET_ADVANCED_COLOR_STATE`(10)를 씀. 상태는 `GET_ADVANCED_COLOR_INFO_2`(15)의 `activeColorMode == 2`로 판단함.
- `DISPLAYCONFIG_TARGET_DEVICE_NAME`의 `monitorDevicePath`는 WCHAR[260]이 아니라 WCHAR[128]임. 구조체 전체가 420바이트가 아니면 `DisplayConfigGetDeviceInfo`가 오류 87을 반환함.
- `.ps1` 파일에는 ASCII만 씀. Windows PowerShell 5.1은 BOM이 없는 파일을 ANSI로 읽음.

## 라이선스

[MIT](LICENSE)
