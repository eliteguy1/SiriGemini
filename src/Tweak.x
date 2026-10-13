#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "GeminiWebClient.h"

// ============================================================================
// SiriGemini 1단계 스켈레톤
//
// 컨셉: Siri 음성 인식 결과를 가로채 Gemini Web(쿠키 인증)으로 전달하고,
//       응답 텍스트를 Siri 발화/화면에 표시.
//
// --- Fact-Check Gate (검증 상태, AGENTS Sec.17) ---
// claim | type | verification source | status
//  AFConnection 클래스 존재                        | private class    | 미조회 | HYPOTHESIS
//  -_tellSpeechDelegateSpeechRecognized: 셀렉터/시그니처 | private selector | 미조회 | HYPOTHESIS
//  SAUIAssistantUtteranceView 클래스 존재          | private class    | 미조회 | HYPOTHESIS
// 따라서 아래 모든 훅은 %group + objc_getClass 존재 검사 + %init 조건부로만
// 활성화되며, 메서드 미존재 시 안전하게 비활성화된다. 무조건 %hook 하지 않음.
// ============================================================================

#define SiriGeminiPrefsAppID CFSTR("com.csw.sirigemini")
#define SiriGeminiChangedNotification CFSTR("com.csw.sirigemini.settingschanged")

static BOOL gEnabled = YES;
static NSString * __nullable gKeyword = nil;   // 비어 있으면 키워드 없이 전체 가로챔
static BOOL gInGeminiCallback = NO;            // 재진입 가드
static NSTimeInterval gLastDispatchTime = 0;   // 고빈도 호출 스로틀용
static const NSTimeInterval kMinDispatchInterval = 1.0;

// SiriPlus 역공학 기반 응답 차단(-11): 가로채기가 진행되는 동안 Apple이 SpringBoard로 보내는
// 출력 명령(SAUI 계열)과 요청 타임아웃을 막는다. 값 설정/해제 위치는 훅 본문 참조.
static BOOL gIsInterceptingSiri = NO;          // 현재 발화가 Gemini에 가로채진 상태
static NSString *gCapturedQuestion = nil;      // 키워드 제거 후 캡처된 질문(관측용)

// 필터 확장(-8)의 파생 위험: SpringBoard / SiriViewService / com.apple.siri / assistantd 에
// 동시에 인젝션되면 동일 발화가 프로세스별로 중복 dispatch 되어 답변이 여러 번 재생될 수 있다.
// Darwin 알림으로 "선점"을 브로드캐스트하고, 선점을 목격한 프로세스는 창 동안 인터셉트를 포기한다.
// (HYPOTHESIS: 크로스프로세스 동시 호출 빈도는 기기 로그로 확정 필요)
#define SiriGeminiClaimNotification CFSTR("com.csw.sirigemini.claimed")

static NSTimeInterval gLastPeerClaim = 0;      // 다른 프로세스(또는 자기 자신) 선점 시각
static const NSTimeInterval kPeerClaimWindow = 3.0;

static void SiriGeminiReloadSettings(void) {
    CFPreferencesAppSynchronize(SiriGeminiPrefsAppID);

    id enabledVal = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("enabled"), SiriGeminiPrefsAppID);
    if (enabledVal) {
        gEnabled = [enabledVal boolValue];
    } else {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:SiriGeminiPrefsPath];
        id v = prefs[@"enabled"];
        gEnabled = v ? [v boolValue] : YES;
    }

    id keywordVal = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("keyword"), SiriGeminiPrefsAppID);
    if (!keywordVal) {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:SiriGeminiPrefsPath];
        keywordVal = prefs[@"keyword"];
    }
    if ([keywordVal isKindOfClass:[NSString class]]) {
        NSString *kw = [(NSString *)keywordVal stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        gKeyword = (kw.length > 0) ? [kw copy] : nil;   // 앞뒤 공백 제거 후 로드
    } else {
        gKeyword = nil;
    }
}

