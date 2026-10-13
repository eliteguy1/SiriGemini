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
* **현재 패키지 버전:** 1.0.0 (control) / 빌드 산출물 `1.0.0-1+debug` (Theos debug suffix)
* **프로젝트 상태:** 2단계 RootHide 빌드 성공 (2026-10-13), runtime 미검증
* **빌드 산출물:** `build/com.csw.sirigemini_1.0.0-3+debug_iphoneos-arm64e.deb` (WebView UI 개선판, SHA256 `fcf1908e…71e8`)

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

## 5. 검증 상태 (Fact-Check Gate)

| claim | type | verification source | status |
| :--- | :--- | :--- | :--- |
| `AFConnection -_tellSpeechDelegateSpeechRecognized:` 존재/시그니처 | private selector | 미조회 (헤더/디스어셈블/런타임 필요) | HYPOTHESIS |
| `SAUIAssistantUtteranceView` 클래스 존재 | private class | 미조회 | HYPOTHESIS |
| Gemini web endpoint `https://gemini.google.com` + 쿠키 인증 동작 | external behavior | 미검증 | HYPOTHESIS |
| `__Secure-1PSID` / `__Secure-1PSIDTS` 쿠키명 | external identifiers | recall, 미검증 | UNVERIFIED (recall) |
| THEOS_PACKAGE_SCHEME=roothide, ARCHS=arm64 arm64e | build config | `docs/roothide-theos-build-and-verification.md` + lockscreenstay 실측 | VERIFIED (config convention) |

## 6. 다음 단계 (OPEN ISSUES)

1. `AFConnection` 실제 셀렉터/시그니처를 기기 헤더·disassembly·Frida 런타임으로 확인할 것.
2. Gemini `batchexecute` RPC 파라미터/응답 파싱을 런타임 캡처로 확정할 것 (현재 스켈레톤은 placeholder).
3. 기기 설치·동작 테스트 미수행 (Siri 가로챔/로그인 쿠키/응답 표시).
4. Git init + `eliteguy1/SiriGemini` 원격 확인/생성 미수행.
