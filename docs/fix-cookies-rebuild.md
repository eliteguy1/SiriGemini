# SiriGemini 쿠키 개선 (fix_cookies) — 구현·빌드 기록 (2026-10-13)

## 문제 현상 (기기 실측, user report — VERIFIED symptom)
설정 → SiriGemini → "Google 로그인"에서 로그인 후 "완료" 탭 시
`"로그인 쿠키를 찾지 못했습니다..."` 얼럿 발생.

## 원인 분석
1. 초기 로드 URL이 `accounts.google.com/` — Gemini 쿠키(`__Secure-1PSIDTS` 등)는
   `gemini.google.com` 접속 시 발급. 계정 관리 화면에 머물러 쿠키 미발급 (HYPOTHESIS → 코드 경로상 정합).
2. 판정 조건 `psid && psidts` 엄격 — 세션에 따라 1PSIDTS 없이 발급되는 경우 실패.
3. RPC가 2개 쿠키만 전송 — 전체 세션 쿠키 필요 시 401/403 가능 (HYPOTHESIS).

## 수정 내역 (로컬 src, 3개 파일)
* `Preferences/LoginWebViewController.m`:
  - 초기 URL → `https://gemini.google.com/` (미로그인 시 자동 로그인 유도).
  - `saveCookiesAndFinish` 전면 개선: `.google.com`/`gemini.google.com` 쿠키 전체 수집,
    핵심 4종(SID, __Secure-1PSID, __Secure-3PSID, __Secure-1PSIDTS) 중 1개 이상이면 성공,
    `"name=value; ..."` 전체 문자열을 `prefs[@"cookieString"]`에 저장 (+ 기존 2키 호환 저장).
  - 성공 얼럿에 쿠키 개수 + 핵심 4종 O/X 표시, 실패 얼럿에 수집된 쿠키명 표시, NSLog 진단 로그.
  - `didFinishNavigation`에서 gemini 도달 여부 로그.
* `GeminiWebClient.h/.m`:
  - `SiriGeminiCookieStringKey` (`@"cookieString"`) 추가.
  - `hasLoginCookies`: `cookieString.length>0 || psid.length>0`.
  - `sendQuestion`: `cookieString` 우선 전체 주입, 없으면 기존 2쿠키 폴백, 둘 다 없으면 code -2.

## 빌드 (VM ~/build_sirigemini)
* 수정 3파일 scp 동기화 → `make clean && make package THEOS_PACKAGE_SCHEME=roothide`.
* 결과: 에러 0, `packages/com.csw.sirigemini_1.0.0-2+debug_iphoneos-arm64e.deb`.
* `lipo -archs`: dylib·Prefs 모두 `arm64 arm64e` VERIFIED.
* 회수: `build/com.csw.sirigemini_1.0.0-2+debug_iphoneos-arm64e.deb`,
  SHA256 `9d642445c33962550f70bb677c7357974823902dbef74b78d49d92daa618df17` 로컬/원격 일치 VERIFIED.

## 잔여 검증 (기기 필요)
1. WebView 로그인 → "완료" 시 쿠키 N개 감지 얼럿 확인.
2. Gemini RPC 401/403 여부 — 있으면 batchexecute 포맷 확정 작업으로 이관.
