# SiriGemini — PROJECT.md

> `D:\llama agent\tweak\sirigemini` 프로젝트 규격서 및 현재 상태 문서 (authoritative handoff).

## 1. 프로젝트 기본 정보

* **프로젝트:** SiriGemini (`com.csw.sirigemini`)
* **로컬 경로:** `D:\llama agent\tweak\sirigemini`
* **Working Directory:** `D:\llama agent\tweak\sirigemini\src`
* **Git 저장소:** 초기화됨 (로컬 `.git`, remote `https://github.com/eliteguy1/SiriGemini.git` — 본 세션 `git remote -v` 실측). `-6/-7/-8` 변경분은 미커밋
* **GitHub:** `eliteguy1/SiriGemini` (remote 설정 확인됨 / push 및 저장소 존재 여부는 실측 미확인)
* **타겟 환경:** iOS 18.7.1 / RootHide (Dopamine 3) / `iphoneos-arm64e`
* **지원 아키텍처:** `arm64`, `arm64e`
* **현재 패키지 버전:** 1.0.0 (control) / 빌드 산출물 `1.0.0-9+debug` (Theos debug build number)
* **프로젝트 상태:** 훅 강제 초기화(-6), Gemini Web RPC + 에러 음성 피드백(-7), 텍스트 복원 다층화 + 필터 확장 + 크로스프로세스 선점(-8), **진단 HUD(팝업/햅틱) + AFConnection 표준 직접 훅(-9)** 반영 (2026-10-13). 원인은 미규명: `-8`과 `-9`의 바인딩 경로는 사실상 동일하므로(생성 코드 실측) HUD 팝업으로 "주입 실패 vs 클래스 미발견"을 분리 판정해야 함
* **빌드 산출물:** `build/com.csw.sirigemini_1.0.0-9+debug_iphoneos-arm64e.deb` (SHA256 `f6780d47…19f5e9`, 로컬/VM 일치)

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

| `1.0.0-9+debug` | 2026-10-13 | 진단 HUD 추가: `CFUserNotificationDisplayAlert`(SpringBoard 팝업 `SiriGemini v1.0.0-9` / 프로세스명 / AFConnection 발견 여부) + 사운드 1003, 훅 진입 시 햅틱 `AudioServicesPlaySystemSound(1519)`. AFConnection을 `%group` 없이 최상위 `%hook`로 전환하고 `%init(_ungrouped)` 호출을 자체 nil 검사(`SiriGeminiInstallAFHook`) 뒤로 배치, `UIApplicationDidFinishLaunchingNotification`에서 설정 리로드+바인딩 재시도. `SAUIAssistantUtteranceView`는 클래스 부재 프로세스 크래시를 피해 `%group` 조건부 유지(의도적 편차) | 빌드 성공(오류 0), SHA256 로컬/VM 일치(`f6780d47…19f5e9`), AudioToolbox 링크 확인(`otool -L`), 팝업·햅틱 런타임 미검증 |

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
| 리스프링 후 SpringBoard에서 `SiriGemini v1.0.0-9` 팝업 표시, 발화 시 햅틱(1519) 발생 | runtime behavior | 기기 미테스트 | OPEN ISSUE |

## 6. 다음 단계 (OPEN ISSUES)

0. **HUD로 원인 분리(-9 최우선):** 리스프링 후 팝업/진단 확인 → (a) 팝업 없음 = dylib 주입 자체 차단(필터/plutil·RootHide 허용 확인), (b) 팝업+`AFConnection: 발견됨` = 바인딩 시도됨 → 발화 시 햅틱/`HOOK FIRED` 로그로 셀렉터 유효성 판정, (c) 팝업+`미발견` = AssistantServices 지연/미로드. 상세 판정표: `docs/diagnostic-alert-and-direct-hook.md` §6

1. 기기 로그로 훅 실제 진입 프로세스 확정: `HOOK FIRED in process <name>` (원인 2 검증).
2. 복원 성공 경로 확인: `text via phrases path` / `via direct selector` / `via description regex fallback` / `via description word fallback`. 정규식·단어 폴백 결과이면 잡음 여부를 반드시 확인할 것. 실패 시 `ALL text extraction paths failed, class: <X>` → `<X>` 구조를 class-dump/Frida로 조사해 정확한 경로 추가.
3. 다중 인젝션 동작 확인: `skip: utterance claimed …`, `suppress orig: utterance handled …` 빈도로 `kPeerClaimWindow = 3.0s` 적정성 판단(지연/누락 발생 시 조정).
4. StreamGenerate 요청/응답 스키마·`bl` 값 확정(`SNlM0e acquired`, `StreamGenerate POST …`, `answer parsed`, `raw response head`) — 여전히 미검증.
5. `-9` 포함 기기 설치·동작 테스트 미수행(설치는 사용자 수행/아이피 대기). 팝업 미표시 시 설치 경로·필터 매칭부터 점검(`dpkg -l`, plist plutil, RootHide 금지 목록).
6. Git: remote는 `https://github.com/eliteguy1/SiriGemini.git`로 설정돼 있고(`git remote -v` 실측) `-6/-7/-8` 변경분이 **미커밋**. 커밋·push는 사용자 명시 요청 시에만 수행한다.
