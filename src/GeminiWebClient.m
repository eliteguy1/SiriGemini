#import "GeminiWebClient.h"

NSString * const SiriGeminiPrefsPath = @"/var/mobile/Library/Preferences/com.csw.sirigemini.plist";
NSString * const SiriGeminiCookie1PSIDKey = @"__Secure-1PSID";
NSString * const SiriGeminiCookie1PSIDTSKey = @"__Secure-1PSIDTS";
NSString * const SiriGeminiCookieStringKey = @"cookieString";

// NOTE(HYPOTHESIS): Gemini Web의 실제 질의 RPC는 batchexecute 계열 POST이며
// 파라미터/응답 포맷은 런타임 캡처로 확정해야 한다. 아래 구현은 1단계 스켈레톤으로,
// 쿠키 주입 + 비동기 NSURLSession + 콜백 파이프라인까지만 제공한다.
// 응답 파싱 부분은 placeholder이며 2단계에서 교체 예정이다.
static NSString * const kGeminiBaseURLString = @"https://gemini.google.com";

@implementation GeminiWebClient

+ (instancetype)sharedClient {
    static GeminiWebClient *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (NSDictionary *)storedPrefs {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:SiriGeminiPrefsPath];
    if (!prefs) {
        // Rootless fallback (구형 경로). RootHide에서는 /var/mobile이 .jbroot로 매핑되므로
        // 보통 위 경로로 충분하나, 구 환경 호환용으로 유지.
        prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.csw.sirigemini.plist"];
    }
    return prefs ?: @{};
}

- (BOOL)hasLoginCookies {
    NSDictionary *prefs = [self storedPrefs];
    // 601078 완화: 전체 쿠키 문자열 또는 1PSID 중 하나라도 있으면 로그인으로 판정.
    NSString *cookieString = prefs[SiriGeminiCookieStringKey];
    NSString *psid = prefs[SiriGeminiCookie1PSIDKey];
    return (cookieString.length > 0 || psid.length > 0);
}

- (void)sendQuestion:(NSString *)question
         completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    if (question.length == 0) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [NSError errorWithDomain:@"SiriGemini"
                                                   code:-1
                                               userInfo:@{NSLocalizedDescriptionKey: @"empty question"}]);
            });
        }
        return;
    }

    NSDictionary *prefs = [self storedPrefs];
    // 601078: 전체 쿠키 문자열 우선 주입 (401/403 방지). 없으면 기존 2쿠키 방식으로 폴백.
    NSString *cookieHeader = prefs[SiriGeminiCookieStringKey];
    if (cookieHeader.length == 0) {
        NSString *psid = prefs[SiriGeminiCookie1PSIDKey];
        NSString *psidts = prefs[SiriGeminiCookie1PSIDTSKey];
        if (psid.length > 0 && psidts.length > 0) {
            cookieHeader = [NSString stringWithFormat:@"%@=%@; %@=%@;",
                            SiriGeminiCookie1PSIDKey, psid,
                            SiriGeminiCookie1PSIDTSKey, psidts];
        }
    }
    if (cookieHeader.length == 0) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [NSError errorWithDomain:@"SiriGemini"
                                                   code:-2
                                               userInfo:@{NSLocalizedDescriptionKey: @"Google login required (missing cookies)"}]);
            });
        }
        return;
    }

    // Cookie 헤더 주입. HttpOnly/Secure 쿠키도 헤더 방식으로는 전송 가능.

    NSURL *url = [NSURL URLWithString:kGeminiBaseURLString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:cookieHeader forHTTPHeaderField:@"Cookie"];
    [request setValue:@"application/x-www-form-urlencoded;charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"https://gemini.google.com" forHTTPHeaderField:@"Origin"];
    [request setValue:@"https://gemini.google.com/" forHTTPHeaderField:@"Referer"];
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15"
        forHTTPHeaderField:@"User-Agent"];

    // batchexecute RPC 바디는 2단계 런타임 캡처로 확정 예정. 여기서는 질의를 담은
    // 최소 placeholder 바디를 전송하고, 응답은 원문 그대로 상위 콜백에 전달한다.
    NSString *encodedQ = [question stringByAddingPercentEncodingWithAllowedCharacters:
                          [NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *body = [NSString stringWithFormat:@"q=%@", encodedQ ?: @""];
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData * _Nullable data,
                                                                NSURLResponse * _Nullable response,
                                                                NSError * _Nullable error) {
        NSString *answer = nil;
        NSError *outError = error;
        if (!outError) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            if (httpResp.statusCode < 200 || httpResp.statusCode >= 300) {
                outError = [NSError errorWithDomain:@"SiriGemini"
                                               code:httpResp.statusCode
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                      [NSString stringWithFormat:@"HTTP %ld", (long)httpResp.statusCode]}];
            } else if (data.length > 0) {
                // TODO(2단계): 실제 batchexecute 응답 파서로 교체.
                // 현재는 디버그용으로 응답 선두 2000자를 그대로 반환.
                NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (raw.length > 2000) raw = [raw substringToIndex:2000];
                answer = raw ?: @"(empty response)";
            }
        }
        if (completion) {
            NSString *finalAnswer = answer;
            NSError *finalError = outError;
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(finalAnswer, finalError);
            });
        }
    }];
    [task resume];
}

@end
