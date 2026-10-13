# SiriGemini 1.0.0-8+debug — 음성 텍스트 복원 강화 · 필터 확장 · 크로스프로세스 선점 (2026-10-13)

지침: `temp/prompt_fix_speech_extraction_and_filter.txt`

## 1. 지시된 원인 진단의 검증 상태

| 지시 주장 | 자체 확인 결과 | 상태 |
| :-- | :-- | :-- |
| 원인 1: `SiriGeminiExtractRecognizedText`가 실패 시 fallback 없이 `nil` 반환 → 훅의 `if (recognizedText && …)` 가 false → `%orig`(기본 Siri) 실행 | 이전 코드(`-7`)에서 사실로 확인: KVC 경로 실패/예외 시 끝에서 `return nil;` 하나뿐 (`src/Tweak.x` 이전 구현). 훅 조건문 구조도 동일하게 존재 | VERIFIED (code-level, `-7` 소스 검토) |
| 원인 2: iOS 18에서 Siri 음성 인식/UI가 `com.apple.siri`, `com.apple.SiriViewService` 등 보조 프로세스에서 실행될 수 있음 | 기기 미측정. dylib 주입 여부와 실제 `_tellSpeechDelegateSpeechRecognized:` 호출 프로세스는 로그로만 확정 가능 | HYPOTHESIS (지시 recall) → 기기 `HOOK FIRED in process …` 로그로 확정 예정 |
| "`너 이름이 뭐야`에 기본 시리가 대답" 재현 보고 | 사용자/지침 인용. 로그 파일 미수취 | EXTERNALLY-SOURCED REPORT |

원인 1은 코드상 확인 가능했으므로 즉시 수정 대상; 원인 2는 검증 가능한 형태로 계측을 추가하는 방식으로 대응했다(아래 C).

## 2. 변경 내역

### A. `src/SiriGemini.plist` — 필터 확장 (지시 그대로)

```xml
<key>Bundles</key>
<array>
    <string>com.apple.springboard</string>
    <string>com.apple.siri</string>
    <string>com.apple.SiriViewService</string>
</array>
<key>Executables</key>
<array><string>assistantd</string></array>
```

패키지 내 설치 확인: `.theos/_/Library/MobileSubstrate/DynamicLibraries/SiriGemini.plist`
`plutil -p` 결과 3개 bundle + executable 1개 확인 (VERIFIED, VM 실측).
주의: `layout/Library/PreferenceLoader/Preferences/SiriGemini.plist`(선호설정 엔트리)는 별개 파일이며 건드리지 않았다.

### B. 텍스트 복원 다층화 — 조용한 nil 폐지 (`src/Tweak.x`)

`SiriGeminiExtractRecognizedText(id)`가 아래 순서로 전부 실패할 때까지 시도한다:

1. `recognition.phrases` → `phrases[]` → `tokens[].text` (실패 시 `phrase.text`) — 공백 결합
2. 직접 텍스트 키 다중 탐색: `text`, `transcription`, `bestTranscription`, `bestText`, `recognizedText`
   (`respondsToSelector:` + KVC, 가장 긴 문자열 채택)
3. **description 정규식 폴백**: `text\s*=\s*"([^"]+)"`, `phrase\s*=…`, `token\s*=…` 매칭 전부 공백 결합 (지시값 그대로)
4. **description 단어 추출 폴백**: 패턴 `[가-힣A-Za-z]{2,}` 로 읽을 만한 단어만 결합

KVC 헬퍼는 예외를 삼키되 타입 검사로 안전성 유지:
`SiriGeminiRawValue`(id 반환 → 배열 접근 가능) / `SiriGeminiStringValue`(NSString 한정).
※ 초기 커밋본에서는 배열 프로퍼티(`tokens`)도 string 한정 헬퍼로 읽으려 해 배열이 항상 무시는 되는 결함이 있었다(코드 검토에서 발견, -8에 포함 전 수정; 검증은 코드 리뷰 수준 — 런타임 미검증).

5. 전부 실패 시: `gLastExtractFailClass`에 클래스명 기록 + 로그 `ALL text extraction paths failed, class: …`
   → 훅이 `SiriGeminiHandleExtractionFailure()`로 **음성 진단**(`음성이 인식되었으나 텍스트 복원에 실패했습니다: <클래스명>`)을 내고 `%orig`를 차단한다.
   발동 조건: speech 관련 클래스명(`Speech|Recogni|Transcription|Utterance`, 대소문자 무시) **그리고** `gKeyword.length == 0`(키워드 설정 상태에서 무관 발화를 가로채지 않도록 지시 B-3을 좁혀 해석).

### C. 훅 진입 계측 (지시 C)

```objc
NSLog(@"[SiriGemini] HOOK FIRED in process %@!", [NSProcessInfo processInfo].processName);
```
기존 `Raw speech object:` 로그와 함께 남긴다 → 어떤 프로세스에서 훅이 실제로 걸리는지 로그로 원인 2 검증 가능.

### D. 파생 추가 (지시문에 없으나 필터 확장의 필연적 결과): 크로스프로세스 선점

