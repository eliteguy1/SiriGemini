#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
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

    NSString *cleaned = SiriGeminiCleanText(recognizedText);
    if (gKeyword.length == 0) return YES;   // 키워드 미설정 → 전체 가로챔

    NSString *kw = [gKeyword stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([cleaned.lowercaseString containsString:kw.lowercaseString] ||
        [recognizedText.lowercaseString containsString:kw.lowercaseString]) {
        // 파생 가드 (기존 스로틀 보존): 동일 발화 중복 dispatch 및 고빈도 호출 방지.
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
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

// Forward declarations — 실제 private 헤더가 없으므로 respondsToSelector로 검증.
// 시그니처는 HYPOTHESIS이며, %orig 호출 시 원래 인자 타입을 그대로 전달한다.
@interface AFConnection : NSObject
- (void)_tellSpeechDelegateSpeechRecognized:(id)recognition;  // HYPOTHESIS
@end

@interface SAUIAssistantUtteranceView : UIView  // HYPOTHESIS
@end

// SASSpeechRecognized 파서.
// 경로: speechRecognized.recognition → .phrases[] → .tokens[] → .text 결합.
// 근거: SiriPlus.dylib 역공학 분석(오케스트레이터 제공) — 기기 실측 검증은 아직 없음
// (EXTERNALLY-SOURCED HYPOTHESIS). KVC 미준수 키 접근 시 예외 → @catch 후 nil.
static NSString *SiriGeminiExtractRecognizedText(id speechRecognized) {
    if (!speechRecognized) return nil;
    if ([speechRecognized isKindOfClass:[NSString class]]) return speechRecognized;

    @try {
        id recognition = nil;
        if ([speechRecognized respondsToSelector:@selector(recognition)]) {
            recognition = [speechRecognized valueForKey:@"recognition"];
        } else {
            recognition = speechRecognized;
        }

        NSArray *phrases = nil;
        if ([recognition respondsToSelector:@selector(phrases)]) {
            phrases = [recognition valueForKey:@"phrases"];
        }

        if (phrases && [phrases isKindOfClass:[NSArray class]]) {
            NSMutableString *fullText = [NSMutableString string];
            for (id phrase in phrases) {
                NSArray *tokens = nil;
                if ([phrase respondsToSelector:@selector(tokens)]) {
                    tokens = [phrase valueForKey:@"tokens"];
                }
                if (tokens && [tokens isKindOfClass:[NSArray class]]) {
                    for (id token in tokens) {
                        NSString *tokenText = nil;
                        if ([token respondsToSelector:@selector(text)]) {
                            tokenText = [token valueForKey:@"text"];
                        }
                        if (tokenText.length > 0) {
                            if (fullText.length > 0) [fullText appendString:@" "];
                            [fullText appendString:tokenText];
                        }
                    }
                }
            }
            if (fullText.length > 0) {
                return [fullText stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[SiriGemini] SASSpeechRecognized parse failed: %@", e);
    }
    // 진단용: 파싱 실패 시 클래스명 기록 (다음 반복의 단서).
    NSLog(@"[SiriGemini] unparsed recognition class: %@",
          NSStringFromClass([speechRecognized class]));
    return nil;
}

%group SiriGeminiAFConnection

%hook AFConnection

// HYPOTHESIS: Siri 음성 인식 콜백. 실제 시그니처는 기기 class-dump/Frida로 확정 필요.
- (void)_tellSpeechDelegateSpeechRecognized:(id)recognition {
    NSLog(@"[SiriGemini] Raw speech object: %@", [recognition class]);
    NSString *recognizedText = SiriGeminiExtractRecognizedText(recognition);
    NSLog(@"[SiriGemini] Extracted text: '%@' (enabled: %d, keyword: '%@')",
          recognizedText, gEnabled, gKeyword);

    if (recognizedText && SiriGeminiShouldIntercept(recognizedText)) {
        gLastDispatchTime = [[NSDate date] timeIntervalSince1970];
        NSString *question = SiriGeminiStripKeyword(recognizedText);
        NSLog(@"[SiriGemini] intercept: %@", question);
        gInGeminiCallback = YES;
        [[GeminiWebClient sharedClient] sendQuestion:question
                                          completion:^(NSString * _Nullable answer, NSError * _Nullable error) {
            gInGeminiCallback = NO;
            if (answer.length > 0) {
                NSLog(@"[SiriGemini] answer (%lu chars)", (unsigned long)[answer length]);
                SiriGeminiSpeak(answer);
            } else {
                NSLog(@"[SiriGemini] error: %@", error);
            }
            // NOTE: 가로챈 경우 %orig를 호출하지 않아 기존 Siri 파이프라인을 중단한다.
            // (키워드 매칭 시에만 해당. 폴백이 필요하면 2단계에서 %orig 호출 정책 확정.)
        }];
        return;  // %orig 생략 = 기존 음성 처리 가로챔
    }

    %orig;
}

%end  // AFConnection

%end  // group SiriGeminiAFConnection

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
        SiriGeminiReloadSettings();

        // AFConnection 클래스가 존재하면 무조건 훅 활성화.
        // (이전 구현의 instancesRespondToSelector: 검사는 비공개 셀렉터/동적 로딩 환경에서
        //  NO를 반환해 %init 자체가 건너뛰어져 훅이 통째로 꺼지는 원인이 되었다.)
        Class afConn = objc_getClass("AFConnection");
        if (afConn) {
            %init(SiriGeminiAFConnection);
            NSLog(@"[SiriGemini] AFConnection hook FORCE-INITIALIZED");
        } else {
            NSLog(@"[SiriGemini] AFConnection class NOT FOUND");
        }

        Class uttClass = objc_getClass("SAUIAssistantUtteranceView");
        if (uttClass) {
            %init(SiriGeminiUtteranceView);
            NSLog(@"[SiriGemini] SAUIAssistantUtteranceView hook INITIALIZED");
        } else {
            NSLog(@"[SiriGemini] SAUIAssistantUtteranceView class NOT FOUND");
        }
    }
}
