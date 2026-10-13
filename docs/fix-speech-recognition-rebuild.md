# SiriGemini 음성 인식 파서 (fix_speech_recognition) — 구현·빌드 기록 (2026-10-13)

## 원인 (오케스트레이터 제공 분석)
* `_tellSpeechDelegateSpeechRecognized:` 인자는 문자열이 아닌 `SASSpeechRecognized` 객체.
* 기존 `recognizedText`/`bestText` 셀렉터는 존재하지 않아 추출 nil → 가로챔 미발동.

## 수정 내역 (로컬 src/Tweak.x)
* `#import <dlfcn.h>` + `%ctor` 선두에 `dlopen` 2종
  (AssistantServices, SAObjects — 링크 없음, SDK .tbd 부재).
* `SiriGeminiExtractRecognizedText` 신규:
  `recognition` → `phrases[]` → `tokens[]` → `text` 공백 결합 반환.
  KVC 예외 → @catch 후 클래스명 진단 로그 (`unparsed recognition class:`).
* 훅 본문 교체: 파서 호출 + `Recognized voice text:` 로그.
* 키워드 유연화: `SiriGeminiKeywordMatches` (부분일치 대소문자 무시 + 공백 무시),
  `SiriGeminiStripKeyword` (첫 매칭 위치 제거로 변경).

## 검증 상태 (정직 표기)
* SASSpeechRecognized 경로 주장은 SiriPlus.dylib 역공학의 외부 제공 분석 —
  자체 헤더/디스어셈블/Frida 검증을 거치지 않았으므로
  PROJECT.md에 `EXTERNALLY-SOURCED HYPOTHESIS`로 기록.
* 파서 실패 시 클래스명 로그가 다음 반복의 검증 단서가 됨.

## 빌드 (VM ~/build_sirigemini)
* Tweak.x scp → 첫 빌드 호출 출력이 전송 중단됐으나 VM에서 계속 진행,
  후속 호출로 완료 확인: 에러 0, `packages/com.csw.sirigemini_1.0.0-5+debug_iphoneos-arm64e.deb`.
* `lipo -archs`: dylib·Prefs `arm64 arm64e` VERIFIED.
* 회수 `build/com.csw.sirigemini_1.0.0-5+debug_iphoneos-arm64e.deb`,
  SHA256 `11448229ce6f3ee24bbaf970b89a0705a5099db8f77d223e214fb639455150b8` 일치.

## 기기 확인 요청
설치 후 Siri 호출 시 `[SiriGemini] Recognized voice text:` 로그 (인식 텍스트 출력 여부),
`AFConnection hook enabled/SKIPPED` 로그.
