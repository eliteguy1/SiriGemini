# SiriGemini — PROJECT.md

> `D:\llama agent\tweak\sirigemini` 프로젝트 규격서 및 현재 상태 문서 (authoritative handoff).

## 1. 프로젝트 기본 정보

* **프로젝트:** SiriGemini (`com.csw.sirigemini`)
* **로컬 경로:** `D:\llama agent\tweak\sirigemini`
* **Working Directory:** `D:\llama agent\tweak\sirigemini\src`
* **Git 저장소:** 초기화됨 (로컬 `.git`, remote `https://github.com/eliteguy1/SiriGemini.git`). 2026-10-13 실측: `HEAD = 710a8e5 "v1.0.0-13: Fix TTS engine dealloc via static synthesizer and relax short answer filter"` (author `eliteguy1 <eliteguy1@users.noreply.github.com>`, 2026-10-13 20:12 +0900), 직전 커밋 `649d688`(1.0.0-12+debug), `1a68424`(1.0.0-10+debug). `-13` 변경분(`PROJECT.md`, `src/Tweak.x`, `src/GeminiWebClient.m`, `docs/fix-tts-dealloc-and-short-answer.md`, 빌드 deb 포함 5개 파일)은 해당 커밋에 포함. 이후 본 세션에서 `PROJECT.md` 갱신(§1 상태 실측 반영)과 `docs/build-report-1.0.0-13-6sections.md` 신규 작성 → 이 두 파일은 **미커밋**(2026-10-13 `git status --short` 실측). **커밋/푸시는 에이전트가 수행하지 않았으며**(세션 외부에서 수행됨). 푸시 상태 실측: `git ls-remote --heads origin` → `refs/heads/master = 710a8e5…`(HEAD와 동일), `git status -sb` 선행/지체 없음 → **GitHub 동기화 완료**
* **GitHub:** `eliteguy1/SiriGemini` — 저장소 존재 및 `-13`까지 동기화 실측 확인(`git ls-remote --heads origin` → `master = 710a8e5…`, `git status -sb` 선행/지체 없음)
* **타겟 환경:** iOS 18.7.1 / RootHide (Dopamine 3) / `iphoneos-arm64e`
* **지원 아키텍처:** `arm64`, `arm64e`
* **현재 패키지 버전:** 1.0.0 (control) / 빌드 산출물 `1.0.0-13+debug` (Theos debug build number)
* **프로젝트 상태:** 훅 강제 초기화(-6), Gemini Web RPC + 에러 음성(-7), 텍스트 복원 다층화 + 선점(-8), 직접 훅 전환(-9), 차단형 알림 제거 핫픽스(-10), SiriPlus식 3대 훅으로 Apple 기본 응답 명령 차단(-11/-12), **TTS 엔진 정적 보존(`gSharedSynth`)+메인 큐 발화+ko-KR 음성 + 단문 답변 필터 완화 및 한글 우선 선택(-13)** 반영 (2026-10-13). `-12` 기기 실측으로 음성 가로채기·햅틱·Apple 응답 차단 3종 성공 확인. 무음의 원인("synth 즉시 dealloc")은 미검증 가설이며, 세션 조작(`Playback + DuckOthers`, 미-deactivate) 리스크는 관측 필요
* **빌드 산출물:** `build/com.csw.sirigemini_1.0.0-13+debug_iphoneos-arm64e.deb` (SHA256 `5fb00fd1…ddb55`, 로컬/VM 일치; dylib에 `setCategory:withOptions:error:`·`voiceWithLanguage:`·`stopSpeakingAtBoundary:` 셀렉터 및 `_OBJC_CLASS_$_AVSpeechSynthesizer/Voice` undefined 심볼 존재 확인)

## 2. 핵심 컨셉

