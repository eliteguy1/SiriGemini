#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Preferences plist에 저장되는 Google 로그인 쿠키 키.
extern NSString * const SiriGeminiPrefsPath;
extern NSString * const SiriGeminiCookie1PSIDKey;    // __Secure-1PSID   (UNVERIFIED recall — 런타임 검증 필요)
extern NSString * const SiriGeminiCookie1PSIDTSKey;  // __Secure-1PSIDTS (UNVERIFIED recall — 런타임 검증 필요)

@interface GeminiWebClient : NSObject

+ (instancetype)sharedClient;

/// 저장된 쿠키로 Gemini Web에 질문을 전송.
/// @param question Siri 인식 텍스트
/// @param completion 응답 텍스트(또는 nil) + 에러. 메인 큐에서 호출됨.
- (void)sendQuestion:(NSString *)question
         completion:(void (^)(NSString * _Nullable answer, NSError * _Nullable error))completion;

/// 로그인 쿠키 존재 여부 (버튼 상태 표시용).
- (BOOL)hasLoginCookies;

@end

NS_ASSUME_NONNULL_END
