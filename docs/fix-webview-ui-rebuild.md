# SiriGemini WebView UI 개선 (fix_webview_ui) — 구현·빌드 기록 (2026-10-13)

## 문제 현상 (스크린샷 기반, user report — VERIFIED symptom)
* "Google 로그인" 화면에서 WebView 미표시 — 뒤 시스템 화면이 투명하게 비침.
* 수집 쿠키가 게스트 쿠키만 (`NID`, `COMPASS`, `_gcl_au`, `_ga`...) — 로그인 미진행 상태.

## 근본 원인
1. `viewDidLoad` 시점 `self.view.bounds` 0x0 + autoresizing → WKWebView 0x0 렌더링.
2. `backgroundColor` 미지정 → 투명 배경.
3. `pushViewController` — Settings 스택 종속 (모달 분리가 안전).
4. 기본 WKWebView UA → Google `disallowed_useragent` 차단 가능 (HYPOTHESIS, 예방적 Safari UA).
5. 로딩 피드백 없음.

## 수정 내역 (로컬 src, 3개 파일)
* `Preferences/RootListController.m`:
  - `openGoogleLogin:` → `UINavigationController`로 감싸 `UIModalPresentationPageSheet` 모달 present.
* `Preferences/LoginWebViewController.h`:
  - `spinner` (UIActivityIndicatorView), `cancelAndDismiss:` 추가.
* `Preferences/LoginWebViewController.m`:
  - `view.backgroundColor = systemBackgroundColor`, 좌측 취소 / 우측 완료.
  - `CGRectZero` + `customUserAgent` (Safari 18.0 실기기 문자열) + Safe Area 4변 constraints.
  - 중앙 `UIActivityIndicatorView(Large)` — provisional 시작 시 start, finish/fail 시 stop.
  - 저장 성공 시 얼럿 확인 → 모달 자동 dismiss (실패 시 화면 유지).
  - 기존 하단 "Gemini 열기" 툴바 제거 — 초기 URL이 이미 gemini이며 top/height 제약 없는
    모호 레이아웃이 불량 원인 중 하나였음 (의도적 편차, 보고됨).

## 빌드 (VM ~/build_sirigemini)
* 수정 3파일 scp → `make clean && make package THEOS_PACKAGE_SCHEME=roothide` 에러 0.
* `packages/com.csw.sirigemini_1.0.0-3+debug_iphoneos-arm64e.deb`.
* `lipo -archs`: dylib·Prefs 모두 `arm64 arm64e` VERIFIED.
* 회수 `build/com.csw.sirigemini_1.0.0-3+debug_iphoneos-arm64e.deb`,
  SHA256 `fcf1908e57a571e339713e86a9646bc20662c7993ab55da4eba263372be071e8` 로컬/원격 일치.

## 기기 확인 요청
1. 로그인 화면에 Gemini 페이지 렌더링 여부 (Safari UA로 로그인 차단 해소 여부).
2. 로그인 후 "완료" → 쿠키 N개 감지 얼럿.