유료 API 키 없이 Google 계정 웹 로그인 쿠키(`__Secure-1PSID`, `__Secure-1PSIDTS`)를
`/var/mobile/Library/Preferences/com.csw.sirigemini.plist`에 저장하고,
Siri 음성 인식 결과를 가로채 Gemini Web과 연동하는 트윅.

## 3. 표준 디렉터리 구조

```text
sirigemini\
├── PROJECT.md
├── extracted\      # 원본 .deb 없음 (신규 트윅, 역공학 레퍼런스 없음)
├── src\            # 개발 소스 (Working Directory)
│   ├── Makefile
│   ├── control
│   ├── Tweak.x
│   ├── GeminiWebClient.h / .m
│   ├── SiriGemini.plist            # dylib filter
│   ├── Preferences/                # PreferenceBundle 서브프로젝트
│   └── layout/DEBIAN/control       # 요청 지침 경로의 control 복사본
├── build\          # 빌드 산출물 (미생성)
├── mcp\            # 외부 조사자료 (비어 있음)
├── logs\           # 런타임 로그 (없음)
├── temp\           # prompt_step1.txt 등 임시파일
└── docs\           # 검증 지식 (step1 보고서 예정)
```

## 4. 버전 이력

| 버전 | 일자 | 변경 내역 | 결과 |
| :--- | :--- | :--- | :--- |
| `1.0.0` | 2026-10-13 | 1단계 스켈레톤 (Tweak.x, GeminiWebClient, Preferences, Makefile, control) | 소스 작성 완료 |
| `1.0.0-1+debug` | 2026-10-13 | 2단계 RootHide 빌드 성공 (arm64+arm64e, .jbroot install_name) — 수정 2건: AVFoundation import 추가, AssistantServices 링크 제거 | 빌드 성공, SHA256 로컬/원격 일치 |
| `1.0.0-2+debug` | 2026-10-13 | 쿠키 추출 개선 (gemini 초기 URL, 전체 cookieString 저장/주입, 핵심 4종 중 1개 판정) + 재빌드 성공 | 빌드 성공, SHA256 로컬/원격 일치 |
| `1.0.0-3+debug` | 2026-10-13 | WebView UI 개선 (Safe Area 오토레이아웃, systemBackground, 모달 PageSheet, Safari UA, 인디케이터, 저장 성공 시 자동 닫기, Gemini 툴바 제거) + 재빌드 성공 | 빌드 성공, SHA256 로컬/원격 일치 |
| `1.0.0-4+debug` | 2026-10-13 | 로그인 상태 UI (동적 버튼 라벨 ✓/필요, 상태 푸터, 로그아웃, viewWillAppear reload) + 재빌드 성공 (에러 2건 해결: PSSpecifier.h import, action ivar→propertyForKey) | 빌드 성공, SHA256 로컬/원격 일치 |
| `1.0.0-5+debug` | 2026-10-13 | 음성 인식 파서 (SASSpeechRecognized recognition→phrases→tokens→text, dlopen 2종, 키워드 유연 매칭, 인식 로그) + 재빌드 성공 (에러 0) | 빌드 성공, SHA256 로컬/원격 일치 |

| `1.0.0-6+debug` | 2026-10-13 | 키워드 매칭 전면 유연화(CleanText 호출어 접두사 제거 + anywhere contains, 위치 검사 폐지), %ctor의 instancesRespondToSelector 가드 제거로 AFConnection 훅 강제 초기화, 인식/가로채기 로그 강화. control Version 1.0.0 유지, Theos build number 자동 -6 | 빌드 성공(에러 0), SHA256 로컬/원격 일치, runtime 미검증 |

