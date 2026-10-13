# SiriGemini 로그인 상태 UI (fix_login_status_ui) — 구현·빌드 기록 (2026-10-13)

## 문제 현상 (user report — VERIFIED symptom)
로그인 완료 후에도 설정 화면에 정적 "Google 로그인" 버튼만 표시 — 상태 확인 불가.

## 수정 내역 (로컬 src, 3개 파일)
* `Preferences/RootListController.h`: `logoutGoogle:`, `PSSpecifier.h` import 추가.
* `Preferences/RootListController.m`:
  - `siriGeminiIsLoggedIn` (cookieString 또는 __Secure-1PSID 존재 판정).
  - `specifiers`에서 로그인 버튼 `name` 동적 변경
    (`Google 계정 재연결 (로그인됨 ✓)` / `Google 로그인 (로그인 필요)`),
    미로그인 시 로그아웃 셀 제거, 하단 그룹 `footerText` 상태 문구 동적 구성.
  - `logoutGoogle:` (3키 삭제 + notify + reloadSpecifiers + 얼럿).
  - `viewWillAppear:` → `reloadSpecifiers` (모달 복귀 즉시 반영).
* `Preferences/Resources/Root.plist`: 로그아웃 버튼 셀 추가, 기본 라벨/푸터 상태 문구로 정리 (6 items).

## 빌드 에러 및 수정 (2건, VM 실측 VERIFIED)
1. `definition of 'PSSpecifier' must be imported from module ... before it is required`
   → `RootListController.h`에 `#import <Preferences/PSSpecifier.h>` 추가 (Theos clang modules quirk).
2. `property 'action' not found on object of type 'PSSpecifier *'`
   → 원인: VM 헤더 실측 (`PSSpecifier.h:117`) 결과 `action`은 property가 아닌
     protected ivar (`SEL action;`). `spec.action`/`spec->action` 모두 불가.
   → 해결: `propertyForKey:@"action"` (PSActionKey) 문자열 비교로 식별. 정상 빌드.

## 빌드 결과
* `packages/com.csw.sirigemini_1.0.0-4+debug_iphoneos-arm64e.deb`, 에러 0.
* `lipo -archs`: dylib·Prefs `arm64 arm64e` VERIFIED.
* 회수 `build/com.csw.sirigemini_1.0.0-4+debug_iphoneos-arm64e.deb`,
  SHA256 `e0e9223fbe0a48a38c83c03ae1f03048f5ba47a54dafd51ed017891a750c173e` 일치.

## 기기 확인 요청
설정 진입 시 로그인 상태 라벨/푸터, 로그아웃 동작, 모달 복귀 후 갱신 여부.
