# SiriGemini 1.0.0-7+debug — Gemini Web 실제 RPC(SNlM0e + StreamGenerate) 및 에러 음성 피드백 (2026-10-13)

## 1. 지시·배경

* 지침: `temp/prompt_implement_gemini_rpc.txt`
* 사용자 보고(지침 인용, 로그 직접 확인은 미수행): `"재미야"` 호출 시 **음성 가로채기는 성공**했으나 Gemini 응답이 없어 **완전 무응답**.
  원인으로 지시문이 든 근거: 구 `GeminiWebClient.m`이 `https://gemini.google.com`에 placeholder POST(`q=…`)를 보내 HTTP 4xx,
  그리고 `Tweak.x`가 `answer.length == 0`일 때 어떤 피드백도 하지 않음.

## 2. 구현

### A. `src/Tweak.x` — 무응답 방지 음성 피드백

completion 블록에서 실패 시 음성을 출력하도록 변경(Tweak.x:217-225):

```objc
gInGeminiCallback = NO;
if (answer.length > 0) { NSLog(@"[SiriGemini] answer: %@", answer); SiriGeminiSpeak(answer); }
else {
    NSString *errText = [NSString stringWithFormat:@"제미나이 연결 오류: %@",
                         error.localizedDescription ?: @"응답 없음"];
    NSLog(@"[SiriGemini] error speech: %@ (raw error: %@)", errText, error);
    SiriGeminiSpeak(errText);
}
```

기존 `%orig` 생략 정책 관련 NOTE 주석은 유지했다.

### B. `src/GeminiWebClient.m` — 실제 RPC 파이프라인으로 교체

public API(`sendQuestion:completion:`, `hasLoginCookies`)와 쿠키 로드 로직(전체 `cookieString` 우선 → 1PSID/1PSIDTS 폴백,
`/var/jb` 구형 경로 fallback)은 그대로 보존하고, 전송부를 아래로 대체했다.

1. `fetchSNlM0eWithCookie:completion:` (지침과 동일한 시그니처)
   * `GET https://gemini.google.com/app`, 헤더: `Cookie`, Safari UA(`iPhone OS 18_2 … Version/18.0 Mobile/15E148`), Accept.
   * 정규식 `"SNlM0e\":\"([^\"]+)\"`(ObjC 리터럴)로 토큰 추출. 실패 시 본문에 `accounts.google.com` 포함 여부를 판정하여
     "Google 로그인 쿠키 만료/미인증" vs "SNlM0e 토큰 미발견"을 구분(원격 진단 로그).
2. StreamGenerate POST
   * `https://gemini.google.com/_/BardChatUi/data/assistant.lamda.BardFrontendService/StreamGenerate?bl=<bl>&_reqid=<n>&rt=c`
   * 헤더: Content-Type form-urlencoded, Cookie, Origin, Referer, UA(지침 값).
   * 바디: `f.req=[null,"[[\"<escaped 질문>\"],null,[\"\",\"\",\"\"]]"]&at=<SNlM0e>`
     - 내부 JSON 문자열은 직접 이스케이프(`SiriGeminiJSONEscape`), 외부는 `NSJSONSerialization`(이중 인코딩 보장).
     - percent-encoding은 unreserved 세트(`A-Za-z0-9-_.~`)만 허용하는 자체 인코더 사용.
       (`URLQueryAllowedCharacterSet`는 `&`, `=` 등을 남겨 파라미터가 깨진다 — 이전 placeholder 구현의 잠재 결함이기도 함)
   * `_reqid`는 인스턴스 카운터(`arc4random` 초기값 + 100000 증가). 요청 타임아웃 GET 30s / POST 60s.

### C. 답변 추출: 인덱스 하드코딩 대신 스키마 무관 휴리스틱 (의도적 설계 결정)

Gemini/Bard 응답은 `)]}'` XSSI 가드 + 복수 프레임 연결이고, 답변 문자열의 정확한 중첩 인덱스는 **미확인**이다.
Sec.17(심볼/오프셋 추측 금지)에 따라 인덱스를 추정 하드코딩하지 않고 다음 방식으로 구현:

* `)]}'` 제거 → `SiriGeminiBalancedArrays()`로 문자열/이스케이프를 고려한 균형 JSON 배열 후보 최대 6개 추출
* 각 후보 파싱 → `SiriGeminiCollectAnswerCandidates()` 재귀 순회. 문자열이 `[`로 시작하면 추가 JSON 디코딩(이중 인코딩 해제)
* 답변 아닌 것 제외 휴리스틱(`^[A-Za-z0-9_\-.]+$`, URL, `boq_assistant`, `/_/BardChatUi`, `SNlM0e`, `wrb.fr`)
* 자연어 선호: 공백 포함 + 최장 문자열 우선
* 전부 실패 시 원문에서 인용부호 안 40자 이상 블록 추출(`SiriGeminiReadableBlockFallback`), 그리고 **raw 선두 500자 로그**로 스키마 캡처 가능하게 함

### D. 토큰 캐시와 무효화

* `gCachedSNlM0e` / `gCachedBL` (+ `gCacheKeyCookie`) 인메모리 정적 저장(지침 요구).
* 캐시는 **동일 쿠키 문자열과 일치할 때만** 재사용 → `__Secure-1PSIDTS` 회전 시 자동 무효화.
* 캐시 토큰으로 실패하면 캐시 폐기 후 SNlM0e 재조회, POST는 **1회만** 재시도(무한 루프 방지).