| `1.0.0-7+debug` | 2026-10-13 | Gemini Web 실제 RPC 구현: GET /app에서 `SNlM0e`(+`bl`) 정규식 추출·쿠키 키드 인메모리 캐시, StreamGenerate POST(`f.req=[null,"[[\"질문\"],null,[\"\",\"\",\"\"]]"]&at=token`), 응답은 이중-JSON 디코딩+재귀 longest-text 휴리스틱 파싱(실패 시 raw 선두 500자 로그). 에러 시 음성 피드백(`제미나이 연결 오류: …`). 컴파일 오류 3종 수정(rangeAtIndex 콜론 폼, 중첩 send 대괄호, 대괄호 그룹핑) | 빌드 성공(오류 0/경고=기존 ld 경고 4건), SHA256 로컬/원격 일치, RPC 프로토콜 runtime 미검증 |

| `1.0.0-8+debug` | 2026-10-13 | 음성 텍스트 복원 다층화(phrases → 직접 키 5종(text/transcription/bestTranscription/bestText/recognizedText) → description 정규식(`text=`/`phrase=`/`token=`) → description 단어추출 `[가-힣A-Za-z]{2,}`), 전 경로 실패 시 클래스명 기록 + 진단 음성(`음성이 인식되었으나 텍스트 복원에 실패했습니다: <class>`) 후 `%orig` 차단. 필터에 `com.apple.siri`, `com.apple.SiriViewService` 추가. 훅 진입 로그 `HOOK FIRED in process …`. 파생: Darwin 알림 `com.csw.sirigemini.claimed` 선점으로 다중 인젝션 중복 답변 억제(3초 창). 오류 1건(unused function → 헬퍼 미연결) 수정 | 빌드 성공(오류 0), SHA256 로컬/VM 일치(`374c7a0b…18877`), 런타임 미검증 |

| `1.0.0-9+debug` | 2026-10-13 | 진단 HUD 추가: `CFUserNotificationDisplayAlert`(SpringBoard 팝업 `SiriGemini v1.0.0-9` / 프로세스명 / AFConnection 발견 여부) + 사운드 1003, 훅 진입 시 햅틱 `AudioServicesPlaySystemSound(1519)`. AFConnection을 `%group` 없이 최상위 `%hook`로 전환하고 `%init(_ungrouped)` 호출을 자체 nil 검사(`SiriGeminiInstallAFHook`) 뒤로 배치, `UIApplicationDidFinishLaunchingNotification`에서 설정 리로드+바인딩 재시도. `SAUIAssistantUtteranceView`는 클래스 부재 프로세스 크래시를 피해 `%group` 조건부 유지(의도적 편차) | 빌드 성공(오류 0), SHA256 로컬/VM 일치(`f6780d47…19f5e9`), AudioToolbox 링크 확인(`otool -L`), **기기 설치 시 무한 리스프링 유발 → `-10`에서 제거됨** |

| `1.0.0-10+debug` | 2026-10-13 | 핫픽스: `CFUserNotificationDisplayAlert`·`SiriGeminiShowAlert`·사운드 1003 완전 삭제(`#import <CoreFoundation/CFUserNotification.h>` 제거), `SiriGeminiReportLoad()`를 로그 전용으로 축소, `kSiriGeminiBuildTag` → `1.0.0-10`. 햅틱(1519)과 dlopen/Darwin 옵저버/지연 바인딩 재시도는 유지(지침 샘플 대비 의도적 편차, §deviation in docs) | 빌드 성공(오류 0), SHA256 로컬/VM 일치(`192655ec…591fb5`), `nm -u`로 CFUserNotification 심볼 0건 확인. 후속 기기 보고에서 햅틱 1519 발생 = 부팅 정상화 + 음성 훅 진입 실증(사용자 보고) |

