# SiriGemini — PROJECT.md

> `D:\llama agent\tweak\sirigemini` 프로젝트 규격서 및 현재 상태 문서 (authoritative handoff).

## 1. 프로젝트 기본 정보

* **프로젝트:** SiriGemini (`com.csw.sirigemini`)
* **로컬 경로:** `D:\llama agent\tweak\sirigemini`
* **Working Directory:** `D:\llama agent\tweak\sirigemini\src`
* **Git 저장소:** 미초기화 (1단계 스켈레톤 작성 후 초기화 예정)
* **GitHub:** `eliteguy1/SiriGemini` (미확인 — 원격 생성 여부 OPEN)
* **타겟 환경:** iOS 18.7.1 / RootHide (Dopamine 3) / `iphoneos-arm64e`
* **지원 아키텍처:** `arm64`, `arm64e`
* **현재 패키지 버전:** 1.0.0 (control) / 빌드 산출물 `1.0.0-7+debug` (Theos debug build number)
* **프로젝트 상태:** 키워드 가로채기 + 훅 강제 초기화(-6), Gemini Web RPC 구현 및 에러 음성 피드백(-7) 반영 (2026-10-13). 사용자/지침 보고 기준 음성 가로채기는 성공, 응답 무음 → -7에서 RPC+피드백으로 해결 시도 (직접 로그 확인은 미수행). **RPC 프로토콜/응답 파싱은 기기 캡처 미검증**
* **빌드 산출물:** `build/com.csw.sirigemini_1.0.0-7+debug_iphoneos-arm64e.deb` (SHA256 `b2424c65…31abfad`, 로컬/원격 일치)

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

## 6. 다음 단계 (OPEN ISSUES)

1. `AFConnection` 실제 셀렉터/시그니처를 기기 헤더·disassembly·Frida 런타임으로 확인할 것.
2. StreamGenerate 요청/응답을 기기 로그(`SNlM0e acquired`, `StreamGenerate POST …`, `answer parsed`, 필요 시 `raw response head`)로 확보하여 실제 응답 스키마(정확한 인덱스 경로)와 `bl` 값을 확정할 것. 현재 파서는 휴리스틱이며 4xx/파싱 실패 시 토큰 갱신 후 1회 재시도한다.
3. 기기 설치·동작 테스트 미수행 (Siri 가로챔 성공 여부는 사용자 보고로만 확인, `-7`의 RPC 응답/음성 피드백은 미테스트).
4. Git 저장소는 초기화되어 있고 remote는 `https://github.com/eliteguy1/SiriGemini.git` (본 세션 `git remote -v` 실측). 커밋/푸시는 사용자 요청 시 수행 — 현재 워킹 트리에 `-6`/`-7` 변경분이 미커밋 상태.
