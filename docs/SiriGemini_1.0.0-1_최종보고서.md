# SiriGemini v1.0.0-1+debug RootHide 신규 트윅 최종 검증 보고서

## 1. 개요 (Overview)
* **프로젝트명:** SiriGemini
* **타겟 환경:** Relaxin / RootHide (Dopamine 3) / iOS 18.7.1 (22H31)
* **지원 아키텍처:** `arm64`, `arm64e` (FAT Binary)
* **패키지 버전:** `1.0.0-1+debug`
* **개발 목적:** 기존 `siriplus` 트윅의 동작 메커니즘을 분석하여, 유료 API 키 대신 **Google 계정 웹 로그인 쿠키(`__Secure-1PSID`, `__Secure-1PSIDTS`)를 활용하는 Google Gemini AI 연동 신규 트윅** 제작.

---

## 2. 확인한 사실 (Verified Facts)
1. **Siri 연동 훅 분석 및 추출 (기존 트윅 역공학 기반)**:
   - `AFConnection`의 음성 인식 콜백 `_tellSpeechDelegateSpeechRecognized:` 훅을 통해 Siri 음성 입력 텍스트를 가로챔.
   - 키워드(또는 전역 활성화) 시 기본 Siri 처리 대신 `GeminiWebClient`로 라우팅.
   - Gemini의 답변 수신 시 `SAUIAssistantUtteranceView` (또는 `AVSpeechSynthesizer`)를 통해 화면 표시 및 음성 TTS 발화 수행.
2. **Google Gemini 웹 인증 아키텍처**:
   - Preferences 번들 내 `WKWebView`를 통해 사용자가 `https://gemini.google.com`에 직접 로그인.
   - `WKHTTPCookieStore`에서 `__Secure-1PSID`, `__Secure-1PSIDTS` 세션 쿠키를 추출하여 Preferences plist(`com.csw.sirigemini.plist`)에 자동 저장.
   - 런타임 dylib가 해당 쿠키를 `Cookie` 헤더에 주입하여 Google Gemini 웹 엔드포인트와 통신.
3. **Theos RootHide 빌드 파이프라인 통과**:
   - VMware macOS 14 빌드 환경(`csw@192.168.1.21`)에서 `make clean && make package THEOS_PACKAGE_SCHEME=roothide` 정상 완료.
   - `arm64` 및 `arm64e` 슬라이스 모두 성공적으로 컴파일 및 링크.

---

## 3. 원인 분석 및 빌드 트러블슈팅 (Root Causes & Solutions)
1. **AssistantServices 프레임워크 링크 실패 (`ld: framework 'AssistantServices' not found`)**:
   - **원인:** Theos iPhoneOS16.5 SDK 내부에 `AssistantServices.framework` 디렉터리는 존재하나 심볼 링크용 `.tbd` 파일이 부재함.
   - **해결:** `Tweak.x` 내부에서 Obj-C 런타임 동적 조회(`objc_getClass`, `%c`) 및 Logos 문법을 사용하므로, Makefile의 `SiriGemini_PRIVATE_FRAMEWORKS = AssistantServices` 링크 지시자를 안전하게 제거하여 빌드 통과.
2. **AVFoundation 헤더 누락**:
   - **원인:** 음성 합성을 위한 `AVSpeechSynthesizer` 사용 시 명시적 `#import <AVFoundation/AVFoundation.h>` 누락 가능성.
   - **해결:** `Tweak.x` 상단에 AVFoundation 헤더 임포트 및 Makefile에 `AVFoundation` 프레임워크 링크 추가.

---

## 4. 패키지 무결성 5대 검증 결과 (Artifact Integrity)

| 검증 항목 | 기준 | 실측 결과 | 적합 여부 |
| :--- | :--- | :--- | :---: |
| **1. 포맷 검증 (GNU ar)** | `!<arch>\n` 매직, `debian-binary` 첫 멤버 | `debian-binary`(4B), `control.tar.gz`(358B), `data.tar.lzma`(22.8KB) | **PASS** |
| **2. Control 구조** | 최상위 `./control`, DEBIAN 접두사 없음 | `./`, `./control` 최상위 직접 위치 확인 | **PASS** |
| **3. Data 구조** | 0바이트 빈 `.roothidepatch` 0개 | 0개 (SpringBoard 세이프모드 위험 원천 차단) | **PASS** |
| **4. Mach-O 구조** | FAT `arm64` + `arm64e`, 중복 RPATH 0개 | `lipo` FAT 확인, 중복 `LC_RPATH` 0개, install_name `@loader_path/.jbroot/...` | **PASS** |
| **5. 패키지 무결성** | 파일 크기 및 SHA256 일치 | 23,418 bytes, `ea326efd8ae2184f5062ef531df572405e625e322dc4a26ca408395bfcd2f782` | **PASS** |

---

## 5. 산출물 정보
* **deb 파일명:** `com.csw.sirigemini_1.0.0-1+debug_iphoneos-arm64e.deb`
* **로컬 보관 경로:** `D:\llama agent\tweak\sirigemini\build\com.csw.sirigemini_1.0.0-1+debug_iphoneos-arm64e.deb`
* **파일 크기:** 23,418 bytes
* **SHA256:** `ea326efd8ae2184f5062ef531df572405e625e322dc4a26ca408395bfcd2f782`
