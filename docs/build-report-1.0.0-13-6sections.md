# SiriGemini v1.0.0-13+debug 상세 보고 (6대 필수 양식) — 2026-10-13

지침: `temp/prompt_enforce_detailed_reporting.txt` / 프로토콜 원문: `D:\llama agent\docs\detailed-reporting-protocol-6sections.md` (`AGENTS.md` §18 등록)

> 작성 범위 고지: `-13` 코드 구현·초기 패키징은 **이전 컨텍스트 윈도우**에서 수행됐다. 본 문서는 (a) 그 결과물에 대해 현재 세션에서 **직접 재측정**한 정합성 데이터, (b) 소스/커밋에서 직접 확인 가능한 변경 내용만으로 작성한다. 이전 윈도우의 명령어 원문을 그대로 재현하지 못하고, 잔존 증거(VM 로그 파일명·산출물·해시)로만 뒷받침되는 항목은 명시적으로 표시한다.

---

## 1) 작업 전 상태 및 분석 (Pre-check & Analysis)

### 저장소/빌드 상태 (`-13` 직전)
| 항목 | 값 | 근거 |
| :-- | :-- | :-- |
| 패키지 버전 (`src/control`) | `1.0.0`(Theos debug scheme이 `-N+debug`로 자동 증가) | control 실측 관례 + 산출물명 |
| 직전 배포·테스트 빌드 | `com.csw.sirigemini_1.0.0-12+debug_iphoneos-arm64e.deb`, SHA256 `a361fec784…4accde` | `-12` 회수 시 로컬/VM 해시 일치 확인 |
| 직전 기능 커밋 | `649d688 "1.0.0-12+debug: Implement SiriPlus 3 core hooks …"` | 본 세션 `git log --oneline -3` 실측 |
| `-13` 이후 HEAD | `710a8e5 "v1.0.0-13: Fix TTS engine dealloc via static synthesizer and relax short answer filter"`, author `eliteguy1 <eliteguy1@users.noreply.github.com>`, 2026-10-13 20:12 +0900 | `git log -1 --format=…` 실측. **커밋 주체는 에이전트 아님(에이전트는 git 쓰기 명령 미실행)** |

### 사용자 보고 증상 (원문 의미 그대로)
- `-12`에서: 음성 가로채기 성공, 햅틱 발생, Apple 순정 응답("시리입니다") 차단 성공. **그러나 우리 답변 음성이 들리지 않고**, 짧은 질문("너 이름이 뭐야")에 대한 짧은 답변(`저는 Gemini입니다`, ≈12자)가 폐기되어 시리가 종료만 됨.

### 원인 분석 (실측 기반)
| claim | 근거 | 상태 |
| :-- | :-- | :-- |
| 발화 객체가 함수 지역 변수라 ARC에 의해 즉시 해제됨 | `-12` 소스 실측: `AVSpeechSynthesizer *synth = [[ttsClass alloc] init];`(함수 내부) → 스코프 종료 시 release는 언어 규칙상 확정 | VERIFIED (code inspection) — 해제가 무음의 **원인**인지 자체는 아래 항목과 분리 |
| "발화 중 객체 해제 → 음성 중단"이 무음의 원인 | Apple Docs/디바이스 SDK 헤더(`AVFAudio.framework/Headers/AVSpeechSynthesis.h`, 340줄) grep에 lifetime/dealloc 언급 없음(실측). 런타임 로그도 미수집 | HYPOTHESIS (지시 recall) → `-13` 기기 관측으로 판정 예정 |
| 발화가 Gemini 완료 큐에서 메인 스레드 밖으로 나가 UI/오디오 경로와 어긋날 수 있음 | 소스 실측(기존 `SiriGeminiSpeak`는 호출 스레드 그대로 실행, `dispatch_async(main)` 없음) | VERIFIED (code inspection) / 영향은 미검증 |
| 짧은 답변 폐기 게이트는 필터 함수 **하나가 아니라 두 곳** | ① `src/GeminiWebClient.m:105` `-12` 기준 `if (s.length < 20) return NO;`<br>② 폴백 정규식 `SiriGeminiReadableBlockFallback()` 패턴 `"\"((?:[^\"\\\\\\n]|\\\\.){40,}?)\""` → 최소 40자 강제(실측 157줄 부근) | VERIFIED (code inspection) — 지시문은 ①만 지적, ②는 에이전트가 발견·수정 |

