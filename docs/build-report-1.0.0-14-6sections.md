# SiriGemini v1.0.0-14+debug 상세 보고 (6대 필수 양식) — 2026-10-13

지침: `temp/prompt_fix_performance_and_siri_dismiss.txt` / 프로토콜: `AGENTS.md` §18, 템플릿 `D:\llama agent\docs\detailed-reporting-protocol-6sections.md`
산출물: `build/com.csw.sirigemini_1.0.0-14+debug_iphoneos-arm64e.deb` (52,308 bytes, SHA256 `8439cfdf624b371dad4bb7ca59f013a2320518c4c3f2bd910925929a223020f4`)

---

## 1) 작업 전 상태 및 분석 (Pre-check & Analysis)

### 저장소/빌드 상태 (작업 직전 실측)
| 항목 | 값 | 근거 |
| :-- | :-- | :-- |
| HEAD | `5abcd5b "docs: Add detailed 6-section build report for v1.0.0-13"`, 직전 `710a8e5`(v1.0.0-13) | `git log --oneline -2` 실측 (커밋은 세션 외부에서 수행됨 — 에이전트는 git 쓰기 명령 미실행) |
| 작업 트리 | `-14` 지시 전: 소스 변경 없음(`src/` unmodified), temp 파일만 untracked | `git status --short` |
| 직전 산출물·배포 | `-13+debug`, 52,786 bytes, SHA256 `5fb00fd1…ddb55`(로컬=VM) → **사용자 설치·테스트됨** | §-13 보고서 |
| `-14` 이전 소스 해시(VM=로컬 동일) | `Tweak.x` md5 `6a976c8cfcb884c8c02d61771ab51a28`, `SiriGemini.plist` md5 `4187724f7d5bb302bb3e3cf6d5382061` | VM `md5 -q` / 로컬 `Get-FileHash MD5` 일치 확인 후 편집 시작 |
| 플리스트(수정 전) 실측 | Bundles: `com.apple.springboard`, `com.apple.siri`, `com.apple.SiriViewService` + Executables: `assistantd` | `src/SiriGemini.plist` 원문(19줄) |

### 사용자 보고 증상 (원문 그대로)
> "이 트윅 깔면 시스템이 느려져 그리고 시리 작동하고 너 이름이 뭐야 하면 뭐라고 말하는지 인식하고 그냥 시리가 꺼져"

즉 (A) 시스템 전역 성능 저하, (B) 음성 인식 성공 후 발화 없이 Siri 창 즉시 종료.

### 원인 분석과 지시문 주장의 Fact-Check (§17 게이트)
| # | claim | 유형 | 검증 출처 | 상태 |
| :-- | :-- | :-- | :-- | :-- |
| 1 | SiriPlus는 **오직 `com.apple.springboard`에만** 인젝션된다 | 필터 구성 | 로컬 원본 아티팩트 실측: `tweak/siriplus/extracted/data/var/jb/Library/MobileSubstrate/DynamicLibraries/SiriPlus.plist`(93 bytes) → VM `plutil -convert xml1 -o -` 결과 Bundles = `com.apple.springboard` **하나뿐** | **VERIFIED (primary artifact)** — 지시문 주장이 원본 패키지에서 확인됨 |
| 2 | `assistantd` 인젝션 + 전역 세션 변경이 시스템 지연의 원인 | causal mechanism | 메커니즘 자체를 직접 측정하지 못함(지연 정량 데이터 없음). 다만 (a) 우리가 실제로 SpringBoard 프로세스에서 AVAudioSession을 Playback+DuckOthers로 바꾸고 deactivate하지 않았다는 사실(`-13` 소스 실측), (b) 인젝션 대상 4개 프로세스(-13 이전 plist 실측)는 SiriPlus 대비 명백한 초과 | HYPOTHESIS (원인 귀속) / VERIFIED (우리가 그 코드·필터를 가지고 있었음) → `-14` 기기 관측으로 판정 |
| 3 | `_handleCommand:reply:`에서 `replyBlock(nil)` 호출이 "처리 완료(nil)"로 취급돼 Siri가 즉시 종료된다 | causal mechanism | 우리 코드에 해당 호출이 존재한 사실은 VERIFIED(소스 실측). "nil 응답 → 즉시.dismiss" semantics는 Apple 문서/사설 API 명세에서 미확인, 로그도 없음. 사용자 증상(-13에서 인식 후 종료)과 시간적으로 일치 | HYPOTHESIS (strong, user-symptom-supported) |
| 4 | SiriPlus는 reply 블록을 호출하지 않고 조용히 드롭한다(디스어셈블리 실측 인용) | 외부 RE 주장 | 정적 검증 시도 결과: `SiriPlus.dylib`(fat arm64/arm64e, 463,024 bytes) strings에서 `_handleCommand:` 2회, `_tellSpeechDelegate…` 2회, `"Command of type"` **6회** 존재 → 셀렉터·로그는 실존. 그러나 그 함수 본문이 블록을 호출하는지 여부는 역컴파일하지 못함(정적 분석 2회 한도 내 미해결 → 규칙에 따라 정적 추격 중단) | PARTIALLY VERIFIED (셀렉터/로그 실재) / **UNVERIFIED (reply 드롭 semantics)** |

