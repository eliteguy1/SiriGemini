#import "GeminiWebClient.h"
#import <objc/runtime.h>
#import <stdlib.h>

NSString * const SiriGeminiPrefsPath = @"/var/mobile/Library/Preferences/com.csw.sirigemini.plist";
NSString * const SiriGeminiCookie1PSIDKey = @"__Secure-1PSID";
NSString * const SiriGeminiCookie1PSIDTSKey = @"__Secure-1PSIDTS";
NSString * const SiriGeminiCookieStringKey = @"cookieString";

// ============================================================================
// Gemini Web 실제 RPC (SNlM0e 토큰 + StreamGenerate)
//
// --- Fact-Check Gate (AGENTS Sec.17) ---
// claim | type | source | status
//  GET https://gemini.google.com/app 에서 "SNlM0e":"..." 추출      | external protocol | directives(prompt_implement_gemini_rpc.txt) recall | UNVERIFIED (directive-sourced hypothesis)
//  POST /_/BardChatUi/data/assistant.lamda.BardFrontendService/StreamGenerate | external endpoint | 동일 지침 recall | UNVERIFIED (directive-sourced hypothesis)
//  bl=boq_assistant-bard-web-server_20240519.16_p0 상수            | external param      | 동일 지침 recall(구버전 포착값)              | UNVERIFIED — 런타임 실패 대비하여 페이지에서 "bl":"..." 동적 추출 후 폴백으로만 사용
//  f.req = [null,"[[\"질문\"],null,[\"\",\"\",\"\"]]"] + at=SNlM0e | external body format| 동일 지침 recall                              | UNVERIFIED (기기 응답 캡처로 확정 필요)
// 답변 텍스트의 정확한 인덱스 경로는 미확인 → 인덱스 하드코딩 대신
// "이중 JSON 디코딩 + 재귀 longest-text 추출" 휴리스틱을 사용하고,
// 실패 시 원문 선두를 반환+로그에 raw 앞부분(500자 제한)을 기록한다.
// ============================================================================

static NSString * const kGeminiAppURLString = @"https://gemini.google.com/app";
static NSString * const kGeminiStreamGeneratePath =
    @"/_/BardChatUi/data/assistant.lamda.BardFrontendService/StreamGenerate";
static NSString * const kDefaultBL = @"boq_assistant-bard-web-server_20240519.16_p0";  // UNVERIFIED (recall) 폴백 전용
static NSString * const kGeminiUserAgent =
    @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 "
    @"(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";

// in-memory token cache (지침 요구). 쿠키 문자열과 함께 보관하여 쿠키 회전 시 자동 무효화.
static NSString *gCachedSNlM0e = nil;
static NSString *gCachedBL = nil;
static NSString *gCacheKeyCookie = nil;

// ----------------------------------------------------------------------------
// 유틸리티
// ----------------------------------------------------------------------------

// form-value 완전 percent-encoding (URLQueryAllowedCharacterSet은 &,= 등을 남겨 파라미터가 깨진다).
static NSString *SiriGeminiFormEncode(NSString *s) {
    if (!s) return @"";
    static NSCharacterSet *allowed = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
                   @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"];
    });
    return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

// 중첩 JSON 문자열에 넣기 위한 최소 이스케이프.
static NSString *SiriGeminiJSONEscape(NSString *s) {
    if (!s) return @"";
    NSMutableString *m = [NSMutableString stringWithCapacity:s.length + 8];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        switch (c) {
            case '"':  [m appendString:@"\\\""]; break;
            case '\\': [m appendString:@"\\\\"]; break;
            case '\n': [m appendString:@"\\n"];  break;
            case '\r': [m appendString:@"\\r"];  break;
            case '\t': [m appendString:@"\\t"];  break;
            default:   [m appendFormat:@"%C", c]; break;
        }
    }
    return m;
}