| `1.0.0-11+debug` | 2026-10-13 | SiriPlus식 3대 훅: 인터셉트 상태(`gIsInterceptingSiri`, `gCapturedQuestion`) + 성공 2차 햅틱 1520 + 답변 후 3초 창 유지, `_invokeRequestTimeoutForReason:` 타임아웃 차단, `_handleCommand:reply:`에서 클래스명 `SAUI`/`AddViews`/`AssistantUtterance` 매칭 시 `%orig` 미호출(Apple 출력 명령 차단), `reply`는 `NSBlock` 확인 후에만 `replyBlock(nil)`. 신규 셀렉터 둘은 **별도 %group으로 분리 후 `instancesRespondToSelector:` 가드 통과 시에만 %init**(미구현 바인딩의 %orig=NULL 크래시 방지). Logos 구문 오류(`%group` 내 `%hook` 누락 → `%orig does not make sense outside a function`) 수정 | 빌드 성공(오류 0), `strings`로 셀렉터·로그 문자열 존재 확인. 런타임 실존 여부는 이 시점엔 미검증 → `-12` 기기 테스트에서 동작 확인됨 |

| `1.0.0-12` | 2026-10-13 | 로그 태그(`kSiriGeminiBuildTag`)를 실제 빌드 번호로 동기화(코드 차이 없음) → 이 빌드로 기기 배포·테스트: 음성 가로채기/햅틱/Apple 응답 차단 성공 확인 | SHA256 `a361fec7…4accde`, dylib strings에 신규 셀렉터 존재(각 2 = 훅+가드), `response hook guard` 로그 추가. **성공 판정 근거는 사용자 보고** |

| `1.0.0-13+debug` | 2026-10-13 | (A) `SiriGeminiSpeak` 개편: `static AVSpeechSynthesizer *gSharedSynth`(정적 보존·재사용), 발화를 메인 큐로 이동, `AVAudioSession` `Playback + DuckOthers` + `setActive:YES`, `ko-KR` 음성, 발화 전 `stopSpeakingAtBoundary:Immediate`, 리플렉션(`objc_getClass`) 제거. (B) 답변 필터: 최소 길이 20→2(토큰/URL 기각은 유지), `SiriGeminiHasHangul()` 도입, 후보 선택 우선순위 `한글→공백→길이`, 폴백 정규식의 `{40,}` 때문에 짧은 답변이 추가로 죽는 결함 발견 → 한글 포함 인용 필드 우선 스캔 추가 + `SiriGeminiUnescapeJSONString()` 분리 | 사전 프로브(`logos` 714줄 / Tweak·GeminiWebClient 각각 syntax OK), 패키지 errors=0, dylib에 3개 셀렉터+신클래스 undefined 심볼 확인, SHA256 로컬=VM(`5fb00fd1…ddb55`), 소스 md5 동기화. 무음 원인 가설은 미검증(관측 대기) |

## 5. 검증 상태 (Fact-Check Gate)