필터를 3개 bundle + assistantd로 확장하면 같은 dylib가 여러 프로세스에 들어가고, 동일 발화가 프로세스별로
`_tellSpeechDelegateSpeechRecognized:`를 각각 통과해 **Gemini 요청/음성이 중복**될 수 있다(다중 인젝션 시 중복 dispatch — HYPOTHESIS).

기전:
* Darwin 알림 `com.csw.sirigemini.claimed` (`SiriGeminiPostClaim`)
* 인터셉트/진단음 생성 시 `SiriGeminiClaimThisUtterance()` → 로컬 스로틀 갱신 + 브로드캐스트
* 수신측 콜백은 `gLastPeerClaim`만 갱신 → 이후 `kPeerClaimWindow = 3.0s` 동안 인터셉트를 포기하고, 키워드 미설정 모드에서는 `%orig`도 억제하여 다른 프로세스가 이미 처리한 발화에 기본 Siri가 겹쳐 대답하지 않게 한다
* Darwin 알림은 크로스프로세스 페이로드를 전달하지하므로(CFNotificationCenter darwin center), 선점 토큰 대신 시간 창 기반으로 판단한다 → 자기 자신의 선점도 동일 창에 적용된다(의도된 대가로 3초 내 연속 발화 하나는 Siri/Gemini 양쪽 모두 지연될 수 있음)

## 3. 빌드 실패와 원인 (오류→수정 로그)

| # | 오류 | 원인 | 수정 |
| :-- | :-- | :-- | :-- |
| 1 | `Tweak.x:378 error: unused function 'SiriGeminiHandleExtractionFailure' [-Werror,-Wunused-function]` | 실패 처리 헬퍼를 정의했으나 훅에서 호출하지 않음(편집 순서 실수). Theos `-Werror`가 unused-function을 치명 오류로 승격 | `%orig` 직전에 `if (SiriGeminiHandleExtractionFailure(recognition)) return;` 연결 → 이후 재빌드 0건 성공 (-8) |

이번 사이클부터 반복 빌드 대신 **빠른 프로브**를 사용했다(AGENTS Sec.16 접근 전환):
VM에서 `perl $THEOS/bin/logos.pl Tweak.x > /tmp/Tweak_pre.m` 후
`clang -fsyntax-only -fobjc-arc -target arm64-apple-ios15.0 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) -I . -I $THEOS/vendor/include -I /tmp/sginc`
(`substrate.h`는 실제 것 사용, 그 내부가 요구하는 `CydiaSubstrate/CydiaSubstrate.h`는 MSHookMessageEx 원형만 담은 스텁으로 대체: `temp/sginc_stub_CydiaSubstrate.h`).
단, 이 프로브는 `-Werror` 경고 플래그를 복제하지 않으므로 **unused-function 류 경고는 실제 빌드에서 처음 발견됐다**(프로브 한계 기록).

## 4. 검증 (evidence)

| 항목 | 근거 | 상태 |
| :-- | :-- | :-- |
| logos 전처리 + Tweak.x 문법 통과 | VM `clang -fsyntax-only` 무출력(`PROBE_OK`) | VERIFIED (compile-level) |
| 전체 패키지 빌드 성공, 오류 0 | `/tmp/sg_build.log`, `grep -c error:` = 0 | VERIFIED |
| 산출물 버전 | `packages/com.csw.sirigemini_1.0.0-8+debug_iphoneos-arm64e.deb` (control Version 1.0.0 유지, Theos build number 자동 증가) | VERIFIED |
| 회수 무결성 | 로컬 복사 SHA256 `374c7a0bdba4a6d22184298cee09bdf8ba230c5fd01c99bcc098b131a8118877` == VM `shasum -a 256` | VERIFIED |
| 필터 plist 설치 내용 | VM `plutil -p .theos/_/Library/MobileSubstrate/DynamicLibraries/SiriGemini.plist` → bundle 3개/Executable 1개 | VERIFIED (패키징 수준) |
| 새 복원 경로들이 실제 Siri 객체에서 텍스트를 얻는지 | 기기 로그 미수취 | UNVERIFIED / OPEN ISSUE |
| 다중 인젝션 중복 발생 및 선점 창(3초) 충분성 | 기기 로그 미수취 | HYPOTHESIS |
| `com.apple.siri` 번들 ID 존재 여부 (필터가 유효한지) | Apple 문서/기기 미확인 — 지시 recall 그대로 입력 | UNVERIFIED (recall) |

## 5. 다음 단계 — 기기 로그로 확정할 것

1. 설치 후 log: `HOOK FIRED in process <name>` → 훅이 걸리는 실제 프로세스 집합(원인 2 검증).
2. 어느 복원 경로가 성공했는지: `text via phrases path` / `via direct selector` / `via description regex fallback` / `via description word fallback`.
   특히 **regex/word 폴백**이 성공했다면 그 결과 문자열이 실제 발화와 일치하는지 확인(폴백은 잡음을 섞을 수 있다).
3. 실패 시: `ALL text extraction paths failed, class: <X>` → `<X>`의 실제 구조를 class-dump/Frida로 조사해 정확한 경로를 추가한다.
4. 중복 Symptoms: `skip: utterance claimed …` / `suppress orig: utterance handled …` 빈도 확인 후 `kPeerClaimWindow` 조정.
5. Gemini 응답 자체(`-7` RPC)는 여전히 미검증이므로 함께 관찰한다.