// 응답 문자열에서 균형(bracket-balanced) JSON 배열 후보를 순서대로 추출.
// Google 스트리밍 응답은 ")]}'" + 복수 프레임 연결 형식이라 통째로 파싱 실패한다.
static NSArray<NSString *> *SiriGeminiBalancedArrays(NSString *text, NSUInteger maxCandidates) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSInteger depth = 0;
    NSUInteger start = NSNotFound;
    BOOL inString = NO;
    BOOL escaped = NO;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (inString) {
            if (escaped) { escaped = NO; }
            else if (c == '\\') { escaped = YES; }
            else if (c == '"') { inString = NO; }
            continue;
        }
        if (c == '"') { inString = YES; continue; }
        if (c == '[') {
            if (depth == 0) start = i;
            depth++;
        } else if (c == ']') {
            depth--;
            if (depth < 0) { depth = 0; start = NSNotFound; }
            else if (depth == 0 && start != NSNotFound) {
                [out addObject:[text substringWithRange:NSMakeRange(start, i - start + 1)]];
                start = NSNotFound;
                if (out.count >= maxCandidates) break;
            }
        }
    }
    return out;
}

static BOOL SiriGeminiLooksLikeAnswer(NSString *s) {
    if (s.length < 20) return NO;
    // 토큰/세션 ID/URL/내부 상수는 답변이 아니다.
    static NSRegularExpression *tokenRe = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tokenRe = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9_\\-\\.]+$"
                                                            options:0 error:nil];
    });
    if ([tokenRe firstMatchInString:s options:0 range:NSMakeRange(0, s.length)]) return NO;
    NSArray<NSString *> *rejects = @[@"accounts.google.com", @"http://", @"https://",
                                     @"boq_assistant", @"/_/BardChatUi", @"SNlM0e", @"wrb.fr"];
    NSString *low = s.lowercaseString;
    for (NSString *r in rejects) {
        if ([low containsString:r.lowercaseString]) return NO;
    }
    return YES;
}

// 파싱된 객체 트리를 순회하며 답변 후보(긴 자연어 문자열)를 모은다.
// 문자열이 JSON 배열처럼 보이면 한 겹 더 디코딩 (f.req류 이중 인코딩 처리).
static void SiriGeminiCollectAnswerCandidates(id obj, NSMutableArray<NSString *> *out, NSUInteger depth) {
    if (!obj || depth > 6) return;
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)obj;
        if (SiriGeminiLooksLikeAnswer(s)) [out addObject:s];
        NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([t hasPrefix:@"["] && t.length > 2) {
            NSData *d = [t dataUsingEncoding:NSUTF8StringEncoding];
            id nested = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
            if (nested) SiriGeminiCollectAnswerCandidates(nested, out, depth + 1);
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) SiriGeminiCollectAnswerCandidates(e, out, depth + 1);
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id v in [(NSDictionary *)obj allValues]) SiriGeminiCollectAnswerCandidates(v, out, depth + 1);
    }
}

// 원문에서 사람이 읽을 수 있는 블록 추출 (최후 폴백): 인용부호로 감싼 긴 문자열.
static NSString *SiriGeminiReadableBlockFallback(NSString *raw) {
    static NSRegularExpression *re = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"\"((?:[^\"\\\\\\n]|\\\\.){40,}?)\""
                                                       options:0 error:nil];
    });
    if (!re) return nil;
    __block NSString *best = nil;
    [re enumerateMatchesInString:raw options:0 range:NSMakeRange(0, raw.length)
                      usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
         NSString *s = [raw substringWithRange:[m rangeAtIndex:1]];
         s = [s stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"];
         s = [s stringByReplacingOccurrencesOfString:@"\"" withString:@"\""];
        if (SiriGeminiLooksLikeAnswer(s) && (!best || s.length > best.length)) best = s;
    }];
    return best;
}

@implementation GeminiWebClient {
    long _reqID;
}

+ (instancetype)sharedClient {
    static GeminiWebClient *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _reqID = 100000 + (long)(arc4random_uniform(800000));
    }
    return self;
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

