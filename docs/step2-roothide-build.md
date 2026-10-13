# SiriGemini 2단계 — macOS VM 동기화 및 RootHide 빌드 기록 (2026-10-13)

## 실행 명령 (순서대로)

1. `ssh csw@192.168.1.21 "mkdir -p ~/build_sirigemini/layout ~/build_sirigemini/Preferences"` (+ Resources/DEBIAN/PreferenceLoader 하위)
2. 개별 scp 15개 (Makefile, Tweak.x, GeminiWebClient.h/.m, SiriGemini.plist, control,
   Preferences/{Makefile, RootListController.h/.m, LoginWebViewController.h/.m,
   Resources/Info.plist, Resources/Root.plist},
   layout/{DEBIAN/control, Library/PreferenceLoader/Preferences/SiriGemini.plist})
3. `ssh csw@192.168.1.21 "chmod -R 755 ~/build_sirigemini/layout/DEBIAN"`
4. `ssh csw@192.168.1.21 'source ~/.zshrc && export PATH="/usr/local/bin:$PATH" && cd ~/build_sirigemini && make clean && make package THEOS_PACKAGE_SCHEME=roothide'`
5. 검증: `dpkg-deb -I/-c`, `lipo -archs`, `otool -l (LC_ID_DYLIB)`, `otool -L`, `ldid -ed`, `shasum -a 256`
6. 회수: `scp csw@192.168.1.21:~/build_sirigemini/packages/*.deb D:\...\build\<full-filename>` + `Get-FileHash` 대조

## VM 환경 (실측 VERIFIED)

| 항목 | 값 |
|---|---|
| Theos | roothide/theos @ 88506b2 (`export THEOS="$HOME/theos"` in ~/.zshrc) |
| ldid | /usr/local/bin/ldid → Cellar/ldid-procursus/2.1.5-procursus7_2 |
| SDK | iPhoneOS16.5.sdk (단일) |
| TARGET | iphone:clang:latest:15.0 → SDK 16.5로 해결 |

## 빌드 에러 및 수정 내역 (2건)

### E1. `ld: framework 'AssistantServices' not found` (FATAL, arm64 링크)
* 원인: `src/Makefile`의 `SiriGemini_PRIVATE_FRAMEWORKS = AssistantServices`.
  SDK에 `AssistantServices.framework` 디렉터리는 있으나 링크용 `.tbd` 없음 (실측).
* 수정: 해당 줄 삭제 + 주석 기록. 당위성: private 심볼 접근을 전부
  `objc_getClass`/`objc_msgSend` 런타임으로만 수행하므로 링크 불필요.
* 재빌드: 통과.

### E2. 잠재 컴파일 에러 사전 제거 (빌드 전 로컬 수정)
* `Tweak.x`가 `AVSpeechSynthesizer` 사용하면서 `<AVFoundation/AVFoundation.h>` 미import.
* 빌드 전 `#import <AVFoundation/AVFoundation.h>` 추가. (Makefile FRAMEWORKS에는 이미 AVFoundation 포함)
* 결과: Tweak.x arm64/arm64e 컴파일 무경고 통과.

## 산출물 정보

* `build/com.csw.sirigemini_1.0.0-1+debug_iphoneos-arm64e.deb` (23,418 bytes)
* SHA256 `ea326efd8ae2184f5062ef531df572405e625e322dc4a26ca408395bfcd2f782` (로컬/원격 일치 VERIFIED)
* control: Package com.csw.sirigemini / Version 1.0.0-1+debug / Architecture iphoneos-arm64e
* 페이로드: `Library/MobileSubstrate/DynamicLibraries/SiriGemini.{dylib(176,192B),plist}`,
  `Library/PreferenceBundles/SiriGeminiPrefs.bundle/{SiriGeminiPrefs(175,120B), Info.plist, Root.plist}`,
  `Library/PreferenceLoader/Preferences/SiriGemini.plist`
* `lipo -archs`: dylib·prefs 모두 `arm64 arm64e` VERIFIED
* `LC_ID_DYLIB`: `@loader_path/.jbroot/...` (슬라이스당 1, 총 2 출력) VERIFIED
* `otool -L`: 시스템 lib + `@loader_path/.jbroot/usr/lib/libsubstrate.dylib` VERIFIED
* `ldid -ed`: 무출력 (엔티틀メント 미임베드). 정상: Substrate dylib은 호스트 프로세스 권한 상속,
  커스텀 엔티틀メント 불필요 (roothide fork 기본 `ldid -S` 서명).

## OPEN ISSUES (3단계 이후)

1. 기기 설치·동작 테스트 (Siri 가로챔 여부 로그 확인이 최우선).
2. AFConnection 셀렉터 HYPOTHESIS — 훅 비활성 로그 시 3단계 역공학 착수.
3. Git init + eliteguy1/SiriGemini 원격 (설치 테스트 후 커밋 권장).
