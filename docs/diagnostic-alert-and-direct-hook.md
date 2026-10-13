# SiriGemini 1.0.0-9+debug — 화면 진단 팝업(HUD) · 햅틱 · AFConnection 표준 직접 훅 (2026-10-13)

지침: `temp/prompt_diagnostic_alert_and_direct_hook.txt`

## 1. 지시된 진단의 검증 상태

| 주장 | 확인 결과 | 상태 |
| :-- | :-- | :-- |
| "진단 음성조차 안 나오고 순정 시리가 답변 → dylib 미로드 또는 `%ctor`의 `objc_getClass` 조건부 검사 실패로 훅 미설치" | 사용자 보고(진단음 없음)는 외부모색. 두 원인 중 어느 쪽인지는 로그/팝업 없이는 구분 불가 | HYPOTHESIS (지시) — 본 릴리스의 팝업·햅틱이 이를 분리 판정하기 위한 계측 |
| "logos 표준 `%hook`(최상위)로 바꾸면 런타임이 안전하게 dynamic swizzling 수행" | logos 생성 코드 실측: ungrouped `%init(_ungrouped)`도 **호출 지점에 인라인 바인딩**을 발행하며 `objc_getClass(...)` 결과는 **nil 가드 없이** 그대로 `MSHookMessageEx`에 전달된다(아래 §3) — 즉 "자동으로 안전"은 아님 | 반증 (partially disproven, 생성 코드 근거) |
| `-8`에서 AFConnection 훅이 설치되지 않았을 가능성 | `-8` 경로(`%group` + `if (objc_getClass) %init(group)`)와 `-9` 경로(ungrouped + 자체 nil 검사 후 `%init(_ungrouped)`)는 **동작상 사실상 동일**(둘 다 클래스 존재 시에만 바인딩). 따라서 직접 훅 전환 자체가 "설치 실패"를 해결한다는 근거는 없음 | HYPOTHESIS 유지 (root cause 미규명) → HUD로 판정 예정 |

## 2. 구현 내역 (`src/Tweak.x`)

### A. 화면 진단 HUD (지시 A 그대로 + 확장)
```objc
#import <AudioToolbox/AudioToolbox.h>
#import <CoreFoundation/CFUserNotification.h>

static void SiriGeminiShowAlert(NSString *title, NSString *message);  // main queue dispatch
// AudioServicesPlaySystemSound(1003) + CFUserNotificationDisplayAlert(..., CFSTR("확인"), ...)
```
* `SiriGeminiReportLoad()`는 모든 프로세스에서 로그(`ctor loaded in process: X (AFConnection: 0/1)`), SpringBoard에서는 팝업.
* 팝업 내용 = 지시문이 원하는 정보(버전 태그 + 프로세스명 + AFConnection 발견 여부):
  title `SiriGemini v1.0.0-9`, message `SpringBoard 주입 성공!\n프로세스: …\nAFConnection: 발견됨/미발견`.
* 버전 문자열 `kSiriGeminiBuildTag = @"1.0.0-9"`는 **수동 태그**다(Theos build number는 자동 증가하므로 매 릴리스마다 동기화 필요 — 탈동기 시 화면 표시가 실제 빌드와 어긋난다).

### B. `%ctor` (지시 B 반영, 기존 안전장치 유지)
```objc
dlopen(AssistantServices / SAObjects);          // 유지
CFNotificationCenterAddObserver(설정 변경);        // 유지
CFNotificationCenterAddObserver(선점 알림);        // 유지 (-8 파생)
SiriGeminiReloadSettings();
SiriGeminiInstallAFHook();                      // ← 클래스 확인 후 %init(_ungrouped)
SiriGeminiReportLoad();                         // 팝업은 설치 시도 이후(정확한 상태 표시)
if (objc_getClass("SAUIAssistantUtteranceView")) %init(SiriGeminiUtteranceView);   // 유지(group 조건부)
UIApplicationDidFinishLaunchingNotification 옵저버 → ReloadSettings + InstallAFHook 재시도  // 지시 3
```

### C. AFConnection을 `%group` 없이 최상위 `%hook`로 (지시 C)
* 다층 텍스트 복원/가로채기/진단음 로직은 그대로 유지.
* 훅 진입 시 `AudioServicesPlaySystemSound(1519);` 햅틱 추가 → 인식 반응 체감.