| claim | type | verification source | status |
| :--- | :--- | :--- | :--- |
| `AFConnection -_tellSpeechDelegateSpeechRecognized:` 존재/시그니처 | private selector | 미조회 (헤더/디스어셈블/런타임 필요) | HYPOTHESIS |
| 인자가 `SASSpeechRecognized`이며 `.recognition.phrases[].tokens[].text` 경로로 텍스트 복원 | private object graph | SiriPlus.dylib 역공학 분석 (오케스트레이터 제공, 자체 미검증) | EXTERNALLY-SOURCED HYPOTHESIS |
| `SAUIAssistantUtteranceView` 클래스 존재 | private class | 미조회 | HYPOTHESIS |
| Gemini web endpoint `https://gemini.google.com` + 쿠키 인증 동작 | external behavior | 미검증 | HYPOTHESIS |
| `__Secure-1PSID` / `__Secure-1PSIDTS` 쿠키명 | external identifiers | recall, 미검증 | UNVERIFIED (recall) |
| THEOS_PACKAGE_SCHEME=roothide, ARCHS=arm64 arm64e | build config | `docs/roothide-theos-build-and-verification.md` + lockscreenstay 실측 | VERIFIED (config convention) |
| Gemini 프로토콜: `GET /app` → `"SNlM0e":"..."` 추출, `POST /_/BardChatUi/data/assistant.lamda.BardFrontendService/StreamGenerate`, `f.req=[null,"[[\"q\"],null,[\"\",\"\",\"\"]]"]&at=<token>` | external protocol/identifiers | 지침 `temp/prompt_implement_gemini_rpc.txt` recall 기반 — 기기 HTTP 캡처/로그 미확보 | UNVERIFIED (externally-sourced hypothesis) |
| `bl=boq_assistant-bard-web-server_20240519.16_p0` 상수 값 유효성 | external param | recall(구버전 포착값). 대비책: `/app` HTML에서 `"bl":"..."` 동적 추출 후 폴백으로만 사용 (`GeminiWebClient.m`) | UNVERIFIED / HYPOTHESIS |
| 답변 텍스트 인덱스 경로(`parsed[0][2]…`) 확정 | external response schema | 미확정 → 인덱스 하드코딩 대신 이중 JSON 디코딩+재귀 longest-text 휴리스틱, 실패 시 raw 선두 500자 로그로 캡처 가능하게 함 | OPEN ISSUE (설계 의도적 우회) |
| `gCachedSNlM0e` 등 정적 선언/메서드 구조, ObjC 메시지 전송 문법 오류 3종 존재 및 해결 | code state | VM `grep -rn gCachedSNlM0e`(:33 선언 확인), `clang -fsyntax-only`(수정 후 무출력) → 이후 `make package` 오류 0 | VERIFIED (compile-level) |
| `-7`까지 파서 실패 시 조용한 `nil` 반환 → 훅 조건 false → `%orig`(기본 Siri) 실행 | code state | `-7` `src/Tweak.x` 소스 검토: 성공 경로 외 끝의 `return nil;` 단일, 훅은 `if (recognizedText && …)` 구조 | VERIFIED (code-level) |
| 다중 프로세스 동시 주입 시 동일 발화 중복 dispatch/중복 음성 | runtime behavior | 미측정. 필터 확장(-8)으로 파생된 위험 → Darwin 선점(3초 창)으로 완화 시도 | HYPOTHESIS |
| `com.apple.siri`, `com.apple.SiriViewService` bundle ID의 실제 매칭 | external identifiers | 지시 recall 입력. plist가 패키지에 포함된 것(plutil)만 실측, 기기 주입/매칭 미확인 | UNVERIFIED (recall) / VERIFIED (패키징 포함) |
| `logos.pl + clang -fsyntax-only`(vendor include, CydiaSubstrate 스텁)로 Tweak.x 사전 문법 검증 가능 | build methodology | VM 실측: `PROBE_OK` 후 `make package` 오류 0. `-Wunused-function -Werror=unused-function`을 프로브에 추가해 이전 실패 유형도 잡히도록 개선(-9 사이클 무오류) | VERIFIED (tool chain, 한계 기록) |
| logos는 ungrouped `%init(_ungrouped)`를 호출 지점에 인라인 발행하며 nil 가드가 없고, 별도 자동 설치 생성자도 없다 | Logos/Theos 코드 생성 semantics | VM 실측: `/tmp/Tweak_pre.m` line 592(`{Class … = objc_getClass("AFConnection"); { MSHookMessageEx(…); }}`), `grep -c _logos_init` = 0, MSHookMessageEx 발생 지점 2곳뿐 | VERIFIED (code-level) |
| "`%group`+조건부 `%init`(-8)이 훅 미설치의 원인" → 직접 훅 전환으로 해결된다 | root cause 주장 | 생성 코드 실측: -8과 -9 모두 "클래스 존재 시에만 바인딩" 동일 경로. 전환 자체의 동작 차이 없음 | DISPROVEN (as stated) / root cause OPEN ISSUE |
| `CFUserNotificationDisplayAlert`·`AudioServicesPlaySystemSound` 심볼이 로드 시점에 해결 가능 | link/loader behavior | `otool -L .theos/obj/debug/arm64/SiriGemini.dylib`에 `AudioToolbox.framework` 링크 확인, CoreFoundation은 이미 링크 | VERIFIED (static) / 팝업 실제 표시는 OPEN |
| 리스프링 후 SpringBoard에서 `SiriGemini v1.0.0-9` 팝업 표시, 발화 시 햅틱(1519) 발생 | runtime behavior | 기기 테스트 결과 **팝업 경로가 무한 리스프링을 유발**(-10에서 제거). 햅틱은 미검증 | DISPROVEN (popup as diagnostic — causes respring loop) / OPEN (햅틱) |
| `CFUserNotificationDisplayAlert(timeout=0,…)`는 사용자가 닫을 때까지 호출 스레드를 기다린다(차단형) | API semantics | Apple Docs `cfusernotificationdisplayalert`: "wait for the user to dismiss… Pass `0` to have the dialog never time out" | VERIFIED (docs) |
| `%ctor`(SpringBoard 부팅 중·메인 스레드)에서 위 차단 API 호출 → 부팅 정지 → 워치독 킬 → 무한 리스프링 | causal mechanism | docs(차단 semantics) + `-9` 코드 실측(`%ctor → ReportLoad → ShowAlert`) + 기기 증언(무한 리스프링). kill 신호/10초 수치는 로그 미확보 | VERIFIED (blocking chain) / HYPOTHESIS (watchdog 수치) |
| 음성 훅 진입 정상 작동(햅틱 1519 발생), 하지만 Apple 기본 응답이 그대로 출력됨 | runtime behavior | 사용자 기기 보고(`-10` 이후 진동 확인, "시리입니다" 대답 계속) | VERIFIED (observed, single report) |
| `AFConnection`의 `- _invokeRequestTimeoutForReason:` / `- _handleCommand:reply:` 실존 및 4번째 인자=블록 | private selectors/types | SiriPlus 역공학 인용(외부 출처)으로 시작. `-12` 기기 테스트에서 Apple 기본 응답("시리입니다")이 사라졌다는 사용자 보고 → 두 훅 중 최소 하나는 유효하게 동작한 셈. 다만 **어느 셀렉터가 막았는지**, reply 타입/블록 여부는 로그 미수집으로 미분리 | VERIFIED (동작 관측, 사용자 보고) / OPEN ISSUE (구체 셀렉터·시그니처 분리) |
| `-12` 무음의 원인은 `AVSpeechSynthesizer` 지역 변수 즉시 dealloc | causal mechanism | dealloc 사실은 코드 실측(지역 변수). "발화 중 해제가 음성을 중단시킨다"는 Apple Docs/SDK 헤더 어디에서도 근거를 찾지 못함(`speech-synthesis.md`, `AVSpeechSynthesis.h` 340줄 grep) | UNVERIFIED (HYPOTHESIS) → `-13` 관측으로 판정. 상세: `docs/fix-tts-dealloc-and-short-answer.md` §2 |
| 사용된 AVFoundation/AVFAudio API 이름 및 `Playback + DuckOthers` 조합의 합법성 | API names / semantics | 디바이스 SDK 헤더 실측(`AVSpeechSynthesis.h` 셀렉터 카운트, `AVAudioSessionTypes.h:450` 상수값, 446–448줄 유효 카테고리 목록) | VERIFIED (local headers) |
| 짧은 답변 폐기 게이트는 필터 함수 하나만이 아니라 폴백 정규식 `{40,}`에도 있었다 | code-level fact | `-12` 소스 실측(`GeminiWebClient.m:105`, 폴백 패턴 157줄) → `-13`에서 두 곳 모두 완화 | VERIFIED (code inspection) — 지시문은 한 곳만 지적 |
| 미구현 셀렉터를 바인딩하면 `%orig`(orig=NULL) 경로가 NULL 점프 위험 → 가드 없이 심지 않는다 | design decision (calling/ABI hazard) | substrate semantics 원문 미확인. 근거: `-9` 교훈 + 로고스 생성 코드가 orig 심볼을 호출하는 구조(생성 코드 실측). 위험 회피 목적의 방어적 설계 | HYPOTHESIS (hazard model) / VERIFIED (코드가 그렇게 구성됨) |
| Logos에서 `%group` 안에 `%hook` 없이 메서드를 두면 `error: %orig does not make sense outside a function`(exit 255, 산출물 0줄) | Logos/Theos parser semantics | VM 실측(`logos_err.txt` + `wc -l` = 0) 후 `%hook AFConnection` 추가 시 `LOGOS_OK`/703줄 | VERIFIED (parser behavior) |