// 발화 전처리: 앞뒤 공백/줄바꿈 제거 + 시리 호출어 접두사 제거.
// " 젬아", "시리야 젬아", "Hey Siri 젬아" 등을 동일한 형태로 만든다.
static NSString *SiriGeminiCleanText(NSString *raw) {
    if (!raw) return @"";
    NSString *cleaned = [raw stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *prefixes = @[@"시리야", @"시리", @"hey siri", @"siri야", @"siri"];
    for (NSString *p in prefixes) {
        if ([cleaned.lowercaseString hasPrefix:p.lowercaseString]) {
            cleaned = [cleaned substringFromIndex:p.length];
            cleaned = [cleaned stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }
    return cleaned;
}

// 키워드 매칭 ( 전면 유연화 ): 비어 있으면 전체 가로챔.
// 위치(location==0) 조건 없음 — anywhere contains, 대소문자/호출어 접두사 무시.
static BOOL SiriGeminiShouldIntercept(NSString *recognizedText) {
    if (!gEnabled) return NO;
    if (gInGeminiCallback) return NO;  // Gemini 응답 재생성 루프 방지
    if (recognizedText.length == 0) return NO;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

    // 다른 프로세스(또는 직전 자기 선점)가 최근 이 발화를 처리했으면 포기.
    if (now - gLastPeerClaim < kPeerClaimWindow) {
        NSLog(@"[SiriGemini] skip: utterance claimed %.1fs ago", now - gLastPeerClaim);
        return NO;
    }

    NSString *cleaned = SiriGeminiCleanText(recognizedText);
    if (gKeyword.length == 0) return YES;   // 키워드 미설정 → 전체 가로챔

    NSString *kw = [gKeyword stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([cleaned.lowercaseString containsString:kw.lowercaseString] ||
        [recognizedText.lowercaseString containsString:kw.lowercaseString]) {
        // 파생 가드 (기존 스로틀 보존): 동일 발화 중복 dispatch 및 고빈도 호출 방지.
        if (now - gLastDispatchTime < kMinDispatchInterval) return NO;
        return YES;
    }

    return NO;
}

static NSString * SiriGeminiStripKeyword(NSString *text) {
    NSString *cleaned = SiriGeminiCleanText(text);
    if (gKeyword.length > 0) {
        NSString *kw = [gKeyword stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSRange r = [cleaned rangeOfString:kw options:NSCaseInsensitiveSearch];
        if (r.location != NSNotFound) {
            cleaned = [cleaned stringByReplacingCharactersInRange:r withString:@""];
            cleaned = [cleaned stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }
    return cleaned.length > 0 ? cleaned : SiriGeminiCleanText(text);
}

// Siri 발화 출력 (best-effort).
// HYPOTHESIS: SAUIAssistantUtteranceView의 실제 텍스트 설정 경로는 미확인.
// 우선 AVSpeechSynthesizer 음성 출력 + NotificationCenter 브로드캐스트로
// 화면 갱신 훅(SAUIAssistantUtteranceView)이 수신할 수 있게 한다.
static void SiriGeminiSpeak(NSString *text) {
    if (text.length == 0) return;
    @try {
        Class ttsClass = objc_getClass("AVSpeechSynthesizer");
        if (ttsClass) {
            AVSpeechSynthesizer *synth = [[ttsClass alloc] init];
            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate;
            [synth speakUtterance:utterance];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SiriGeminiAnswerNotification"
                                                            object:text];
    } @catch (NSException *e) {
        NSLog(@"[SiriGemini] Speak failed: %@", e);
    }
}

// ============================================================================
// 로드 상태 보고 (-10 핫픽스): 차단형 UI 제거.
// CFUserNotificationDisplayAlert는 사용자에게 표시될 때까지 호출 스레드를 막는 API다.
// %ctor(SpringBoard 부팅 중, 메인 스레드)에서 호출하면 워치독이 프로세스를 잡아
// 무한 리스프링을 일으키므로(-9 기기 증언) 팝업 경로를 완전히 삭제하고 로그만 남긴다.
// kSiriGeminiBuildTag는 수동 문자열이므로 자동 증가하는 Theos build number와 맞도록 갱신해야 한다.
static NSString * const kSiriGeminiBuildTag = @"1.0.0-12";

static void SiriGeminiReportLoad(void) {
    NSString *procName = [NSProcessInfo processInfo].processName;
    Class afClass = objc_getClass("AFConnection");
    NSLog(@"[SiriGemini] v%@ ctor loaded in process: %@ (AFConnection: %d)",
          kSiriGeminiBuildTag, procName, afClass ? 1 : 0);
}

static void SiriGeminiPostClaim(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         SiriGeminiClaimNotification,
                                         NULL,
                                         NULL,
                                         true);
}

// 이 발화를 현재 프로세스가 처리했음을 기록하고 다른 프로세스에 브로드캐스트한다.
static void SiriGeminiClaimThisUtterance(void) {
    gLastDispatchTime = [[NSDate date] timeIntervalSince1970];
    gLastPeerClaim = gLastDispatchTime;
    SiriGeminiPostClaim();
}

static void SiriGeminiClaimObserverCallback(CFNotificationCenterRef center,
                                            void *observer,
                                            CFStringRef name,
                                            const void *object,
                                            CFDictionaryRef userInfo) {
    gLastPeerClaim = [[NSDate date] timeIntervalSince1970];
    NSLog(@"[SiriGemini] utterance claimed by another process -> skipping this window");
}

// Forward declarations — 실제 private 헤더가 없으므로 respondsToSelector로 검증.
// 시그니처는 HYPOTHESIS이며, %orig 호출 시 원래 인자 타입을 그대로 전달한다.
@interface AFConnection : NSObject
- (void)_tellSpeechDelegateSpeechRecognized:(id)recognition;  // HYPOTHESIS
@end

@interface SAUIAssistantUtteranceView : UIView  // HYPOTHESIS
@end

// SASSpeechRecognized 파서 ( 전면 강화 ).
// 기존 구현은 KVC 경로 실패 시 조용히 nil을 반환했고, 그 결과 훅의
// `if (recognizedText && SiriGeminiShouldIntercept(...))` 가 false가 되어 %orig(기본 Siri)가 실행됐다.
// 이제 복원 경로를 다중으로 탐색하고, 최후에 description 기반 정규식/단어 폴백까지 사용하며,
// 그래도 실패하면 클래스명을 기록해 훅이 음성 진단을 내고 %orig를 차단할 수 있게 한다.
// (경로·셀렉터 이름은 여전히 EXTERNALLY-SOURCED HYPOTHESIS이며, 기기 로그로 확정 예정.)

static NSString *gLastExtractFailClass = nil;   // 복원 실패가 확정된 객체의 클래스명(진단용)

static id SiriGeminiRawValue(id obj, NSString *key) {
    if (!obj || key.length == 0) return nil;
    SEL sel = sel_registerName([key UTF8String]);
    if (![obj respondsToSelector:sel]) return nil;
    @try {
        return [obj valueForKey:key];
    } @catch (NSException *e) {
        return nil;
    }
}

static NSString *SiriGeminiStringValue(id obj, NSString *key) {
    id value = SiriGeminiRawValue(obj, key);
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    return nil;
}

static NSString *SiriGeminiLongest(NSArray<NSString *> *items) {
    NSString *best = nil;
    for (NSString *s in items) {
        if (![s isKindOfClass:[NSString class]] || s.length == 0) continue;
        if (!best || s.length > best.length) best = s;
    }
    return best;
}

static void SiriGeminiAppendPiece(NSMutableString *dst, NSString *piece) {
    if (![piece isKindOfClass:[NSString class]] || piece.length == 0) return;
    if (dst.length > 0) [dst appendString:@" "];
    [dst appendString:piece];
}

// phrases[] → tokens[].text, 실패 시 phrase.text. 공백으로 이어 붙인다.
static NSString *SiriGeminiPhrasesText(id phrasesObj) {
    if (![phrasesObj isKindOfClass:[NSArray class]]) return nil;

    NSMutableString *full = [NSMutableString string];
    for (id phrase in (NSArray *)phrasesObj) {
        NSArray *tokens = nil;
        id tval = SiriGeminiRawValue(phrase, @"tokens");
        if ([tval isKindOfClass:[NSArray class]]) tokens = (NSArray *)tval;

        BOOL appendedToken = NO;
        for (id token in tokens) {
            NSString *tokenText = SiriGeminiStringValue(token, @"text");
            if (tokenText.length > 0) {
                SiriGeminiAppendPiece(full, tokenText);
                appendedToken = YES;
            }
        }
        if (!appendedToken) {
            SiriGeminiAppendPiece(full, SiriGeminiStringValue(phrase, @"text"));
        }
    }

    if (full.length == 0) return nil;
    return [full stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL SiriGeminiIsSpeechLikeObject(id obj) {
    if (!obj) return NO;
    NSString *cn = NSStringFromClass([obj class]);
    if (cn.length == 0) return NO;
    NSArray<NSString *> *needles = @[@"Speech", @"Recogni", @"Transcription", @"Utterance"];
    for (NSString *needle in needles) {
        if ([cn rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

// 최후의 폴백 1: description 문자열에서 text=/phrase=/token= 값 추출 후 공백 결합.
static NSString *SiriGeminiDescriptionRegexFallback(id obj) {
    NSString *desc = [obj description];
    if (desc.length == 0) return nil;

    NSArray<NSString *> *patterns = @[
        @"text\\s*=\\s*\"([^\"]+)\"",
        @"phrase\\s*=\\s*\"([^\"]+)\"",
        @"token\\s*=\\s*\"([^\"]+)\""
    ];

    NSMutableString *joined = [NSMutableString string];
    for (NSString *pattern in patterns) {
        NSRegularExpression *re = nil;
        @try {
            re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        } @catch (NSException *e) {
            re = nil;
        }
        if (!re) continue;

        [re enumerateMatchesInString:desc options:0 range:NSMakeRange(0, desc.length)
                          usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
            NSString *s = [desc substringWithRange:[m rangeAtIndex:1]];
            SiriGeminiAppendPiece(joined, s);
        }];
    }

    if (joined.length == 0) return nil;
    return [joined stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// 최후의 폴백 2: description에서 사람이 읽을 만한 단어(한글/라틴 2자 이상)만 추려 결합.
static NSString *SiriGeminiWordsFromDescription(id obj) {
    NSString *desc = [obj description];
    if (desc.length == 0) return nil;

    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"[가-힣A-Za-z]{2,}"
                                                                       options:0 error:nil];
    if (!re) return nil;

    NSMutableString *joined = [NSMutableString string];
    [re enumerateMatchesInString:desc options:0 range:NSMakeRange(0, desc.length)
                      usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        NSString *s = [desc substringWithRange:m.range];
        SiriGeminiAppendPiece(joined, s);
    }];

    if (joined.length == 0) return nil;
    return [joined stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *SiriGeminiExtractRecognizedText(id speechRecognized) {
    gLastExtractFailClass = nil;
    if (!speechRecognized) return nil;
    if ([speechRecognized isKindOfClass:[NSString class]]) return (NSString *)speechRecognized;

    // 1) recognition.phrases / phrases 경로.
    @try {
        id phrasesObj = nil;
        SEL recSel = sel_registerName("recognition");
        if ([speechRecognized respondsToSelector:recSel]) {
            id recognition = [speechRecognized valueForKey:@"recognition"];
            if (recognition) {
                SEL phSel = sel_registerName("phrases");
                if ([recognition respondsToSelector:phSel]) phrasesObj = [recognition valueForKey:@"phrases"];
            }
        } else {
            SEL phSel = sel_registerName("phrases");
            if ([speechRecognized respondsToSelector:phSel]) phrasesObj = [speechRecognized valueForKey:@"phrases"];
        }

        NSString *fromPhrases = SiriGeminiPhrasesText(phrasesObj);
        if (fromPhrases.length > 0) {
            NSLog(@"[SiriGemini] text via phrases path (len=%lu)", (unsigned long)fromPhrases.length);
            return fromPhrases;
        }
    } @catch (NSException *e) {
        NSLog(@"[SiriGemini] phrases path failed: %@", e);
    }

    // 2) 직접 텍스트 셀렉터/KVC 키 다중 탐색 → 가장 긴 문자열 채택.
    NSArray<NSString *> *keys = @[@"text", @"transcription", @"bestTranscription", @"bestText", @"recognizedText"];
    NSMutableArray<NSString *> *direct = [NSMutableArray array];
    for (NSString *key in keys) {
        NSString *v = SiriGeminiStringValue(speechRecognized, key);
        if (v.length > 0) [direct addObject:v];
    }
    NSString *bestDirect = SiriGeminiLongest(direct);
    if (bestDirect.length > 0) {
        NSLog(@"[SiriGemini] text via direct selector (len=%lu)", (unsigned long)bestDirect.length);
        return bestDirect;
    }

    // 3) description 정규식 폴백.
    NSString *fromRegex = SiriGeminiDescriptionRegexFallback(speechRecognized);
    if (fromRegex.length > 0) {
        NSLog(@"[SiriGemini] text via description regex fallback (len=%lu)", (unsigned long)fromRegex.length);
        return fromRegex;
    }

    // 4) description 단어 추출 폴백.
    NSString *fromWords = SiriGeminiWordsFromDescription(speechRecognized);
    if (fromWords.length > 0) {
        NSLog(@"[SiriGemini] text via description word fallback (len=%lu)", (unsigned long)fromWords.length);
        return fromWords;
    }

    // 실패 확정: 진단 정보를 남긴다(훅이 음성 피드백 후 %orig를 차단하도록 사용).
    gLastExtractFailClass = NSStringFromClass([speechRecognized class]);
    NSLog(@"[SiriGemini] ALL text extraction paths failed, class: %@", gLastExtractFailClass);
    return nil;
}

// 복원 실패 진단을 음성으로 내고 기본 Siri(%orig)로 빠져나가지 않게 한다.
static BOOL SiriGeminiHandleExtractionFailure(id recognitionObject) {
    if (gLastExtractFailClass.length == 0) return NO;          // 실패 확정 아님(예: nil 입력)
    if (!SiriGeminiIsSpeechLikeObject(recognitionObject)) return NO;
    if (gKeyword.length > 0) return NO;   // 키워드 설정 상태에서는 무관 발화를 가로채지 않는다
    if (!gEnabled || gInGeminiCallback) return NO;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - gLastDispatchTime < kMinDispatchInterval || now - gLastPeerClaim < kPeerClaimWindow) {
        NSLog(@"[SiriGemini] extraction-failure diagnostics throttled (peer or local)");
        return YES;   // %orig는 차단하되 음성 중복은 방지
    }
    gLastDispatchTime = now;
    SiriGeminiPostClaim();   // 진단음을 냈다는 것도 다른 프로세스에 알린다(중복 음성 방지)

    NSString *msg = [NSString stringWithFormat:@"음성이 인식되었으나 텍스트 복원에 실패했습니다: %@",
                     gLastExtractFailClass];
    NSLog(@"[SiriGemini] extraction failure diagnostics: %@", msg);
    SiriGeminiSpeak(msg);
    return YES;   // %orig 차단 → 기본 시리가 대답하지 못하게 하고 진단음 유지
}

// 표준 Logos 직접 후킹(-9): %group + 조건부 %init 대신 최상위 %hook를 사용한다.
// 주의: logos가 생성하는 바인딩 코드에는 클래스 nil 가드가 없으므로(본 세션 생성 코드 확인),
// %init(_ungrouped) 호출은 AFConnection이 로드된 뒤에 수행해야 한다(%ctor + 지연 재시도).

%hook AFConnection

// HYPOTHESIS: Siri 음성 인식 콜백. 실제 시그니처는 기기 class-dump/Frida로 확정 필요.
- (void)_tellSpeechDelegateSpeechRecognized:(id)recognition {
    NSLog(@"[SiriGemini] HOOK FIRED in process %@!", [NSProcessInfo processInfo].processName);
    AudioServicesPlaySystemSound(1519);   // 인식 반응을 손으로 즉시 체감(지시 C)
    NSLog(@"[SiriGemini] Raw speech object: %@", [recognition class]);
    NSString *recognizedText = SiriGeminiExtractRecognizedText(recognition);
    NSLog(@"[SiriGemini] Extracted text: '%@' (enabled: %d, keyword: '%@')",
          recognizedText, gEnabled, gKeyword);

    if (recognizedText && SiriGeminiShouldIntercept(recognizedText)) {
        SiriGeminiClaimThisUtterance();
        gIsInterceptingSiri = YES;
        gCapturedQuestion = [SiriGeminiStripKeyword(recognizedText) copy];
        NSLog(@"[SiriGemini] INTERCEPT ACTIVE: '%@'", gCapturedQuestion);
        AudioServicesPlaySystemSound(1520);   // 텍스트 추출 성공 2차 햅틱(지시 B)
        gInGeminiCallback = YES;
        [[GeminiWebClient sharedClient] sendQuestion:gCapturedQuestion
                                          completion:^(NSString * _Nullable answer, NSError * _Nullable error) {
            gInGeminiCallback = NO;
            if (answer.length > 0) {
                NSLog(@"[SiriGemini] Gemini Answer: %@", answer);
                SiriGeminiSpeak(answer);
            } else {
                NSString *errText = [NSString stringWithFormat:@"제미나이 연결 오류: %@",
                                     error.localizedDescription ?: @"응답 없음"];
                NSLog(@"[SiriGemini] error speech: %@ (raw error: %@)", errText, error);
                SiriGeminiSpeak(errText);
            }
            // 발화 시작 후 잠시 동안 Apple의 기본 응답 명령 차단을 유지하고 창을 닫는다.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                gIsInterceptingSiri = NO;
                NSLog(@"[SiriGemini] interception window closed");
            });
        }];
        return;  // %orig 생략 = 기존 음성 처리 가로챔
    }

    // 텍스트 복원이 모든 경로를 통해 실패한 경우: 진단음을 내고 기본 Siri로 넘기지 않는다.
    if (SiriGeminiHandleExtractionFailure(recognition)) {
        return;
    }

    // 최근(창 내) 다른 프로세스/자기 선점이 있으면 기본 Siri도 억제한다.
    // (키워드 미설정 = 전체 가로챔 모드에서만 적용. 다중 인젝션 환경의 중복 답변 방지 의도.)
    if (gKeyword.length == 0 && gLastPeerClaim > 0) {
        NSTimeInterval since = [[NSDate date] timeIntervalSince1970] - gLastPeerClaim;
        if (since < kPeerClaimWindow) {
            NSLog(@"[SiriGemini] suppress orig: utterance handled %.1fs ago", since);
            return;
        }
    }

    %orig;
}

%end  // AFConnection

// ============================================================================
// -11: SiriPlus 역공학 기반 "Apple 기본 응답" 차단 훅 2종.
// 셀렉터(`_invokeRequestTimeoutForReason:`, `_handleCommand:reply:`)는 외부 역공학 출처로,
// 이 프로젝트에서 class-dump/Frida 확인을 못 했으므로 HYPOTHESIS다. 따라서 각각을 별도 %group으로
// 나눠 `instancesRespondToSelector:` 검사 통과 시에만 바인딩한다: 미구현 셀렉터를 바인딩하면
// substrate가 orig=NULL로 메서드를 추가하고, 훅 본문의 `%orig`가 NULL 점프가 되어 SpringBoard를
// 잡는 경로가 생긴다(-9 무한 리스프링 교훈 → 검증 없는 바인딩 금지).
// ============================================================================

%group SiriGeminiAFTimeoutBlock

%hook AFConnection

- (void)_invokeRequestTimeoutForReason:(id)reason {
    if (gIsInterceptingSiri) {
        NSLog(@"[SiriGemini] request timeout blocked during Gemini generation (reason: %@)", reason);
        return;   // 제미나이가 답변할 때까지 Siri의 타임아웃 종료 차단
    }
    %orig;
}

%end  // AFConnection

%end  // group SiriGeminiAFTimeoutBlock

%group SiriGeminiAFCommandBlock

%hook AFConnection

- (void)_handleCommand:(id)command reply:(id)reply {
    if (gIsInterceptingSiri && command) {
        NSString *cmdClass = NSStringFromClass([command class]);
        NSLog(@"[SiriGemini] intercepted command: %@", cmdClass);
        BOOL appleResponse = [cmdClass containsString:@"SAUI"];
        if (!appleResponse) appleResponse = [cmdClass containsString:@"AddViews"];
        if (!appleResponse) appleResponse = [cmdClass containsString:@"AssistantUtterance"];

        if (appleResponse) {
            NSLog(@"[SiriGemini] BLOCKED Apple Siri response command: %@", cmdClass);
            // reply가 실제 블록일 때만 조용한 응답으로 처리한다(4번째 인자 타입은 HYPOTHESIS).
            Class blockClass = NSClassFromString(@"NSBlock");
            if (reply && blockClass && [reply isKindOfClass:blockClass]) {
                void (^replyBlock)(id) = (void (^)(id))reply;
                @try {
                    replyBlock(nil);
                } @catch (NSException *e) {
                    NSLog(@"[SiriGemini] reply(nil) raised: %@", e);
                }
            }
            return;   // %orig 미호출 = Apple의 기본 화면/음성 응답 차단
        }
    }
    %orig;
}

%end  // AFConnection

%end  // group SiriGeminiAFCommandBlock

%group SiriGeminiUtteranceView

%hook SAUIAssistantUtteranceView

// HYPOTHESIS: Gemini 응답을 Siri 화면에 표시하기 위한 훅 위치.
// 1단계에서는 관측용 로깅 + 노티 수신 시 텍스트 반영 시도만 수행한다.
- (void)didMoveToWindow {
    %orig;
    @try {
        id observer = [[NSNotificationCenter defaultCenter]
            addObserverForName:@"SiriGeminiAnswerNotification"
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            NSString *text = (NSString *)note.object;
            if (![text isKindOfClass:[NSString class]] || text.length == 0) return;
            // best-effort: setText:/setDetailText: 응답 시에만 반영
            if ([self respondsToSelector:@selector(setText:)]) {
                ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(setText:), text);
            } else if ([self respondsToSelector:@selector(setDetailText:)]) {
                ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(setDetailText:), text);
            } else {
                NSLog(@"[SiriGemini] utterance view has no known text setter (hypothesis unconfirmed)");
            }
        }];
        (void)observer;  // 1단계: 해제 관리 미구현 (2단계에서 약참조/해제 처리)
        NSLog(@"[SiriGemini] SAUIAssistantUtteranceView observed (hypothesis hook active)");
    } @catch (NSException *e) {
        NSLog(@"[SiriGemini] utterance hook failed: %@", e);
    }
}

%end  // SAUIAssistantUtteranceView

%end  // group SiriGeminiUtteranceView

static void SiriGeminiSettingsChangedCallback(CFNotificationCenterRef center,
                                              void *observer,
                                              CFStringRef name,
                                              const void *object,
                                              CFDictionaryRef userInfo) {
    SiriGeminiReloadSettings();
}

// ============================================================================
// -9: 표준 직접 훅(-ungrouped)의 바인딩 설치 제어.
// logos가 생성한 AFConnection 바인딩 코드에는 클래스 nil 가드가 없으므로(생성 코드 관찰),
// %init(_ungrouped)는 클래스가 로드된 뒤에만 호출한다. 프레임워크 지연 로드를 대비해
// 앱 런칭 완료 시점에도 재시도한다(지시 3).
static BOOL gAFHookInstalled = NO;
static BOOL gTimeoutHookInstalled = NO;
static BOOL gCommandHookInstalled = NO;

static void SiriGeminiInstallAFHook(void) {
    if (gAFHookInstalled) return;

    Class afConn = objc_getClass("AFConnection");
    if (!afConn) {
        // 아직 로드 전이므로 private 프레임워크를 강제로 로드해본 뒤 다시 확인한다.
        dlopen("/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices", RTLD_NOW);
        afConn = objc_getClass("AFConnection");
    }

    if (!afConn) {
        NSLog(@"[SiriGemini] AFConnection not loaded yet -> hook binding deferred");
        return;
    }

    %init(_ungrouped);
    gAFHookInstalled = YES;
    NSLog(@"[SiriGemini] AFConnection hook INSTALLED (direct logos hook, ungrouped)");

    // -11 응답 차단 훅: 셀렉터가 실제로 구현돼 있을 때만 바인딩한다(미구현 시 %orig=NULL 위험).
    BOOL hasTimeout = [afConn instancesRespondToSelector:@selector(_invokeRequestTimeoutForReason:)];
    BOOL hasCommand = [afConn instancesRespondToSelector:@selector(_handleCommand:reply:)];

    if (hasTimeout && !gTimeoutHookInstalled) {
        %init(SiriGeminiAFTimeoutBlock);
        gTimeoutHookInstalled = YES;
    }
    if (hasCommand && !gCommandHookInstalled) {
        %init(SiriGeminiAFCommandBlock);
        gCommandHookInstalled = YES;
    }

    NSLog(@"[SiriGemini] response hook guard: _invokeRequestTimeoutForReason:%d _handleCommand:reply:%d -> installed timeout=%d command=%d",
          hasTimeout ? 1 : 0, hasCommand ? 1 : 0, gTimeoutHookInstalled ? 1 : 0, gCommandHookInstalled ? 1 : 0);
}

%ctor {
    @autoreleasepool {
        // AFConnection/SASSpeechRecognized 클래스가 %ctor 시점에 로드되도록
        // private 프레임워크 사전 로드 (링크는 하지 않음 — SDK에 .tbd 없음).
        dlopen("/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices", RTLD_NOW);
        dlopen("/System/Library/PrivateFrameworks/SAObjects.framework/SAObjects", RTLD_NOW);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        SiriGeminiSettingsChangedCallback,
                                        SiriGeminiChangedNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        // 크로스프로세스 선점(중복 답변 방지) 알림 수신.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        SiriGeminiClaimObserverCallback,
                                        SiriGeminiClaimNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        SiriGeminiReloadSettings();

        // 직접 훅 바인딩 시도(차단 없음) 후 결과를 로그로만 보고한다(-10 핫픽스: 팝업 제거).
        SiriGeminiInstallAFHook();
        SiriGeminiReportLoad();

        Class uttClass = objc_getClass("SAUIAssistantUtteranceView");
        if (uttClass) {
            %init(SiriGeminiUtteranceView);
            NSLog(@"[SiriGemini] SAUIAssistantUtteranceView hook INITIALIZED");
        } else {
            NSLog(@"[SiriGemini] SAUIAssistantUtteranceView class NOT FOUND");
        }

        // 지시 3: 프레임워크가 늦게 로드되는 환경을 대비한 2차 바인딩 안전장치.
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            SiriGeminiReloadSettings();
            SiriGeminiInstallAFHook();
            NSLog(@"[SiriGemini] didFinishLaunching: settings reloaded, AF hook installed=%d", gAFHookInstalled ? 1 : 0);
        }];
    }
}