### 영향 범위
* 파일: `src/Tweak.x`, `src/GeminiWebClient.m` (+ `PROJECT.md`, 본 문서).
* 프레임워크(링크 실측): `Foundation`, `CoreFoundation`, `UIKit`, **AVFoundation**, **AVFAudio**, AudioToolbox, libobjc, libsubstrate(`@loader_path/.jbroot/usr/lib/`).
* 프로세스: SpringBoard(필터에 포함된 Siri 관련 번들/assistantd 주입 환경) — 발화 자체는 SpringBoard 프로세스에서 AVFoundation 경유.

---

## 2) 실제 실행 명령 (Executed Commands)

### A. 이번 세션에서 직접 실행·확인한 명령
| # | 위치 | 명령(요지) | 목적 | 결과 |
| :-- | :-- | :-- | :-- | :-- |
| 1 | VM | `sed "s/\r$//" /tmp/vm_integrity_13.sh > /tmp/vi.sh; sh /tmp/vi.sh` | `-13` deb 정합성 일괄 실측(size/sha/ar/control/data/roothidepatch/lipo/otool/nm) | 성공(출력은 §5에 전사) |
| 2 | VM | `sh /tmp/vi2b.sh`(패턴을 파일로 올려 `grep -Fc`) | `nm -u`·`strings`의 심볼/셀렉터 존재 확인(`$` 전개 사고 회피) | 성공(§5) |
| 3 | 로컬 | `git log --oneline -3`, `git diff --stat`, `git show --stat 710a8e5`, `git ls-files docs` | 저장소 상태·커밋 내용 확인 | 성공. 작업 트리 clean, HEAD=`710a8e5`(5개 파일 변경) |
| 4 | 로컬 | `(Get-Item …\…_1.0.0-13+debug….deb).Length`, `Get-FileHash -Algorithm SHA256` | 산출물 크기/해시(로컬) | `52786 bytes`, `5fb00fd1aa6bcac2bd4e4331391e8735f3881da225100c5641efb413133ddb55` |
| 5 | VM | `perl /Users/csw/theos/bin/logos.pl Tweak.x > /tmp/pre13.m; wc -l < /tmp/pre13.m; wc -l < Tweak.x` | Logos 전처리 산출물 실측(§4) | `logos_exit=0`, 생성 **714줄** (원본 686줄) |
| 6 | VM | `clang -fsyntax-only -fobjc-arc -target arm64-apple-ios15.0 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) -I . -I $THEOS/vendor/include -I /tmp/sginc -Wunused-function -Werror=unused-function /tmp/pre13.m` | `-13` 소스 즉시 재검증(경고·오류 0 확인) | 성공(무출력 = 오류/지정경고 없음) |
| 7 | VM | `grep -c error: /tmp/sg_build13.log`, `grep -i warning /tmp/sg_build13.log` | 패키지 빌드 로그 판독 | errors **0**, warnings **4**(전부 §4) |

### B. `-13` 패키징 자체에 대해 (이전 윈도우에서 실행, 본 세션 재현 불가 항목)
* VM `/tmp/sg_build13.log`가 존재(2,365 bytes, mtime 10-13 20:05)하고 그 안에 error 0건·경고 4건이 들어있으므로, 리다이렉트 방식의 `make package THEOS_PACKAGE_SCHEME=roothide` 빌드가 수행됐음은 확인된다. 다만 **명령어 원문과 `make clean` 포함 여부는 본 세션에서 재현·확인할 수 없다** → `OPEN (provenance)`.
* 실패 함정 2건(이후 회피책 확립, 공용 문서에 등록): 
  - 원격 zsh에서 존재하지 않는 glob(`*.xm`) 사용 시 명령 자체가 중단됨 → `ls -1` 후 필터로 대체.
  - 중첩 quoting 때문에 `grep -Fc -- "$p"`의 `$p`가 shell에서 전개/분해돼 `_OBJC_CLASS_$_AVSpeechSynthesizer` 검증이 오염됐음(처음 실행 땐 `_OBJC_CLASS_=50` 같은 잘못된 출력) → **패턴을 파일로 전송하고 `grep -Ff` / 스크립트화**로 재실행해 정정(§5에 정정값 전사).

---

## 3) 코드 변경 상세 (Diff & Rationale)

HEAD(`710a8e5`) diff stat 실측: `src/Tweak.x +37/-…`, `src/GeminiWebClient.m +71/-…`, `PROJECT.md`, `docs/fix-tts-dealloc-and-short-answer.md`(신규), 빌드 deb(신규, 52786 bytes).