## 3. 빌드 과정의 오류와 정확한 원인 (오류→수정 로그)

`make package` 첫 시도에서 `GeminiWebClient.m` 컴파일 실패. 원인은 전량 내 ObjC 문법 실수였다(프로토콜/SDK 문제 아님):

| # | 위치 | 잘못된 코드 | 원인 | 수정 |
| :-- | :-- | :-- | :-- | :-- |
| 1 | `rangeAtIndex` 호출부 4곳 (155, 276, 280×2) | `[m rangeAtIndex(1)]` | Objective-C 메시지 전송은 `rangeAtIndex:1`(콜론+인자). 괄호 호출 폼은 Swift/C# 구문 → clang "expected ']'" | `rangeAtIndex:` 콜론 폼으로 치환 |
| 2 | 위 수정 후 155행 | `[ [raw substringWithRange:[m rangeAtIndex:1] \n stringBy… ] stringBy… ]` | 개행으로 이어진 중첩 send에서 닫는 대괄호 부족 → 셀렉터가 `substringWithRange:stringByReplacingOccurrencesOfString:withString:`로 병합됨 | 3문장 평탄화로 재작성(`[raw substringWithRange:…]`, `[s stringBy…:]` ×2) |
| 3 | sendQuestion 캐시 검사 (427행) | `([gCachedSNlM0e.length > 0 && … && [gCacheKeyCookie isEqualToString:…]])` | 대괄호를 **그룹핑**으로 오용(message send 자리에 피연산자만 있는 형태) → "expected identifier" | 소괄호로 그룹핑, 메시지 send는 `[gCacheKeyCookie isEqualToString:]`만 유지 |

수정 절차 개선(AGENTS Sec.16/17.5 반영): `make package`(arm64+arm64e 전부 컴파일, 수 분)를 반복하는 대신
VM에서 `clang -fsyntax-only -fobjc-arc -target arm64-apple-ios15.0 -isysroot $(xcrun --sdk iphoneos --show-sdk-path)`로
**문법만 수 초 만에 검증**한 뒤 전체 빌드를 진행했다(무출력 = 통과).

### 정정 (Fact-Check Gate)

세션 도중 "`gCachedSNlM0e`가 미선언 상태이며 파일이 두 개 구현의 혼합본"이라는 진술을 했다. 이는 **잘못된 판단**이었다:
VM `grep -rn gCachedSNlM0e GeminiWebClient.m` 결과 정적 선언은 `GeminiWebClient.m:33`에 실제로 존재했고,
실제 실패 원인은 위 표의 ObjC 문법 3종뿐이었다(위 오류 목록의 진단이 그 증거). 혼합본 가능성도 배제됐다.

## 4. 검증 (evidence)

| 항목 | 근거 | 상태 |
| :-- | :-- | :-- |
| `GeminiWebClient.m` 문법/타입 통과 | VM `clang -fsyntax-only …` 무출력 | VERIFIED (compile-level) |
| 전체 패키지 빌드 | `make clean && make package THEOS_PACKAGE_SCHEME=roothide` → 로그 내 `error:` 0건, 경고는 기존 `ld: warning: -multiply_defined is obsolete` 4건뿐 | VERIFIED |
| 산출물 이름/버전 | `packages/com.csw.sirigemini_1.0.0-7+debug_iphoneos-arm64e.deb` (control Version 1.0.0 유지, Theos build number 자동 -7) | VERIFIED |
| 회수/무결성 | 로컬 `build/` 복사 + SHA256 remote(`shasum`) == local(`Get-FileHash`) = `b2424c65b00fb662f1ac687f9fd9774c516341799fc9736dd717e59a531abfad` | VERIFIED |
| SNlM0e/StreamGenerate/f.req/bl 파라미터의 실제 유효성 | 기기 HTTP 캡처·로그 미수행 (지침 recall 기반) | **UNVERIFIED** |
| 응답 파싱 휴리스틱의 실응답 정확성 | 실응답 미캡처 → `raw response head` 로그로 다음 반복에서 확정 예정 | OPEN ISSUE |
| `-7` 설치 후 발화→음성 응답 동작 | 기기 테스트 미수행 | OPEN ISSUE |

## 5. 다음 단계(디바이스 캡처로 확정할 것)

1. 기기 설치 후 로그 확인: `SNlM0e acquired (len=…, bl=…)`, `StreamGenerate POST (bl=…, reqid=…, freqLen=…)`,
   `answer parsed (…)`, 또는 실패 시 `no answer (status=…, dataLen=…)` + `raw response head for capture analysis`.
2. 그 raw 헤더로 실제 응답 스키마(정확한 인덱스 경로)를 확정하고 휴리스틱 파서를 정확한 경로 파서로 교체.
3. 로그에 `loginRedirect=1`이 잡히면 쿠키 만료 → Preferences 재로그인 또는 쿠키 갱신 정책 추가 필요.
4. 음성 출력은 AVSpeechSynthesizer 기반(best-effort)이며 화면 표시(`SAUIAssistantUtteranceView`)는 여전히 가설 훅이다.
