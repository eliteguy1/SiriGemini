# SiriGemini 1.0.0-6+debug — 키워드 가로채기 유연화 + 훅 강제 초기화 (2026-10-13)

## 1. 지시 및 증상

* 사용자 보고: "키워드 동작이 안되는데?" → 음성 키워드(`gKeyword`) 기준 가로채기가 발생하지 않음.
* 지침 파일: `temp/prompt_fix_keyword_intercept.txt` (A: %ctor 강제 init, B: 매칭 유연화, C: 로그 강화, D: VM 재빌드/deb 회수).

## 2. 적용한 수정 (`src/Tweak.x`)

### A. `%ctor` — AFConnection 훅 강제 초기화

* 제거된 가드: `afConn && [afConn instancesRespondToSelector:@selector(_tellSpeechDelegateSpeechRecognized:)]`
* 변경 후: `objc_getClass("AFConnection")`가 non-nil이면 **무조건** `%init(SiriGeminiAFConnection)`.
  로그: `AFConnection hook FORCE-INITIALIZED` / 클래스 부재 시 `AFConnection class NOT FOUND`.
*UtteranceView 훅은 클래스 존재 시 `%init`, 로그 문구만 `INITIALIZED`/`NOT FOUND`로 통일.

### B. 키워드 매칭 전면 유연화

* 삭제: `SiriGeminiKeywordMatches()` (flat-문자열 비교까지 있던 이전 구현).
* 신규 `SiriGeminiCleanText(NSString*)`: 앞뒤 whitespace/newline trim + 호출어 접두사
  (`시리야`, `시리`, `hey siri`, `siri야`, `siri`) 대소문자 무시 반복 제거.
* 신규 `SiriGeminiShouldIntercept()`:
  * `gEnabled` / 재진입 가드(`gInGeminiCallback`) / 빈 문자열 검사 유지.
  * 키워드 비어 있으면 전체 가로챔 (기존 동작 유지).
  * 매칭: 위치 조건(**`location != 0` 폐지**) 없이 `cleaned` 또는 원문이 keyword를 **contains**하면 통과.
* 신규 `SiriGeminiStripKeyword()`: `CleanText` 후 키워드 첫 occurrence 제거 → trim,
  결과가 비면 원문(clean) 반환.
* `gKeyword` 로드 시 `stringByTrimmingCharactersInSet:` 적용, trim 후 빈 문자열이면 `nil` 처리.

### C. preserved guard (지시문에 없던 기존 안전장치 유지 판단)

* 지시문의 새 `SiriGeminiShouldIntercept()` 예시는 dispatch 스로틀
  (`kMinDispatchInterval = 1.0s`, `gLastDispatchTime`)을 포함하지 않음.
* 음성 인식 콜백은 고빈도이므로 AGENTS Sec.6(고빈도 메서드 스로틀/가드)에 따라
  keyword 매칭 성공 시점의 interval 체크는 **의도적으로 보존**함 (동일 발화 중복 dispatch 방지).
* 재진입 가드(`gInGeminiCallback`)와 상호보완적이며, 키워드 매칭 동작 자체에는 영향 없음.

### D. 로그 강화

* `_tellSpeechDelegateSpeechRecognized:` 진입 시:
  `Raw speech object: <class>` → 파싱 후 `Extracted text: '<text>' (enabled: %d, keyword: '%@')`.

## 3. 버전 처리 (AGENTS Sec.10)

* `src/control`의 `Version: 1.0.0`은 **변경하지 않음**.
* Theos 비-final(package) 빌드는 `_THEOS_PACKAGE_DEFAULT_VERSION_FORMAT = base-$(VERSION.INC_BUILD_NUMBER)`를 사용하며,
  build number는 `$THEOS_BIN_PATH/package_version.sh -N <pkg> -V <base>`가 로컬 데이터 디렉터리에 저장된 카운터를 증가시킨다.
  (근거: VM `/Users/csw/theos/makefiles/package.mk` 실측 — `packages/`에 `-1 … -5` 누적 존재 확인)
* 따라서 이번 빌드 산출물은 **재사용되지 않은 신규 패키지 버전 문자열** `1.0.0-6+debug`(이전 `-5`와 다름).

## 4. 빌드 및 검증 (evidence)

| 단계 | 명령/결과 |
| :--- | :--- |
| 동기화 | `scp src/Tweak.x → csw@192.168.1.21:~/build_sirigemini/Tweak.x` (변경파일 1개만) |
| 빌드 | `ssh … 'source ~/.zshrc && export PATH="/usr/local/bin:$PATH" && cd ~/build_sirigemini && make clean && make package THEOS_PACKAGE_SCHEME=roothide'` — 컴/링크 에러 0 (`ld: warning: -multiply_defined is obsolete`는 무해한 상시 경고) |
| 산출물 | `dm.pl: building package com.csw.sirigemini:iphoneos-arm64e → ./packages/com.csw.sirigemini_1.0.0-6+debug_iphoneos-arm64e.deb` |
| 회수 | `build/com.csw.sirigemini_1.0.0-6+debug_iphoneos-arm64e.deb` |
| SHA256 로컬/원격 | `9a9a890f7a046f70527a9c902934e94238c4b7429d3845ce9c6a74e3c7180693` 일치 (MATCH) |

## 5. Fact-Check Gate

| claim | type | verification source | status |
| :--- | :--- | :--- | :--- |
| Theos non-final 빌드는 `package_version.sh`로 build number 자동 증가 → 이번 산출물 `-6` | Theos semantics | VM `/Users/csw/theos/makefiles/package.mk:59-74` + `packages/` 목록 실측 | VERIFIED |
| deb SHA256 로컬/원격 일치 | build artifact integrity | `shasum -a 256` vs `Get-FileHash` | VERIFIED |
| 소스 변경분 컴파일 성공 (arm64/arm64e, tweak+Prefs bundle) | compile evidence | VM 빌드 로그 (에러 없음) | VERIFIED (compile-only) |
| 이전 `%ctor`의 `instancesRespondToSelector:` 가드가 훅 누락(비활성화)의 원인였다 | runtime cause | 기기 로그/런타임 미확보 — 지시문 근거 채택 | UNVERIFIED (recall/directive-sourced hypothesis) |
| 키워드 매칭 유연화로 실제 사용자 발화가 가로채짐 | runtime behavior | 기기 설치·발화 테스트 미수행 | OPEN ISSUE |
| `AFConnection -_tellSpeechDelegateSpeechRecognized:`, `SAUIAssistantUtteranceView` 존재/시그니처 | private selector/class | class-dump/Frida 미확보 (기존 상태 유지) | HYPOTHESIS |

## 6. 다음 단계

1. 기기 설치 후 로그로 확인 필요: `AFConnection hook FORCE-INITIALIZED`,
   `Raw speech object: <class>`, `Extracted text: '…'`, `intercept: …` 라인 유무.
   * 로그가 전혀 안 남는다 → 훅이 로드되지 않은 것 (filter/프로세스 대상 문제).
   * `AFConnection class NOT FOUND` → AssistantServices 로드 시점/클래스명 재확인 필요.
2. 클래스는 존재하나 콜백 미발화면 셀렉터명이 틀린 것 → Frida/class-dump로 실셀렉터 확정.