### 3-1. `src/Tweak.x` — TTS 발화 경로 재작성
Before(`-12` 실측):
```objc
static void SiriGeminiSpeak(NSString *text) {
    if (text.length == 0) return;
    @try {
        Class ttsClass = objc_getClass("AVSpeechSynthesizer");
        if (ttsClass) {
            AVSpeechSynthesizer *synth = [[ttsClass alloc] init];   // 함수 종료 시 해제
            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate;
            [synth speakUtterance:utterance];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SiriGeminiAnswerNotification" object:text];
    } @catch (NSException *e) { NSLog(@"[SiriGemini] Speak failed: %@", e); }
}
```
After(`-13` 실측):
```objc
static AVSpeechSynthesizer *gSharedSynth = nil;

static void SiriGeminiSpeak(NSString *text) {
    if (text.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{                 // 항상 메인 큐
        @try {
            AVAudioSession *audioSession = [AVAudioSession sharedInstance];
            [audioSession setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionDuckOthers error:nil];
            [audioSession setActive:YES error:nil];
            if (!gSharedSynth) { gSharedSynth = [[AVSpeechSynthesizer alloc] init]; }   // 정적 보존·재사용
            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
            utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"ko-KR"];
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate;
            [gSharedSynth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];             // 이전 발화 정리
            [gSharedSynth speakUtterance:utterance];
            NSLog(@"[SiriGemini] Speaking utterance SUCCESS: '%@'", text);
        } @catch (NSException *e) { NSLog(@"[SiriGemini] Speak failed: %@", e); }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SiriGeminiAnswerNotification" object:text];
    });
}
```
Rationale / 근거 헤더 실측(디바이스 SDK `iPhoneOS26.0.sdk/System/Library/Frameworks/AVFAudio.framework/Headers`):
* `AVSpeechSynthesis.h`(340줄) 내 카운트: `stopSpeakingAtBoundary` 2, `speakUtterance:` 1, `voiceWithLanguage:` 2, `DefaultSpeechRate` 1 → 지시문이 쓴 API명이 실제 헤더에 존재(VERIFIED).
* `AVAudioSessionTypes.h:450` `AVAudioSessionCategoryOptionDuckOthers = 0x2`, 그리고 주석 실측 446–448줄 "DuckOthers is only valid with Ambient, PlayAndRecord, **Playback**, MultiRoute" → `Playback + DuckOthers` 조합은 헤더 문서상 합법(VERIFIED).
* 같은 주석 440–442줄: 세션이 active인 동안 다른 앱 오디오가 ducked 유지되고 복원엔 deactivate 필요 → `-13` 구현은 deactivate하지 않으므로 §6 리스크로 등록.
* 리플렉션(`objc_getClass`) 제거 설계 의도: 컴파일 타임 클래스 참조로 바꿔 링크 단계에서 심볼 결손을 노출시키기 위함(§5 `nm -u`에 `_OBJC_CLASS_$_AVSpeechSynthes*/Voice` 존재 확인으로 검증).

### 3-2. `src/GeminiWebClient.m` — 짧은 한국어 답변 보존
Before(`-12`):
```objc
static BOOL SiriGeminiLooksLikeAnswer(NSString *s) {
    if (s.length < 20) return NO;                 // ① 짧은 답변 폐기
    … 토큰 정규식 / URL·내부상수 기각 목록 …
}
// 폴백: 
re = [NSRegularExpression regularExpressionWithPattern:@"\"((?:[^\"\\\\\\n]|\\\\.){40,}?)\"" …];   // ② 40자 미만 원천 차단
```
After(`-13`):
```objc
static BOOL SiriGeminiHasHangul(NSString *s) {                       // 신규 헬퍼(비앵커 검사)
    if (s.length == 0) return NO;
    return [s rangeOfString:@"[가-힣]" options:NSRegularExpressionSearch].location != NSNotFound;
}
static BOOL SiriGeminiLooksLikeAnswer(NSString *s) {
    if (s.length < 2) return NO;                                     // ① 완화(토큰/URL 기각은 유지)
    …
}
// 폴백: 한글 포함 인용 필드를 우선 스캔, 없으면 기존 40자+ 경로
@"\"((?:[^\"\\\\\\n]|\\\\.){0,240}[가-힣](?:[^\"\\\\\\n]|\\\\.){0,240})\""   // 상한 고정으로 백트래킹 억제
// 후보 선택 우선순위: 한글 → 공백 포함 → 길이
```
Rationale: 짧은 답변을 죽이는 게이트가 지시문이 지적한 ①뿐 아니라 폴백 정규식 ②에도 있다는 것을 소스 실측으로 확인해 **지시에 없던 ②를 함께 수정**(의도적 확장). 한글 우선 정렬을 넣은 이유는 `저는 Gemini입니다`(13자) 같은 답변이 더 긴 ASCII 파편에 밀려 선택되는 회귀를 막기 위함.
`^[가-힣]`(지시문 예시는 문자열 시작 앵커) 대신 비앵커 `[가-힣]`를 쓴 것도 의도적 편차: 선행 공백·구두점·이모지를 허용하기 위함.

