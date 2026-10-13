#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
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
    if ([keywordVal isKindOfClass:[NSString class]] && [(NSString *)keywordVal length] > 0) {
        gKeyword = [keywordVal copy];
    } else {
        gKeyword = nil;
    }
}

static BOOL SiriGeminiShouldIntercept(NSString *recognizedText) {
    if (!gEnabled) return NO;
    if (gInGeminiCallback) return NO;  // Gemini 응답 재생성 루프 방지
    if (recognizedText.length == 0) return NO;
    if (gKeyword.length > 0) {
        // 키워드 접두사 매칭 (대소문자 무시). 예: "젬아 ..." / "Gemini ..."
        if ([recognizedText rangeOfString:gKeyword options:NSCaseInsensitiveSearch].location != 0) {
            return NO;
        }
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - gLastDispatchTime < kMinDispatchInterval) return NO;  // 스로틀
    return YES;
}

static NSString * SiriGeminiStripKeyword(NSString *text) {
    if (gKeyword.length > 0 && [text length] > [gKeyword length]) {
        NSString *prefix = [text substringToIndex:[gKeyword length]];
        if ([prefix caseInsensitiveCompare:gKeyword] == NSOrderedSame) {
            return [[text substringFromIndex:[gKeyword length]]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }
    return text;
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

%group SiriGeminiAFConnection

%hook AFConnection

// HYPOTHESIS: Siri 음성 인식 콜백. 실제 시그니처는 기기 class-dump/Frida로 확정 필요.
- (void)_tellSpeechDelegateSpeechRecognized:(id)recognition {
    NSString *recognizedText = nil;
    @try {
        // AFSpeechRecognition 결과 객체에서 텍스트 추출 시도 (best-effort, 다경로).
        if ([recognition isKindOfClass:[NSString class]]) {
            recognizedText = recognition;
        } else if ([recognition respondsToSelector:@selector(recognizedText)]) {
            recognizedText = ((id (*)(id, SEL))objc_msgSend)(recognition, @selector(recognizedText));
        } else if ([recognition respondsToSelector:@selector(bestText)]) {
            recognizedText = ((id (*)(id, SEL))objc_msgSend)(recognition, @selector(bestText));
        } else if ([recognition respondsToSelector:@selector(description)]) {
            recognizedText = [recognition description];
        }
    } @catch (NSException *e) {
        NSLog(@"[SiriGemini] text extract failed: %@", e);
    }

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
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        SiriGeminiSettingsChangedCallback,
                                        SiriGeminiChangedNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        SiriGeminiReloadSettings();

        // 조건부 %init: 클래스가 실제 존재할 때만 훅 활성화 (가설 무효화 시 자동 비활성).
        Class afConn = objc_getClass("AFConnection");
        if (afConn && [afConn instancesRespondToSelector:@selector(_tellSpeechDelegateSpeechRecognized:)]) {
            %init(SiriGeminiAFConnection);
            NSLog(@"[SiriGemini] AFConnection hook enabled");
        } else {
            NSLog(@"[SiriGemini] AFConnection hook SKIPPED (class/selector absent — hypothesis unconfirmed)");
        }

        Class utteranceView = objc_getClass("SAUIAssistantUtteranceView");
        if (utteranceView) {
            %init(SiriGeminiUtteranceView);
            NSLog(@"[SiriGemini] SAUIAssistantUtteranceView hook enabled");
        } else {
            NSLog(@"[SiriGemini] SAUIAssistantUtteranceView hook SKIPPED (class absent — hypothesis unconfirmed)");
        }
    }
}