- (NSString *)cookieHeaderFromPrefs:(NSDictionary *)prefs {
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
    return cookieHeader ?: @"";
}

- (void)invalidateTokenCache {
    gCachedSNlM0e = nil;
    gCachedBL = nil;
    gCacheKeyCookie = nil;
}

// ----------------------------------------------------------------------------
// A. SNlM0e 토큰 (+ bl) 추출 — GET /app
// ----------------------------------------------------------------------------
- (void)fetchSNlM0eWithCookie:(NSString *)cookieHeader
                   completion:(void (^)(NSString * _Nullable token, NSError * _Nullable error))completion {
    NSURL *url = [NSURL URLWithString:kGeminiAppURLString];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:30.0];
    req.HTTPMethod = @"GET";
    [req setValue:cookieHeader forHTTPHeaderField:@"Cookie"];
    [req setValue:kGeminiUserAgent forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"text/html,application/xhtml+xml" forHTTPHeaderField:@"Accept"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (error || !data) {
                if (completion) completion(nil, error ?: [NSError errorWithDomain:@"SiriGemini" code:-10 userInfo:nil]);
                return;
            }
            NSHTTPURLResponse *http = ([response isKindOfClass:[NSHTTPURLResponse class]]) ? (NSHTTPURLResponse *)response : nil;
            NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!html.length) {
                if (completion) completion(nil, [NSError errorWithDomain:@"SiriGemini"
                                                                    code:(long)(http ? http.statusCode : 0)
                                                                userInfo:@{NSLocalizedDescriptionKey: @"empty /app response"}]);
                return;
            }

            static NSRegularExpression *tokenRe = nil;
            static NSRegularExpression *blRe = nil;
            static dispatch_once_t once;
            dispatch_once(&once, ^{
                tokenRe = [NSRegularExpression regularExpressionWithPattern:@"\"SNlM0e\":\"([^\"]+)\""
                                                                    options:0 error:nil];
                blRe = [NSRegularExpression regularExpressionWithPattern:@"\"bl\":\"([^\"]+)\""
                                                                  options:0 error:nil];
            });

            NSTextCheckingResult *mt = tokenRe ? [tokenRe firstMatchInString:html options:0
                                                                       range:NSMakeRange(0, html.length)] : nil;
            if (!mt) {
                BOOL loginRedirect = ([html.lowercaseString containsString:@"accounts.google.com"] ||
                                      [response.URL.absoluteString.lowercaseString containsString:@"accounts.google.com"]);
                NSLog(@"[SiriGemini] SNlM0e not found in /app (len=%lu, status=%ld, loginRedirect=%d)",
                      (unsigned long)html.length, (long)(http ? http.statusCode : 0), loginRedirect);
                if (completion) completion(nil, [NSError errorWithDomain:@"SiriGemini"
                                                                    code:(long)(http ? http.statusCode : 0)
                                                                userInfo:@{NSLocalizedDescriptionKey:
                                                                            loginRedirect ? @"Google 로그인 쿠키 만료/미인증"
                                                                                          : @"SNlM0e 토큰 미발견"}]);
                return;
            }

            NSString *token = [html substringWithRange:[mt rangeAtIndex:1]];
            NSTextCheckingResult *mb = blRe ? [blRe firstMatchInString:html options:0
                                                                 range:NSMakeRange(0, html.length)] : nil;
            gCachedSNlM0e = token;
            gCachedBL = (mb && [mb rangeAtIndex:1].length > 0) ? [html substringWithRange:[mb rangeAtIndex:1]] : kDefaultBL;
            gCacheKeyCookie = cookieHeader;   // 쿠키 회전 시 자동 무효화 비교용 (in-memory 전용)
            NSLog(@"[SiriGemini] SNlM0e acquired (len=%lu, bl=%@)", (unsigned long)token.length, gCachedBL);
            if (completion) completion(token, nil);
        }];
    [task resume];
}