---

## 4) 빌드 진단 및 경고 (Build Diagnostics & Warnings)

* Logos 전처리(본 세션 재실행): `logos_exit=0`, 산출 **714줄** / 원본 `Tweak.x` 686줄 → 생성 코드 정상.
* clang 즉시 재검증(`-fsyntax-only -fobjc-arc -target arm64-apple-ios15.0`, `-Wunused-function -Werror=unused-function`): **무출력**(문법 오류·미사용 정적 함수 없음). 검증 대상은 Logos 산출 `/tmp/pre13.m`.
* `-13` 패키지 빌드 로그(`/tmp/sg_build13.log`, 2,365 bytes): `grep -c error:` = **0**, warnings = **4**.
  ```text
  ld: warning: -multiply_defined is obsolete        (×4)
  ```
  영향도 분석: Theos가 건네는 구식 `-multiply_defined` 링크 옵션을 최신 `ld`가 무시한다는 경고다. 심볼 해석·산출물 구조와 무관하며, undefined 심볼이나 코드 생성과 연관되지 않는다 → **조치 불요**(Theos toolchain 기인, 프로젝트 소스와 무관). 슬라이스×2 + 두 단계 링크로 4회 반복 출력된 것으로 추정(추정 = HYPOTHESIS).
* 링커/심볼: `nm -u` undefined 총 **178**개(§5의 개별 확인), `otool -L`은 libobjc / Foundation / CoreFoundation / UIKit / AVFoundation / libSystem / **AVFAudio** / AudioToolbox + `@loader_path/.jbroot/usr/lib/libsubstrate.dylib`(arm64·arm64e 각 슬라이스에 동일)를 보여준다 → 발화에 필요한 프레임워크가 실제로 링크돼 있음(VERIFIED).

---

## 5) 산출물 무결성 (Artifact Integrity)

* 경로/명: `build/com.csw.sirigemini_1.0.0-13+debug_iphoneos-arm64e.deb`(로컬), VM `~/build_sirigemini/packages/…` 동일명.
* 크기: **52,786 bytes** (VM `wc -c`=52786, 로컬 `Get-Item .Length`=52786 — 일치).
* SHA256: `5fb00fd1aa6bcac2bd4e4331391e8735f3881da225100c5641efb413133ddb55` — VM `shasum -a 256` == 로컬 `Get-FileHash` **일치(VERIFIED)**.
* FAT 슬라이스: `lipo -info` → `Architectures in the fat file … are: arm64 arm64e`, `file` 출력도 universal(Mach-O dylib ×2) 확인.
* `ar tv` 멤버 순서(GNU-ar 형식 유지):
  ```text
  debian-binary   (4 bytes)      rw-r--r-- 0/0
  control.tar.gz  (360 bytes)    rw-r--r-- 0/0
  data.tar.lzma   (52,233 bytes) rw-r--r-- 0/0
  ```
  → `debian-binary` → `control.tar.*` → `data.tar.*` 순서 정상(VERIFIED).
* control tar: 최상위 엔트리로 `./control`(mode `-rwxr-xr-x`, 278 bytes) 존재 확인(`grep -c "\./\?control$"` = 1). RootHide가 요구하는 루트 레벨 control 충족.
* data tar 항목 수 **14**, `.roothidepatch` 총 **0개**(0바이트 패치도 0개) → 이 트윅은 탈옥 감지 우회용 패치가 없는 정상 단일 dylib 패키지로 RootHide/Sileo 설치 구조에 지장 없음(이전 릴리스부터 동일 패턴).
* dylib 심볼 검증 (`/tmp/u.txt` = `nm -u`, `/tmp/s.txt` = `strings`; fat이라 항목은 슬라이스별 ×2 계상):
  ```text
  undef_total=178
  _OBJC_CLASS_$_AVSpeechSynthesizer   존재 (strings/nm 패턴 확인, CR 오염으로 최초 측정값은 무효 → 파일 기반 grep-Ff로 정정)
  _OBJC_CLASS_$_AVSpeechSynthesisVoice = 2
  _MSHookMessageEx                       = 2      (substrate 바인딩 경로 유지)
  _AudioServicesPlaySystemSound          = 2      (햅틱/알림음 경로 유지)
  CFUserNotificationDisplayAlert         = 0      (-10 핫픽스 상태 그대로, 차단형 API 미사용 확인)
  strings: setCategory:withOptions:error:=2, voiceWithLanguage:=2, stopSpeakingAtBoundary:=2,
           speakUtterance:=2, "Speaking utterance SUCCESS"=2, 빌드 태그 "1.0.0-13"=2
  ```
