# SiriGemini 1.0.0-11/12+debug — SiriPlus식 3대 훅 탑재(Apple 기본 응답 차단) (2026-10-13)

지침: `temp/prompt_implement_siriplus_3_hooks.txt`

## 1. 지시된 원인 주장과 검증 상태

| claim | type | verification source | status |
| :-- | :-- | :-- | :-- |
| `_tellSpeechDelegateSpeechRecognized:` 훅이 정상 작동(햅틱 1519 발생) | runtime behavior | 사용자 기기 보고(-10 설치 후 진동 확인) | VERIFIED (observed, single report) |
| 실패 이유는 Apple 백엔드가 `_handleCommand:reply:`로 "저는 Siri입니다" 계열 출력 명령을 SpringBoard에 보내기 때문 | private pipeline semantics | 외부 역공학(SiriPlus) 출처 인용만 존재. 이 프로젝트에는 `extracted/` 원본 바이너리가 **0개 파일**(실측) → class-dump/methlist 검증 불가, 디바이스 클래스 목록도 미확보 | UNVERIFIED (externally-sourced HYPOTHESIS) |
| `AFConnection` 인스턴스 메서드 `_invokeRequestTimeoutForReason:` / `_handleCommand:reply:` 존재·시그니처(4번째 인자=블록) | private selectors/types | 미검증(위와 동일 이유) | HYPOTHESIS → 기기 로그(`intercepted command: <Class>`, `response hook guard: …`)로 확정 예정 |
| 로컬/VM에 원본 SiriPlus 바이너리가 있어 검증에 쓸 수 있다 | project state | `Get-ChildItem -Recurse extracted` → 파일 0개, `mcp\` 비어있음 | DISPROVEN (실측) — 검증 수단 부재 |

## 2. 구현 (`src/Tweak.x`)

지시문대로 3 훅을 모두 AFConnection에 붙였으나, **미검증 셀렉터를 무검증 상태로 바인딩하지는 않았다**(아래 §3).

* 상태: `gIsInterceptingSiri`(가로채기 창), `gCapturedQuestion`(키워드 제거 후 질문 복사본), 기존 재진입 가드 `gInGeminiCallback` 유지.
* 1번째 훅(`_tellSpeechDelegateSpeechRecognized:`): 햅틱 1519 → 다층 텍스트 복원(-8 파이프라인 유지) → 인터셉트 시 선점 브로드캐스트 + `gIsInterceptingSiri = YES` + 성공 2차 햅틱 **1520** → Gemini RPC → 답변/오류 음성 → 발화 후 **3초** 뒤 창 해제(`dispatch_after`). `%orig` 미호출.
* 2번째 훅(`_invokeRequestTimeoutForReason:`): 창 동안 타임아웃 종료 차단(로그 후 return).
* 3번째 훅(`_handleCommand:reply:`): 창 동안 command 클래스명에 `SAUI` / `AddViews` / `AssistantUtterance` 포함 시 `%orig` 미호출로 Apple 출력 명령 원천 차단. `-10`때와 같은 크래시 방지 설계: `reply`가 실제로 `NSBlock`일 때만 `(void(^)(id))reply`로 캐스트해 `replyBlock(nil)`을 `@try` 안에서 호출(인자 타입이 가설이라 타입 검사 선행).

## 3. 안전 편차 (지시문 대비) — 검증 없는 바인딩 금지

`%group SiriGeminiAFTimeoutBlock` / `%group SiriGeminiAFCommandBlock`로 **두 훅을 분리**하고, `SiriGeminiInstallAFHook()`에서 셀렉터별로 나눠 바인딩한다:

```objc
BOOL hasTimeout = [afConn instancesRespondToSelector:@selector(_invokeRequestTimeoutForReason:)];
BOOL hasCommand = [afConn instancesRespondToSelector:@selector(_handleCommand:reply:)];
if (hasTimeout) { %init(SiriGeminiAFTimeoutBlock); }   // 개별 플래그로 1회만
if (hasCommand) { %init(SiriGeminiAFCommandBlock); }
NSLog(@"[SiriGemini] response hook guard: … installed timeout=%d command=%d", …);
```

근거: 미구현 셀렉터를 후킹하면 substrate 계열 바인딩이 `orig = NULL`로 메서드를 추가할 수 있고, 그때 훅 본문의 `%orig`(예: 창이 닫힌 뒤 호출되는 경로)가 **NULL 점프**가 되어 SpringBoard를 잡는다. `-9`의 무한 리스프링에서 "확인 안 된 것을 메인 프로세스에 심지 말라"를 이미 검증했으므로(차단형 API → 워치독), 동일 실패 유형을 사전 차단한다. 단, `-8` 때 기록된 대로 비공개 셀렉터가 동적 해석(`+resolveInstanceMethod`)으로만 존재하면 `instancesRespondToSelector:`가 **false-음성**일 수 있다 → 가드가 false로 나오면 다음 단계에서 class-dump/Frida로 실존 확인 후 가드를 제거한다.

## 4. Logos 구문학 새 발견 (VERIFIED, parser 동작)

`%group` 안에 `%hook` 없이 메서드를 직접 쓰면 logos가 `error: %orig does not make sense outside a function`(exit 255)로 실패하고 산출물은 **0줄**이 된다. 즉 `%group`은 반드시 `%hook 클래스`를 내부에 포함해야 한다. 같은 클래스를 여러 그룹에 반복 `%hook`하는 것은 정상 동작(생성 파일 703줄, 그룹별 심볼 분리).

프로브 개선: logos 실패로 빈 `.m`이 나와도 clang 프로브가 `PROBE_OK`를 출력하던 함정 → 이후 `perl logos.pl … && echo LOGOS_OK && wc -l` 체인으로 고정. (주의: 로컬 셸 래퍼에서 `grep -E "a|b"` 형태의 파이프가 원격까지 전달돼 깨짐 → 원격 grep은 접두어 단일 패턴/여러 `grep -c`로 수행.)

## 5. 빌드·검증 evidence

| 항목 | 근거 | 값 |
| :-- | :-- | :-- |
| 사전 프로브(logos + `clang -fsyntax-only`, `-Werror`) | VM 실측 | `LOGOS_OK`, 생성 703줄, `PROBE_OK` |
| 패키지(-11: 훅 탑재 / -12: 로그 태그 동기화) | `make package THEOS_PACKAGE_SCHEME=roothide` (오류 0), `dm.pl: building package …` | `-11`, `-12` 산출. `-12`는 최종 배포본 |
| dylib 내 셀렉터 존재 확인 | `strings .theos/obj/debug/arm64/SiriGemini.dylib` → `grep -c -- <접두어>` | `_handleCommand`=2, `_invokeRequestTimeoutForReason`=2(각 @selector 2회: 훅 + 가드), `_tellSpeechDelegateSpeechRecognized`=1 |
| 새 로그 문자열 포함 확인 | 같은 strings | `response hook guard`=1, `INTERCEPT ACTIVE`=1 |
| 산출물/해시 | VM `shasum` == Windows `Get-FileHash`(`build\…_1.0.0-12+debug_iphoneos-arm64e.deb`) | `a361fec78458e61b5fe2ff0d1338e3e0eb971d705a443fbf7ba40d5cc14accde` |
| `-12`가 `-11`과 기능상 동일한지 | 소스 diff = `kSiriGeminiBuildTag` 문자열 1줄(`-10`→`-12`)뿐 | VERIFIED (code-level) |

### 지시문 번호와의 편차
지시는 최종 산출물을 `1.0.0-11+debug`로 명시했으나, 훅 탑재 직후 빌드가 `-11`을 소진한 뒤 로그 태그(`kSiriGeminiBuildTag`)가 `1.0.0-10`으로 낡은 것을 발견해 동기화했다(Theos build number는 자동 증가 → 재포장 시 `-12`). AGENTS §10 "낡은 버전 재사용 금지"에 따라 **최종 산출물은 `-12`**이며, 코드 차이는 로그 문자열뿐이다.

## 6. 다음 관측 (기기)

1. `response hook guard: _invokeRequestTimeoutForReason:?1 _handleCommand:reply:?1 -> installed timeout=1 command=1` → 가드 통과 여부 = 두 셀렉터 실존 1차 판정(0이면 미존재/false-음성).
2. 발화 시 `INTERCEPT ACTIVE: '<질문>'` + 진동 1519→1520.
3. `intercepted command: <Class>` / `BLOCKED Apple Siri response command: <Class>` → 실제 Apple 응답 명령 클래스명 확정(HYPOTHESIS 해소).
4. 여전히 "시리입니다"가 들리면: 명령이 다른 셀렉터/다른 클래스를 통과하거나 reply 경로로 재생된다 → 그 로그를 근거로 차단 지점 이동.
5. 크래시 리스크 관찰 포인트: `replyBlock(nil)` 호출 시점(타입 가설). 이상 없으면 타입 검사 제거 검토.
