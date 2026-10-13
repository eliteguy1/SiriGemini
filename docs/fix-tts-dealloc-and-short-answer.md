# SiriGemini 1.0.0-13+debug — TTS 엔진 수명 보존 + 단문 답변 필터 완화 (2026-10-13)

지침: `temp/prompt_fix_tts_and_answer_length.txt`

## 1. 기기 성공/잔여 상태 (사용자 보고)

"시리 → '너 이름이 뭐야' → 햅틱 울림 → 답변 없음 → 시리 종료."
즉 `-12`에서 음성 가로채기·햅틱·Apple 기본 응답 명령 차단은 동작했고, 남은 결함은 **(a) 우리 TTS 음성이 들리지 않음**, **(b) 짧은 답변이 폐기됨** 두 가지.

## 2. Fact-check 게이트

| claim | type | verification source | status |
| :-- | :-- | :-- | :-- |
| 음성 가로채기·햅틱·Apple 응답 차단이 기기에서 동작 | runtime behavior | 사용자 보고(-12 설치 후). 로그 파일은 리포지토리에 미수집 | VERIFIED (user-observed) / OPEN (로그 evidence 부재) |
| 이전 `-12` 구현에서 `AVSpeechSynthesizer`가 함수 종료와 함께 해제됨 | code-level fact | 소스 직접 확인(`-12`: `AVSpeechSynthesizer *synth = [[ttsClass alloc] init];` 지역 변수, ARC 유효) | VERIFIED (code inspection) |
| 그 해제가 발화 중 음성을 중단시키는 것이 무음의 원인 | causal mechanism | 미확인. Apple Docs 검색(`speakUtterance dealloc`, `stopSpeaking*`) + 디바이스 SDK 헤더 `AVSpeechSynthesis.h`(340줄) grep: 수명/dealloc 언급 없음(실측). 단정할 근거 없음 | UNVERIFIED (HYPOTHESIS, 지시 recall) → `-13` 관측으로 판정 |
| API 이름/상수: `setCategory:withOptions:error:`, `voiceWithLanguage:`, `stopSpeakingAtBoundary:`, `AVSpeechUtteranceDefaultSpeechRate`, `AVAudioSessionCategoryOptionDuckOthers`(=0x2) | API names/signatures | 디바이스 SDK 헤더 실측(`iPhoneOS26.0.sdk/.../AVFAudio/Headers/AVSpeechSynthesis.h` 카운트 2/1/2/1, `AVAudioSessionTypes.h:450`) | VERIFIED (local headers) |
| DuckOthers를 Playback 카테고리와 함께 쓰는 것은 합법 | API semantics | `AVAudioSessionTypes.h` 주석(실측 446–448줄): "DuckOthers is only valid with Ambient, PlayAndRecord, **Playback**, MultiRoute" | VERIFIED (header doc) |
| DuckOthers 설정 중 세션이 active인 동안 다른 앱 오디오가 계속 ducked 상태이며 복원엔 deactivate 필요 | API semantics | 같은 헤더 주석(실측 440–442줄). `-13` 구현은 setActive:YES 후 deactivate하지 않음 | VERIFIED (header doc) → 리스크로 §5에 등록 |
| 새 구현이 AVSpeechSynthesizer/Voice를 실제 링크 심볼로 사용(리플렉션 제거) | link-level fact | `nm -u`: `_OBJC_CLASS_$_AVSpeechSynthesizer`=1, `_OBJC_CLASS_$_AVSpeechSynthesisVoice`=1; `strings`: 셀렉터 3종 각 1, 로그 문자열 존재 | VERIFIED (VM 실측) |
| `s.length < 20` 게이트가 "저는 Gemini입니다"(≈12자)를 폐기했다 | code-level fact | `-12` 소스 `GeminiWebClient.m:105`(=`if (s.length < 20) return NO;`) + 폴백 정규식의 `{40,}`(실측 157줄) → 짧은 답변은 두 경로 모두에서 차단 | VERIFIED (code inspection) — 지시문은 게이트 하나만 언급, 실제로는 **두 곳** |

## 3. 구현 내용

### A. `src/Tweak.x` `SiriGeminiSpeak` 전면 개편 (지시문대로)
* `static AVSpeechSynthesizer *gSharedSynth`로 **정적 보존**(첫 호출 때 생성, 재사용).
* 실행을 `dispatch_async(main_queue)`로 이동(기존은 Gemini 완료 큐 스레드에서 직접 호출).
* `[AVAudioSession sharedInstance]`에 `Playback + DuckOthers`(유효 조합임을 헤더로 확인) → `setActive:YES`.
* `voice = ko-KR`, `rate = default`, 발화 전 `stopSpeakingAtBoundary:AVSpeechBoundaryImmediate`(이전 발화 정리), 성공 로그 `Speaking utterance SUCCESS: '<text>'`.
* `objc_getClass("AVSpeechSynthesizer")` 리플렉션 제거 → 직접 생성(링크 실측으로 확인). 브로드캐스트(`SiriGeminiAnswerNotification`)은 메인 큐에서 유지.