* 소스 동기화(md5) 및 커밋 포함: HEAD `710a8e5`에 `src/Tweak.x`, `src/GeminiWebClient.m`, 본 문서·`docs/fix-tts-dealloc-and-short-answer.md`, deb가 포함되어 작업 트리 clean(§1).

---

## 6) 영향도 및 잠재적 리스크 (Risks & Regression)

### 타 컴포넌트 영향
1. **AVAudioSession을 SpringBoard 프로세스에서 `Playback + DuckOthers`로 전환하고 active 유지** — 헤더 문서상 유효 조합이지만(§3 실측), 부작용이 크다: 다른 앱 오디오가 우리 세션 동안 ducked되고, 우리는 세션을 deactivate하지 않으므로 복원이 지연/누락될 수 있다. Siri 자체의 오디오 라우팅과 충돌해 오히려 무음이 지속될 가능성도 배제 못 한다(`OPEN ISSUE`).
2. **TTS 엔진 상주**: `gSharedSynth`는 릴리스되지 않고 살아남는다(단 1개). 메모리 영향은 미미하지만, 발화 도중 새 답변이 오면 `stopSpeakingAtBoundary:Immediate`로 이전 발화를 자른다 → 잘린 문장이 들리는 UX 엣지케이스.
3. **발화 스레드 이동**: 기존엔 Gemini 완료 큐에서 직접 발화했다가 메인 큐로 옮겼다. UI 훅(SAUI 계열)과 동일 스레드화가 되어 재진입 순서가 바뀔 수 있다 → `%orig` 호출 빈도/순서에 변화가 생겼을 가능성(관측 필요).
4. **답변 파싱 완화**: ASCII 2자 이상도 후보가 된다. 토큰 정규식(`^[A-Za-z0-9_\-\.]+$`)과 URL/내부 상수 기각 목록, 한글 우선 정렬이 완충하지만 짧은 쓰레기가 선택되는 사례가 생기면 되돌릴 지점(knob)은 `SiriGeminiLooksLikeAnswer()` 의 최소 길이(한글 제외 20 부활)와 폴백 정규식의 `{0,240}` 상한이다.
5. **성능**: 폴백에 추가된 한글 스캔은 응답이 클 때 매칭 비용이 늘어난다(상한 고정으로 폭주는 제한). 파싱 지연 체감 시 로그로 확인 필요.

### 실기기 관측 포인트 (로그 문자열)
| 관찰 | 의미 / 다음 행동 |
| :-- | :-- |
| `Speaking utterance SUCCESS: '<문장>'` | 발화 요청이 AVFoundation에 전달됨. 있는데 소리가 없으면 **출력 경로/세션 문제**(가설 "dealloc 원인" 기각 검토로 전환) |
| `[SiriGemini] Speak failed:` | 예외 발생 → 카테고리/보이스 설정 실패 가능성 확인 |
| `answer parsed`(또는 답변 길이 로그)와 실제 발화 문장 비교 | 짧은 한국어 답변이 살아남았는지 판정. garbage가 발화되면 필터 knob 되돌림 |
| 다른 앱(음악 등) 재생 중 볼륨 저하 지속 여부 / Siri 호출 시 녹음 불량 | DuckOthers+active 유지 부작용 → `Ambient` 또는 세션 미변경 방식 전환 검토 |
| 크래시/리스프링 유무(`log show`, Crab 로그) | TTS·오디오 경로 조작이 SpringBoard를 잡는지 확인 |
| 이전 발화가 도중에 잘리는 체감 | `stopSpeakingAtBoundary:Immediate` 정책 완화(예: 새 답변이 구 발화 종료 후 재생) 검토 |

### 남은 쟁점 (요약)
* 무음의 진짜 원인은 아직 **HYPOTHESIS** 단계이며, `-13` 관측 결과로 판정한다(dealloc 가설 vs 오디오 세션/라우팅).
* Apple 기본 응답을 실제로 막은 셀렉터가 `_invokeRequestTimeoutForReason:`인지 `_handleCommand:reply:`인지는 로그 수집 전까지 미분리(`VERIFIED`=효과만 확인).
* `-13` 패키징 커맨드의 원문 provenance는 이전 컨텍스트 윈도우에 있어 재현 불가(§2-B).