## 6. 다음 단계 (OPEN ISSUES)

0. **`-13` 재테스트 관측 목록** (세부: `docs/fix-tts-dealloc-and-short-answer.md` §5): (a) 음성 청취 + 로그 `Speaking utterance SUCCESS: '<답변>'` → 이 로그가 있는데 소리가 없으면 "요청은 성공, 출력 경로 실패"(세션/SpringBoard 출력 경로 문제), 로그 자체가 없으면 답변 텍스트가 빈 값(`answer parsed`/`speak skipped` 확인)이나 발화 전 차단, (b) 짧은 질문("너 이름이 뭐야")에서 답변이 버려지지 않는지 → `answer parsed: <len> chars`와 실제 발화 문장 비교(짧은 ASCII 쓰레기가 선택되는지도 함께), (c) 음악/다른 앱 재생 중 ducking·Siri 녹음 방해 여부(`Playback + DuckOthers`, `setActive:YES` 후 해제 없음), (d) 크래시 유무(TTS 세션 조작 경로).
   * 이미 관측 완료(-12): 음성 가로채기 성공, 햅틱 발생, Apple 기본 응답 차단 성공. 남은 미분리 항목은 **어떤 셀렉터가 응답을 막았는지**와 `reply` 블록 타입(로그 수집 시 확정).