// ----------------------------------------------------------------------------
// B. StreamGenerate RPC POST + 응답 파싱
// ----------------------------------------------------------------------------
- (NSString *)extractAnswerFromResponseData:(NSData *)data {
    if (!data.length) return nil;
    NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!raw.length) return nil;

    // 안전 접두사 제거 (Google XSSI 가드).
    NSString *cleaned = [raw stringByReplacingOccurrencesOfString:@")]}'" withString:@" "];

    for (NSString *cand in SiriGeminiBalancedArrays(cleaned, 6)) {
        NSData *d = [cand dataUsingEncoding:NSUTF8StringEncoding];
        if (!d) continue;
        id parsed = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        if (!parsed) continue;
        NSMutableArray<NSString *> *candidates = [NSMutableArray array];
        SiriGeminiCollectAnswerCandidates(parsed, candidates, 0);
        if (candidates.count == 0) continue;
        // 공백을 포함하는(자연어다운) 최장 문자열 우선.
        NSString *best = nil;
        for (NSString *s in candidates) {
            BOOL hasSpace = ([s rangeOfString:@" "].location != NSNotFound);
            if (!best) best = s;
            else if ((hasSpace && [best rangeOfString:@" "].location == NSNotFound) ||
                     (hasSpace == ([best rangeOfString:@" "].location != NSNotFound) && s.length > best.length)) {
                best = s;
            }
        }
        if (best) return best;
    }

    NSString *fallback = SiriGeminiReadableBlockFallback(cleaned);
    NSLog(@"[SiriGemini] answer parse fallback used (structured=no, fallback=%@)",
          fallback ? [NSString stringWithFormat:@"%lu chars", (unsigned long)fallback.length] : @"nil");
    if (!fallback) {
        NSString *head = raw.length > 500 ? [raw substringToIndex:500] : raw;
        NSLog(@"[SiriGemini] raw response head for capture analysis: %@", head);
    }
    return fallback;
}

- (void)postStreamGenerateWithCookie:(NSString *)cookieHeader
                               token:(NSString *)token
                                  bl:(NSString *)bl
                            question:(NSString *)question
                          completion:(void (^)(NSString * _Nullable answer, NSError * _Nullable error))completion {
    // 지침 포맷(UNVERIFIED recall): f.req = [null,"[[\"질문\"],null,[\"\",\"\",\"\"]]"], at=SNlM0e
    NSString *inner = [NSString stringWithFormat:@"[[\"%@\"],null,[\"\",\"\",\"\"]]", SiriGeminiJSONEscape(question)];
    NSArray *outer = @[ (id)[NSNull null], inner ];
    NSData *fReqData = [NSJSONSerialization dataWithJSONObject:outer options:0 error:nil];
    NSString *fReq = fReqData ? [[NSString alloc] initWithData:fReqData encoding:NSUTF8StringEncoding] : nil;
    if (!fReq.length) {
        fReq = [NSString stringWithFormat:@"[null,\"%@\"]", SiriGeminiJSONEscape(inner)];  // 수동 폴백
    }

    _reqID += 100000;
    NSString *urlString = [NSString stringWithFormat:
                           @"https://gemini.google.com%@?bl=%@&_reqid=%ld&rt=c",
                           kGeminiStreamGeneratePath, SiriGeminiFormEncode(bl ?: kDefaultBL), _reqID];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        urlString = [NSString stringWithFormat:@"https://gemini.google.com%@?bl=%@&_reqid=250000&rt=c",
                     kGeminiStreamGeneratePath, SiriGeminiFormEncode(bl ?: kDefaultBL)];
        url = [NSURL URLWithString:urlString];
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:60.0];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/x-www-form-urlencoded;charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    [req setValue:cookieHeader forHTTPHeaderField:@"Cookie"];
    [req setValue:@"https://gemini.google.com" forHTTPHeaderField:@"Origin"];
    [req setValue:@"https://gemini.google.com/" forHTTPHeaderField:@"Referer"];
    [req setValue:kGeminiUserAgent forHTTPHeaderField:@"User-Agent"];

    NSString *body = [NSString stringWithFormat:@"f.req=%@&at=%@", SiriGeminiFormEncode(fReq), SiriGeminiFormEncode(token)];
    req.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSLog(@"[SiriGemini] StreamGenerate POST (bl=%@, reqid=%ld, freqLen=%lu)", bl, _reqID, (unsigned long)fReq.length);

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (error) {
                if (completion) completion(nil, error);
                return;
            }
            NSHTTPURLResponse *http = ([response isKindOfClass:[NSHTTPURLResponse class]]) ? (NSHTTPURLResponse *)response : nil;
            NSInteger status = http ? http.statusCode : 0;
            NSString *answer = [self extractAnswerFromResponseData:data];
            if (answer.length > 0) {
                NSLog(@"[SiriGemini] answer parsed (%lu chars, status=%ld)", (unsigned long)answer.length, (long)status);
                if (completion) completion(answer, nil);
                return;
            }
            NSMutableDictionary *ui = [NSMutableDictionary dictionary];
            ui[NSLocalizedDescriptionKey] = (status >= 400)
                ? [NSString stringWithFormat:@"HTTP %ld + 답변 파싱 실패", (long)status]
                : @"답변을 추출하지 못함";
            if (data.length > 0 && status < 400) {
                NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                ui[@"rawHead"] = (raw.length > 500) ? [raw substringToIndex:500] : raw;
            }
            NSLog(@"[SiriGemini] StreamGenerate no answer (status=%ld, dataLen=%lu)", (long)status, (unsigned long)data.length);
            if (completion) completion(nil, [NSError errorWithDomain:@"SiriGemini" code:(long)status userInfo:ui]);
        }];
    [task resume];
}

