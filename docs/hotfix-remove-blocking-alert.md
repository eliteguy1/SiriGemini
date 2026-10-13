# SiriGemini 1.0.0-10+debug — 핫픽스: `%ctor` 내 차단형 알림(CFUserNotificationDisplayAlert) 완전 제거 (2026-10-13)

지침: `temp/prompt_hotfix_remove_alert_crash.txt` (`-9` 기기 테스트에서 무한 리스프링 보고)

## 1. 원인 분석과 검증 상태

| claim | type | verification source | status |
| :-- | :-- | :-- | :-- |
| `-9` 설치 후 SpringBoard가 무한 리스프링(감지 불가/진단음 없음) | runtime behavior (기기) | 사용자 보고 | VERIFIED (observed, single report) |
| `CFUserNotificationDisplayAlert(timeout=0, …)`는 사용자가 닫을 때까지 호출 스레드를 기다린다 | API semantics | Apple Docs: "`timeout`: The amount of time to wait for the user to dismiss the notification dialog… Pass `0` to have the dialog never time out." (`documentation/CoreFoundation/cfusernotificationdisplayalert.md`) | VERIFIED (docs) |
| 따라서 SpringBoard 자기 `%ctor`(메인 스레드, 부팅 중)에서 timeout=0 호출 → Startup stall → 워치독 kills → 무한 리스프링 | causal mechanism | 위 docs + `-9` 코드 실측(`%ctor → ReportLoad → ShowAlert` was synchronous call chain into the blocking API) — kill 신호/watchdog 값은 기기 로그 미확보 | VERIFIED (blocking path, code+docs) / HYPOTHESIS (SIGKILL·10s 수치) |
| "이로써 dylib가 SpringBoard에 정상 주입됨이 100% 입증" | runtime behavior | 크래시 자체가 주입 증거라는 추론은 타당하나 독립 로그(크래시 리포트/`ctor loaded in process:`) 미확보 | STRONGLY INFERRED / OPEN (로그로 확정 예정) |
| 햅틱 `AudioServicesPlaySystemSound(1519)`는 훅 내 호출이므로 부팅 경로를 막지 않는다 | call-site safety | 코드 실측: 1519 호출은 `_tellSpeechDelegateSpeechRecognized:` 내부에만 존재(%ctor 경로 아님), 사운드 1003은 팝업과 함께 삭제 | VERIFIED (code-level) / 청각·진동 체감은 미검증 |

## 2. 코드 변경 (`src/Tweak.x`)

* `#import <CoreFoundation/CFUserNotification.h>` 삭제, `SiriGeminiShowAlert()` 함수 통째 삭제 → 소스 내 `CFUserNotificationDisplayAlert` 호출 0건(주석 언급만 잔존).
* `SiriGeminiReportLoad()`는 **로그 전용**으로 축소:
  `[SiriGemini] v1.0.0-10 ctor loaded in process: <name> (AFConnection: 0/1)`
* `kSiriGeminiBuildTag`를 `@"1.0.0-10"`로 동기화(수동 태그 → 매 릴리스 확인 필요).
* `%ctor`: 차단형 호출 제거 후에도 `-8/-9`의 안전장치(dlopen 2종, Darwin 옵저버 2종 = 설정/선점, nil 검사 후 `%init(_ungrouped)`, `didFinishLaunching` 재시도)은 유지. **지침 샘플과의 의도적 편차**: 지시 예시는 dlopen·claim 옵저버를 생략하지만, dlopen 없이는 `%ctor` 시점에 `AFConnection`이 로드돼 있지 않아 바인딩이 지연되고 claim 옵저버를 지우면 `-8`의 크로스프로세스 선점(중복 답변 억제)이 사라진다. 두 항목 모두 부팅을 막지 않으므로 유지했다.

## 3. 정적 evidence

| 항목 | 근거 | 값 |
| :-- | :-- | :-- |
| 사전 프로브(logos + `clang -fsyntax-only`, `-Wunused-function -Werror=unused-function` **그리고 전체 `-Werror`**) | VM 실행 | `logos_exit=0`, `PROBE_OK` |
| 패키지 빌드 | `make clean && make package THEOS_PACKAGE_SCHEME=roothide` | `grep -c error:` = 0, `dm.pl: building package … com.csw.sirigemini_1.0.0-10+debug_iphoneos-arm64e.deb` |
| 산출물 회수/해시 | VM `shasum -a 256` == Windows `Get-FileHash` | `192655ec6117ed4c0fa4aa0d6f32ff3e5768489d90d8498acbe73d8755591fb5` |
| 알림 API 심볼 제거 | `nm -u .theos/obj/debug/arm64/SiriGemini.dylib \| grep -c CFUserNotification` | 0 (완전 제거) |
| 햅틱 유지 | 같은 dylib의 undefined 심볼 | `(undefined) external _AudioServicesPlaySystemSound (from AudioToolbox)` 존재 |

 주의: `ls packages | tail -2`는 사전순 정렬 때문에 `1.0.0-10`을 마지막에 보여주지 않는다(`-10` < `-8`). 산출물 확인에는 `grep -- "-10"`를 쓸 것.

## 4. 다음 관측 (판정)

1. 리스프링 정상화 여부 = 이번 핫픽스의 1차 검증 대상(정상 부팅 = 차단형 UI가 리스프링 원인임을 기기로 확정).
2. 로그에 `ctor loaded in process: SpringBoard (AFConnection: …)`가 보이면 주입·클래스 상태를 팝업 없이 확정. 확인 방법: `syslog`/`log` 스트림 또는 Console에서 `[SiriGemini]` 필터.
3. 발화 시 진동(1519)과 `HOOK FIRED in process <name>` 로그 → 셀렉터 유효성 판정(여전히 HYPOTHESIS).