1. 기기 로그로 훅 실제 진입 프로세스 확정: `HOOK FIRED in process <name>` (원인 2 검증).
2. 복원 성공 경로 확인: `text via phrases path` / `via direct selector` / `via description regex fallback` / `via description word fallback`. 정규식·단어 폴백 결과이면 잡음 여부를 반드시 확인할 것. 실패 시 `ALL text extraction paths failed, class: <X>` → `<X>` 구조를 class-dump/Frida로 조사해 정확한 경로 추가.
3. 다중 인젝션 동작 확인: `skip: utterance claimed …`, `suppress orig: utterance handled …` 빈도로 `kPeerClaimWindow = 3.0s` 적정성 판단(지연/누락 발생 시 조정).
4. StreamGenerate 요청/응답 스키마·`bl` 값 확정(`SNlM0e acquired`, `StreamGenerate POST …`, `answer parsed`, `raw response head`) — 여전히 미검증.
5. 기기 배포는 사용자가 수행 중(`-10`→`-12` 설치·테스트됨, `-13` 대기). `make install THEOS_DEVICE_IP=<IP>` 명령은 사용자 승인 시에만 실행한다. 팝업/HUD는 `-10` 이후 제거된 상태이므로 화면 피드백은 햅틱(1519/1520)과 로그로만 확인한다.
6. Git: remote는 `https://github.com/eliteguy1/SiriGemini.git`(`git remote -v` 실측). 2026-10-13 기준 HEAD=`710a8e5`(v1.0.0-13)로 `-13`까지 커밋 완료, 작업 트리 clean(§1 실측). GitHub 푸시 여부는 미확인(`git status -sb`/remote tracking 재실측 필요). 커밋·push는 사용자 명시 요청 시에만 수행한다.
7. 보고 표준: `AGENTS.md` §18(6대 필수 섹션) 등록 완료 — 템플릿 `D:\llama agent\docs\detailed-reporting-protocol-6sections.md`, `-13` 적용 실例 `docs/build-report-1.0.0-13-6sections.md`.