### B. `src/GeminiWebClient.m` 답변 필터 (지시문 + 실측된 두 번째 게이트)
* `if (s.length < 20)` → `if (s.length < 2)`. **토큰 정규식·URL/내부상수 기각 목록은 유지**(짧은 쓰레기 차단).
* 새 헬퍼 `SiriGeminiHasHangul()`(비앵커 `[가-힣]` 검색) 도입. 지시문의 `^[가-힣]`(문자열 시작)는 선행 공백/구두점에서 실패하므로 비앵커로 완화한 **의도적 편차**.
* 구조화 파싱 후보 선택 우선순이를 `한글 → 공백 → 길이`로 변경(짧은 한국어 답변이 ASCII 파편에 밀리지 않음).
* 폴백 경로(`SiriGeminiReadableBlockFallback`)의 `{40,}` 정규식 때문에 짧은 답변이 여기서도 죽는 것을 실측으로 확인 → **한글 포함 인용 필드를 우선 스캔**하는 정규식을 추가하고( `{0,240}[가-힣]{0,240}`, 중첩 백트래킹 방지를 위해 상한 고정), 실패 시 기존 40자+ 경로로 폴백. 이스케이프 전처치를 `SiriGeminiUnescapeJSONString()`으로 분리(기존 코드의 두 번째 치환은 `"` → `"`로 실질 무동작이었다는 결함도 여기서 정리).

## 4. 빌드/evidence (VM 실측)

| 항목 | 값/근거 |
| :-- | :-- |
| 사전 프로브 | `LOGOS_OK`(생성 714줄), Tweak `PROBE_OK`(`-Werror` 포함), `GeminiWebClient.m` 단독 `clang -fsyntax-only` 통과 |
| 패키지 | `make clean && make package THEOS_PACKAGE_SCHEME=roothide`, errors=0, 산출물 `com.csw.sirigemini_1.0.0-13+debug_iphoneos-arm64e.deb` |
| dylib 심볼/문자열 | 셀렉터 `setCategory:withOptions:error:` / `voiceWithLanguage:` / `stopSpeakingAtBoundary:` 각 1, 브로드캐스트명 1, 신규 로그 1, 클래스 undefined 심볼 2건 |
| 산출물 해시(로컬=VM) | `5fb00fd1aa6bcac2bd4e4331391e8735f3881da225100c5641efb413133ddb55` |
| 소스 동기화 md5 | `Tweak.x` `6a976c8c…`, `GeminiWebClient.m` `cb78a2c2…` (VM==로컬) |

주의(VM 셸 함정, 재현 방지): 원격에서 `tr -d "\r"`를 쓰면 문자 `r`까지 삭제돼 경로가 깨진다(`build_sirigemini → build_siigemini`). 개행 변환 확인에는 `od -c`/`sed "s/.\r$//"`를 사용할 것. 또 중첩따옴표 때문에 원격 grep의 공백 포함 패턴이 단어 분할될 수 있어, 다중 패턴 검증은 VM에 스크립트를 올려 실행했다(`temp/vm_probe_13.sh`).

## 5. OPEN ISSUE / 리스크

1. **원인 가설 미확정**: `-13`에서도 음성이 안 나오면 "dealloc이 원인"은 기각된다. 그때는 (a) 세션 카테고리가 Siri의 녹음 세션과 충돌, (b) SpringBoard에 TTS 엔진 자체가 없는 케이스(시스템 daemon에서 발화해야 함), (c) Siri 오디오 경로가 우리 세션 변경으로 mute된 경우를 순서로 검증한다. 로그 `Speaking utterance SUCCESS` 유무로 "요청 자체는 성공"을 분리 판정할 것.
2. **SpringBoard 공유 AVAudioSession 조작**: `Playback + DuckOthers`로 메인 프로세스의 전역 오디오 카테고리를 바꾸고 세션을 active로 남긴다(헤더 주석상 deactivate 시까지 ducking 유지). Siri와의 오디오 충돌·음악 앱 영향 가능성이 있으므로 관측 후 `Ambient`(mixable) 또는 세션 미변경 방식으로 축소 검토.
3. **필터 완화의 부작용**: ASCII 2자 이상 문자열도 후보가 된다. 기각 목록(토큰/URL/내부 상수)과 한글 우선 선택이 완충하지만, 짧은 쓰레기가 선택되는 사례가 생기면 `한글 우선 + 비한글은 최소 길이 부활(예: 20)`로 되돌린다.
4. 폴백의 새 정규식은 큰 응답에서 매칭 비용이 증가할 수 있다(상한 240자로 제한). 응답 파싱 시간 로그로 확인 필요.