### 영향 범위
* 파일: `src/SiriGemini.plist`(필터 축소), `src/Tweak.x`(`SiriGeminiSpeak`, `%group SiriGeminiAFCommandBlock` 내 `_handleCommand:reply:`).
* 프로세스/프레임워크: 인젝션 대상이 4개(SpringBoard·Siri bundle 2종) → **SpringBoard 단독**으로 축소. SpringBoard 프로세스 내 AVFAudio/AudioToolbox 링크는 유지(발화·햅틱). assistantd/SiriViewService에는 이제 코드가 로드되지 않는다.

---

## 2) 실제 실행 명령 (Executed Commands)

| # | 위치 | 명령 | 목적 | 결과 |
| :-- | :-- | :-- | :-- | :-- |
| 1 | 로컬/VM | `scp src/SiriGemini.plist → /tmp/siriplus_filter.plist` 후 VM `plutil -convert xml1 -o -` | SiriPlus 실인젝션 필터 확인(claim 1) | 성공: Bundles = springboard 1개. VERIFIED |
| 2 | 로컬/VM | `scp siriplus …/SiriPlus.dylib → /tmp/SiriPlus.dylib`; VM `lipo -info`, `strings > /tmp/sp.txt`, grep 카운트 | SiriPlus 훅·로그 실재 확인(claim 4) | arm64+arm64e; `"Command of type"`=6, `_handleCommand`=2, `_tellSpeechDelegate`=2 (내부 공백 때문에 원격 quoting이 깨져 `grep: of: No such file…` 경고가 떴으나 카운트는 유효. 이후 패턴파일 방식으로 정정 원칙 적용) |
| 3 | 로컬→VM | `scp src/Tweak.x → ~/build_sirigemini/Tweak.x`, `scp src/SiriGemini.plist → …/SiriGemini.plist` | 소스 동기화 | 성공(사후 md5 일치로 확인, §7행) |
| 4 | VM | `plutil -lint SiriGemini.plist; plutil -p SiriGemini.plist` | 필터 축소 문법·내용 검증 | `OK`, Bundles = com.apple.springboard만 존재 |
| 5 | VM | `perl /Users/csw/theos/bin/logos.pl Tweak.x > /tmp/pre14.m`; `wc -l < /tmp/pre14.m` | Logos 전처리 사전 프로브 | `logos_exit=0`, 생성 **707줄**, stderr 파일 비어있음(`cat` 출력 없음) |
| 6 | VM | `clang -fsyntax-only -fobjc-arc -target arm64-apple-ios15.0 -isysroot $SDK -I . -I $THEOS/vendor/include -I /tmp/sginc -Wunused-function -Werror=unused-function /tmp/pre14.m` | `-14` 소스 즉시 문법·경고 검증 | 무출력(통과) |
| 7 | VM | `grep -n AVAudioSession Tweak.x` | 세션 조작 코드 잔존 확인 | 주석 1줄(`-14` 설명)만 남음 → 실제 호출 없음 |
| 8 | VM | `source ~/.zshrc; export PATH=/usr/local/bin:$PATH; cd ~/build_sirigemini && make clean >/dev/null && make package THEOS_PACKAGE_SCHEME=roothide > /tmp/sg_build14.log 2>&1` | 패키지 빌드 | `make_exit=0`, errors **0**, warnings 4(§4), 산출물 `packages/com.csw.sirigemini_1.0.0-14+debug_iphoneos-arm64e.deb` → 수동 태그 `-14`와 일치 |
| 9 | VM | `sh /tmp/vi14.sh`(아래 함정 정후) | 산출물 무결성 + 수정 3종 반영 검증 | 성공(§5 전사) |
| 10 | VM→로컬 | `scp …_1.0.0-14+debug…deb → build/`; 로컬 `(Get-Item).Length`, `Get-FileHash SHA256` | 회수·해시 대조 | 52,308 bytes / `8439cfdf…020f4` = VM과 일치 |
| 11 | VM/로컬 | `md5 -q ~/build_sirigemini/{Tweak.x,SiriGemini.plist}` vs 로컬 MD5 | 소스 동기화 재확인 | `257fe568f248360e6340de2189d1e2f8` / `2b7ec0208e3f807f918fc7a405c99172` 양측 일치 |
| — | 실패 2건 | (a) `echo "== plist lint =="` 형태로 원격에 전달 → zsh가 `==`를 equals-expansion으로 해석해 `zsh:1: = not found`, 명령 전체 미실행. 원인: Windows argv 파싱이 원격 문자열 안의 쌍따옴표를 제거하기 때문. 해결: 마커를 `PLIST_LINT`처럼 대소문자 표기로 변경하고 원격 명령에 쌍따옴표 사용 금지.<br>(b) 로컬 경로 끝 역슬래시(`build\`)로 scp가 `No such file or directory`. 해결: 목적지 파일명을 명시적으로 지정. <br>(c) awk 개행 제거 시도는 `""`argv 소거로 `awk: syntax error` → **스크립트를 로컬에서 LF로 변환 후 scp**해 해결 | 함정 기록(공용 문서에 축적됨) |

---

## 3) 코드 변경 상세 (Diff & Rationale)

변경 파일: `src/SiriGemini.plist`(수정), `src/Tweak.x`(수정). `src/control`의 `Version:`은 `1.0.0` 유지 — 프로젝트 관례상 패키징 접미 `-NN+debug`가 버전 식별자(Theos debug build number 자동 증가)이며, AGENTS §10의 "신규 버전" 요건을 `-13 → -14`로 충족한다.

### 3-1) `src/SiriGemini.plist`
Before:
```xml
		<key>Bundles</key>
		<array>
			<string>com.apple.springboard</string>
			<string>com.apple.siri</string>
			<string>com.apple.SiriViewService</string>
		</array>
		<key>Executables</key>
		<array>
			<string>assistantd</string>
		</array>
```
After:
```xml
		<key>Bundles</key>
		<array>
			<string>com.apple.springboard</string>
		</array>
```
Rationale: 원본 SiriPlus는 springboard 단독 인젝션(§1 claim 1 VERIFIED). 우리는 4개 대상에 로드해 Darwin notification 선점 로직·TTS·AVAudioSession 조작이 데몬까지 번졌고, 사용자 보고상 시스템 지연이 발생했다. 로드 범위를 원본과 동일하게 맞춰 표면적을 줄이는 것이 목표.
파급(명시): `-8`에서 만든 다중 인젝션 선점(`com.csw.sirigemini.claimed`, `kPeerClaimWindow = 3.0`)은 단일 프로세스화되어 사실상 무력화된다(동작 무해, 로그만 감소). **Siri 관련 셀렉터가 SpringBoard 외 프로세스에 살아있을 경우 훅이 아예 안 붙을 수 있다** → §6 관측 지점 (a)로 판정.

### 3-2) `src/Tweak.x` — `SiriGeminiSpeak`에서 오디오 세션 조작 제거
Before:
```objc
            // 다른 오디오를 낮추고(TTS 출력 확보) 세션을 active로 만든다.
            AVAudioSession *audioSession = [AVAudioSession sharedInstance];
            [audioSession setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionDuckOthers error:nil];
            [audioSession setActive:YES error:nil];

            if (!gSharedSynth) { … }
```
After:
```objc
// -14: `AVAudioSession` 카테고리 변경(`Playback + DuckOthers`, 미-deactivate)은 SpringBoard
// 전역 오디오 라outting을 오염시켜 시스템 지연을 유발한다는 사용자 보고(-13 기기 실측 증상)에 따라
// 세션 조작을 전면 제거하고 순수 `AVSpeechSynthesizer` 경로만 남긴다.
            if (!gSharedSynth) { … }
```
Rationale: `-13`에서 우리가 추가한 코드로, 세션을 active로 두고 deactivate하지 않았다(`AGENTS §17.4` 정량 미확인 — "ducking 지속"도 미측정). 지시대로 순수 발화 경로만 남기고 부작용 가능성을 제거한다. 유지한 것: `gSharedSynth` 상주, 메인 큐 dispatch, `ko-KR` 음성, 발화 전 `stopSpeakingAtBoundary:Immediate`.
산출물 증거(§5): `_OBJC_CLASS_$_AVAudioSession` undefined = **0**, 문자열 `setCategory:withOptions:error:`/`AVAudioSessionCategoryPlayback` = **0** → 바이너리에서 실제로 사라짐.

### 3-3) `src/Tweak.x` — `_handleCommand:reply:`의 nil 응답 삭제
Before:
```objc
            Class blockClass = NSClassFromString(@"NSBlock");
            if (reply && blockClass && [reply isKindOfClass:blockClass]) {
                void (^replyBlock)(id) = (void (^)(id))reply;
                @try { replyBlock(nil); } @catch (NSException *e) { NSLog(@"… reply(nil) raised: %@", e); }
            }
            return;
```
After:
```objc
            // -14: `replyBlock(nil)` 호출을 전면 제거한다. nil 응답으로 "처리 완료"로 알리면
            // Siri가 즉시 세션을 종료(화면 닫힘)한다는 것이 -13 기기 증상이다.
            // `-13`에서 확인한 사실: SiriPlus 바이너리에 `_handleCommand:` 셀렉터와
            // "Command of type" 로그 문자열이 실존(strings/nm 실측, `tweak/siriplus` 원본 deb).
            // 다만 SiriPlus가 reply 블록을 호출하지 않고 드롭하는지는 정적 검증 못 함 → HYPOTHESIS.
            return;   // %orig 미호출 + reply 미호출 = Apple 기본 화면/음성 응답 드롭
```
Rationale: nil Completion이 "응답 없음"이 아니라 "정상 종료 신호"로 해석됐을 가능성이 증상(B)과 부합한다. 이제Apple 명령은 `%orig` 없이, reply도 호출하지 않고 **완전 드롭**된다. 잔여 위험: Siri 상태기계에서 미해결 reply가 타임아웃/세션 유지 이상을 만들 수 있다(§6).
추가로 `NSClassFromString(@"NSBlock")` 가드와 `reply(nil) raised` 예외 로그가 함께 사라진다(문자열 카운트 0으로 확인, §5).

### 3-4) `src/Tweak.x` — 빌드 태그
`kSiriGeminiBuildTag`: `@"1.0.0-13"` → `@"1.0.0-14"`. 근거: Theos debug build number는 패키징마다 자동 증가하므로 수동 로그 문자열과 어긋나면 로그 판정이 오염된다(`-12`에서 실측된 불일치 교훈). 이번 빌드 산출물명 `…_1.0.0-14+debug…`와 **실제 일치** 확인됨(strings 카운트 `1.0.0-14`=2, §5).

---

## 4) 빌드 진단 및 경고 (Build Diagnostics & Warnings)

* Logos 전처리 사전 프로브: `logos_exit=0`, 생성 `.m` **707줄**, 에러 파일 비어있음.
* clang(`-fsyntax-only -fobjc-arc -target arm64-apple-ios15.0`, `-Wunused-function -Werror=unused-function`) 대상 `/tmp/pre14.m`: **무출력** = 오류·지정경고 없음 → 삭제 후 남은 미사용 심볼/함볼 없음.
* 패키지 빌드(`/tmp/sg_build14.log`): `grep -c error:` = **0**. 경고는 4줄로 전부 동일:
  ```text
  ld: warning: -multiply_defined is obsolete     (×4)
  ```
  영향도: Theos toolchain이 건네는 구식 `-multiply_defined` 옵션을 최신 ld가 무시한다는 통보. 심볼 해석/코드 생성과 무관, `-13`(경고 4)과 동일 → 조치 불요. 신규 경고 없음.
* 링크: `otool -L`에 AVFAudio·AVFoundation·AudioToolbox·CoreFoundation·Foundation·UIKit 정상 링크(슬라이스별 중복 제거 후 6종). `nm -u` undefined 총 **170**개(`-13`의 178 → 세션 API 제거로 감소).

---

## 5) 산출물 무결성 (Artifact Integrity)

* 파일: `build/com.csw.sirigemini_1.0.0-14+debug_iphoneos-arm64e.deb`, VM `~/build_sirigemini/packages/` 동일명.
* 크기 **52,308 bytes**(VM `wc -c` = 로컬 Length 일치). SHA256 **`8439cfdf624b371dad4bb7ca59f013a2320518c4c3f2bd910925929a223020f4`** (VM `shasum -a 256` == 로컬 `Get-FileHash`).
* `ar tv` 멤버 순서: `debian-binary`(4) → `control.tar.gz`(360) → `data.tar.lzma`(51,756). GNU-ar 요구 순서 충족.
* control tar 최상위 `./control`(278 bytes) 존재. data tar 항목 **14**, `.roothidepatch` **0개** → RootHide/Sileo 구조 정상(`-13`과 동일 패턴).
* **패키지에 동봉된 플리스트 실측**(data.tar에서 역추출 후 `plutil -p`) — 필터 축소 반영의 종단 증거:
  ```text
  Library/MobileSubstrate/DynamicLibraries/SiriGemini.plist
  { "Filter" => { "Bundles" => [ 0 => "com.apple.springboard" ] } }
  ```
* dylib 슬라이스: `lipo -info` → arm64 arm64e (universal Mach-O ×2).
* 심볼/문자열 검증(fat이라 슬라이스별 ×2 계상; 패턴은 파일로 올려 `grep -Fc`로 측정):
  ```text
  undef_total=170
  _OBJC_CLASS_$_AVSpeechSynthesizer   = 2      (발화 엔진 유지)
  _OBJC_CLASS_$_AVSpeechSynthesisVoice= 2      (ko-KR 음성 경로 유지)
  _MSHookMessageEx                    = 2      (substrate 훅 바인딩 유지)
  _AudioServicesPlaySystemSound       = 2      (햅틱 1519/1520 유지)
  CFUserNotificationDisplayAlert      = 0      (-10 핫픽스 상태 유지)
  _OBJC_CLASS_$_AVAudioSession        = 0      ★ 세션 조작 코드 제거됨
  strings: setCategory:withOptions:error:=0 · AVAudioSessionCategoryPlayback=0   ★
           voiceWithLanguage:=2 · stopSpeakingAtBoundary:=2 · speakUtterance:=2
           "Speaking utterance SUCCESS"=2 · "BLOCKED Apple Siri response command"=2
           _handleCommand:reply:=4 · _tellSpeechDelegateSpeechRecognized:=2 · _invokeRequestTimeoutForReason:=4
           "reply(nil) raised"=0                ★ nil 응답 경로 제거됨
           "1.0.0-14"=2                          (로그 태그가 산출물 번호와 일치)
  ```

---

## 6) 영향도 및 잠재 리스크 (Risks & Regression)

### 영향
1. **인젝션 범위 축소(4→1)**: assistantd·Siri bundle에 더 이상 코드가 로드되지 않으므로, 데몬에서의 Darwin notification 송수신과 다중 발화 선점 로직이 실행되지 않는다(`-8` 기능 사실상 비활성, 무해). 반면 **Siri 셀렉터가 SpringBoard 밖에 존재한다면** 훅 전체가 무력화되는 회귀가 발생한다 — 이것이 최대 리스크이며 아래 (a)로 즉시 판정 가능하다.
2. **오디오 세션 미변경**: SpringBoard 전역 라우팅을 더 이상 오염시키지 않는다(-13의 `Playback + DuckOthers` + deactivate 누락 부작용 제거). 반대 급부로 TTS 음성이 다른 오디오와 섞이거나, 녹음 중인 Siri 세션에서 출력이 안 나올 수 있다 → `-13` 무음 원인이 세션이었다면 이번에도 무음이 계속될 것이다(판정 지점 (b)).
3. **reply 미호출**: Apple 상태머신에 미완료 reply가 남는다. 화면이 유지되지 않거나, 반대 방향으로 세션이 오래 머물거나, 내부 타임아웃 로그가 늘 수 있다.

### 관측 포인트 (사용자 확인 항목)
| 관찰 | 판정 / 다음 행동 |
| :-- | :-- |
| (a) Siri 호출 시 진동(1519/1520)과 `[SiriGemini] Voice hook fired` 로그 유무 | 없으면 **필터 축소 실패**(훅 대상이 SpringBoard 밖) → `com.apple.SiriViewService`만 부분 복원해 재시험. 있으면 인젝션 범위 유지 가능 |
| (b) `[SiriGemini] Speaking utterance SUCCESS: '<문장>'` 로그는 있는데 소리가 없는지 | 세션 변경 없이도 무음이면 "세션이 원인" 가설 기각 → 출력 경로/SpringBoard 오디오 라우팅 또는 별도 데몬 발화 검토 |
| (c) 인식 후 창이 유지되는지(즉시 꺼짐 해소 여부) | 계속 꺼지면 `replyBlock(nil)`가 원인이 아니었다는 것 → `_invokeRequestTimeoutForReason:` 차단 또는 `%orig` 미호출의 다른 측면으로 가설 전환. 로그 `BLOCKED Apple Siri response command: <클래스명>`과 **차단된 클래스명 자체**를 반드시 확보(어느 셀렉터가 막았는지 아직 미분리) |
| (d) 시스템 체감 속도(스크롤·앱 전환), 음악 재생 중 볼륨 이상 여부 | 개선되면 인젝션 범위/세션 가설 지지. 악화·불변이면 원인 재조사(`logs/` 수집 필수) |
| (e) 크래시·리스프링 유무(Crab/log show) | 세션 조작 제거로 `-13` 대비 줄었는지 비교 |

### 되돌리기 지점(knob)
* 필터: `com.apple.SiriViewService`만 복원(springboard 단독 실패 시 첫 단계).
* 세션: `AVAudioSessionCategoryAmbient`(mixable, 녹음 방해 적음) + 즉시 deactivate 방식.
* reply: nil 대신 `%orig` 호출 후 출력만 차단하는 변형(화면 유지 실패 시).

### 남은 쟁점 (OPEN)
1. SiriPlus가 reply 블록을 드롭하는지 semantics — 정적 미검증(§1 claim 4). Ghidra/디스어셈블리 확인 전까지 HYPOTHESIS로만 사용한다.
2. Apple 기본 응답을 실제로 막는 셀렉터(`_invokeRequestTimeoutForReason:` vs `_handleCommand:reply:`) 분리 — `-14` 로그에서 클래스명 확보 시 확정.
3. 시스템 지연의 정량 지표(지연 ms, CPU) 미보유 — `logs/` 수집 후 비교 필요.