// ----------------------------------------------------------------------------
// 공개 API — 토큰 캐싱 + 4xx/파싱 실패 시 1회 재시도
// ----------------------------------------------------------------------------
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
    NSString *cookieHeader = [self cookieHeaderFromPrefs:prefs];
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

    // 캐시 유효성: 동일 쿠키일 때만 재사용 (__Secure-1PSIDTS 회전 대응).
    NSString *cachedToken = (gCachedSNlM0e.length > 0 && gCacheKeyCookie && [gCacheKeyCookie isEqualToString:cookieHeader])
                            ? gCachedSNlM0e : nil;
    if (cachedToken) {
        NSLog(@"[SiriGemini] using cached SNlM0e");
        NSString *bl = gCachedBL.length > 0 ? gCachedBL : kDefaultBL;
        [self postStreamGenerateWithCookie:cookieHeader token:cachedToken bl:bl question:question
                                completion:^(NSString *answer, NSError *error) {
            if (answer.length > 0 || !error) {
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(answer, error); });
                return;
            }
            // 캐시된 토큰으로 실패 → 토큰 갱신 후 1회만 재시도.
            NSLog(@"[SiriGemini] cached-token attempt failed (%@), refreshing SNlM0e", error.localizedDescription);
            [self invalidateTokenCache];
            [self fetchSNlM0eWithCookie:cookieHeader completion:^(NSString *token2, NSError *err2) {
                if (!token2.length) {
                    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err2 ?: error); });
                    return;
                }
                [self postStreamGenerateWithCookie:cookieHeader token:token2 bl:gCachedBL question:question
                                        completion:^(NSString *a2, NSError *e2) {
                    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(a2, e2); });
                }];
            }];
        }];
        return;
    }

    [self invalidateTokenCache];
    __weak typeof(self) weakSelf = self;
    [self fetchSNlM0eWithCookie:cookieHeader completion:^(NSString *token, NSError *error) {
        if (!token.length) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, error); });
            return;
        }
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, nil); });
            return;
        }
        [strongSelf postStreamGenerateWithCookie:cookieHeader token:token bl:gCachedBL question:question
                                      completion:^(NSString *answer, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(answer, err); });
        }];
    }];
}

@end
