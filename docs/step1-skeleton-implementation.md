# SiriGemini 1단계 — 소스 스켈레톤 구현 기록 (2026-10-13)

## 생성 파일 (src/ 기준, 총 13개)

| # | 경로 | 역할 |
|---|------|------|
| 1 | `Tweak.x` | AFConnection 인식 콜백 훅 + 키워드/토글 분기 + GeminiWebClient 호출 + 응답 발화 |
| 2 | `GeminiWebClient.h` | 클라이언트 인터페이스 + plist/쿠키 키 상수 |
| 3 | `GeminiWebClient.m` | plist 쿠키 읽기 + NSURLSession 비동기 통신 + 메인큐 콜백 |
| 4 | `SiriGemini.plist` | dylib inject filter (SpringBoard + assistantd) |
| 5 | `Makefile` | RootHide 스킴, arm64/arm64e, tweak + Preferences aggregate |
| 6 | `control` | 패키지 메타 (com.csw.sirigemini 1.0.0 iphoneos-arm64e) |
| 7 | `layout/DEBIAN/control` | 지침 요구 경로의 control 복사본 (동일 내용) |
| 8 | `Preferences/Makefile` | SiriGeminiPrefs bundle 빌드 (UIKit/WebKit/Preferences) |
| 9 | `Preferences/RootListController.h/.m` | On/Off + keyword + Google 로그인 버튼 |
| 10 | `Preferences/LoginWebViewController.h/.m` | WKWebView 로그인 + 쿠키 추출→plist 저장 |
| 11 | `Preferences/Resources/Info.plist` | 번들 메타 (NSPrincipalClass 지정) |
| 12 | `Preferences/Resources/Root.plist` | 설정 UI 스펙 (switch/text/button) |
| 13 | `layout/Library/PreferenceLoader/Preferences/SiriGemini.plist` | 설정 앱 진입점 |

## 설계 결정

* 모든 private 훅은 `%group` + `objc_getClass` 존재 검사 + 조건부 `%init`. 클래스/셀렉터 부재 시 자동 비활성화 + NSLog 표기.
* 인식 텍스트 추출은 다경로 best-effort (NSString / recognizedText / bestText / description).
* 가로챔 시 `%orig` 생략으로 기존 파이프라인 중단. 재진입 가드(`gInGeminiCallback`) + 1초 스로틀로 루프/고빈도 보호.
* 응답 표시는 1단계에서 AVSpeechSynthesizer + `SiriGeminiAnswerNotification` 브로드캐스트; `SAUIAssistantUtteranceView` 훅은 노티 수신 시 setText:/setDetailText: best-effort 반영.
* 쿠키 저장 경로는 `/var/mobile/Library/Preferences/com.csw.sirigemini.plist` (+ `/var/jb` fallback 읽기).
* Gemini RPC 바디/응답 파서는 placeholder (원문 선두 2000자 반환) — 2단계 런타임 캡처로 교체.

## 검증 상태

| claim | type | source | status |
|---|---|---|---|
| AFConnection / -_tellSpeechDelegateSpeechRecognized: | private class/selector | 미조회 | HYPOTHESIS |
| SAUIAssistantUtteranceView | private class | 미조회 | HYPOTHESIS |
| __Secure-1PSID / __Secure-1PSIDTS 쿠키명 | external identifier | recall | UNVERIFIED (recall) |
| gemini.google.com 쿠키 인증 POST 동작 | external behavior | 미검증 | HYPOTHESIS |
| Filter (SpringBoard + assistantd) | inject target | 관례, 미검증 | HYPOTHESIS |
| Makefile/Control RootHide 규격 | build config | docs/roothide 노트 + lockscreenstay 실측 | VERIFIED (convention) |
| 4× plist XML well-formed | syntax | plistlib 파싱 | VERIFIED |

## OPEN ISSUES

1. AFConnection 실제 셀렉터/시그니처 class-dump + Frida 확인 필요.
2. Gemini batchexecute RPC 포맷 런타임 캡처 + 파서 교체 필요.
3. macOS SSH 빌드 + 7단계 산출물 검증 미수행.
4. Git init + eliteguy1/SiriGemini 원격 미수행 (빌드 검증 후 커밋 권장).