### D. 지시문 대비 의도적 편차 2건 (근거)
1. **SAUIAssistantUtteranceView는 `%group` + 조건부 init 유지.** 근거: 생성 코드 실측 결과 ungrouped 바인딩에도 nil 가드가 없으므로, 그 클래스가 없는 프로세스(필터 확장으로 주입된 SiriViewService 등)에서 `%init(_ungrouped)`에 포함되면 `MSHookMessageEx(nil, …)` 경로에 노출된다. AFConnection은 `dlopen` 직후라 `-9`에서도 우리 코드(`SiriGeminiInstallAFHook`)가 nil을 막는다.
2. **팝업 메시지를 지시 B의 문구 대신 지시 1절이 요구한 정보(버전/프로세스/AFConnection 상태)로 구성**했다(두 지시가 서로 다른 문구를 적었음 → 정보 기준으로 통일).

## 3. logos 생성 코드 실측 (핵심 근거)

`perl $THEOS/bin/logos.pl Tweak.x > /tmp/Tweak_pre.m` 결과:

```
592: {Class _logos_class$_ungrouped$AFConnection = objc_getClass("AFConnection");
     { MSHookMessageEx(_logos_class$_ungrouped$AFConnection, @selector(_tellSpeechDelegateSpeechRecognized:), …); }}
```
* 위 코드는 `SiriGeminiInstallAFHook()` 내부(= `%init(_ungrouped)` 호출 지점)에 인라인으로 발행됨.
* 파일 어디에도 ungrouped 훅을 자동 설치하는 별도 생성 생성자(constructor)는 없음(`grep -c _logos_init` = 0, MSHookMessageEx는 위 두 곳뿐).
  → 즉 **명시적 %init 호출이 유일한 설치 경로**이며, 이전 세션의 "%group 조건부 %init가 훅을 통째로 껐다" 가정과 달리 `-8`도 같은 방식이었다(§1 참조).

## 4. 로딩 안정성 확인 (dyld 관점)

팝업/햅틱 심볼이 로드 시점에 실패하면 "트윅 미로드"와 동일한 증상을 낸다. 산출물 dylib 실측:
```
otool -L .theos/obj/debug/arm64/SiriGemini.dylib
  … /System/Library/Frameworks/AudioToolbox.framework/AudioToolbox (compat 1.0.0)
```
AudioToolbox가 링크됨(빌드 시 자동 추가). CoreFoundation은 Foundation 경유로 이미 링크 목록에 존재 → `CFUserNotificationDisplayAlert`/`AudioServicesPlaySystemSound` 미해결 심볼 위험 없음 (VERIFIED, static).

## 5. 빌드·검증 evidence

| 항목 | 근거 | 상태 |
| :-- | :-- | :-- |
| 사전 프로브(logos + `clang -fsyntax-only`, `-Werror=unused-function` 포함) | VM 실행 → `PROBE_OK`(무출력). 이전 사이클 실패(unused-function)를 복제하도록 플래그 추가 | VERIFIED (tool chain) |
| 패키지 빌드 | `make clean && make package THEOS_PACKAGE_SCHEME=roothide` → `grep -c error:` = 0 | VERIFIED |
| 산출물/회수 | `packages/com.csw.sirigemini_1.0.0-9+debug_iphoneos-arm64e.deb`, 로컬 복사본 SHA256 == VM shasum = `f6780d47f427bc3546774d38477f2c35c9798c4a6c004b6d0bf572417119f5e9` | VERIFIED |
| AudioToolbox 링크 여부 | `otool -L` 실측 | VERIFIED (static) |
| 팝업이 실제 리스프링 후 SpringBoard 화면에 뜨는지 | 기기 미테스트 — **이번 릴리스의 1차 관측 목표** | OPEN ISSUE |
| 햅틱(1519)/팝업(1003) 소리·진동 체감 및 `CFUserNotificationDisplayAlert`의 iOS 18 동작 | 기기 미테스트 (API 존재는 SDK 헤더로 확인: CoreFoundation CFUserNotification) | OPEN ISSUE |
| 직접 훅 전환이 기존 "가로채기 실패"를 해결했는지 | 팝업/로그 결과 전까지 판단 불가 | UNVERIFIED |

## 6. 판정 흐름(사용자 관측 → 결론)

1. 리스프링 후 **팝업 안 보임** → dylib 주입 자체가 차단/미실행(RootHide 필터·권한·설치 문제). 다음 단계: 설치 경로/plutil 확인, RootHide 금지 목록, `Filter` 매칭 검증(로그도 없음이 예상).
2. **팝업 떴고 AFConnection: 발견됨** → 훅 바인딩 시도됨. 발화 시 진동/`HOOK FIRED` 로그를 확인 → 없으면 셀렉터 자체가 다른 것(class-dump/Frida 필요).
3. **팝업 떴고 AFConnection: 미발견** → AssistantServices가 그 프로세스에 늦게/아예 로드되지 않음 → `didFinishLaunching` 재시도 및 추가 dlopen 후보 확인 필요.
