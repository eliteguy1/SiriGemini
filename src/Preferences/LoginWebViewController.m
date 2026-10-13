#import "LoginWebViewController.h"

// Cookie names per step-1 spec — UNVERIFIED (recall), runtime verification required.
//601078: 2개 엄격 판정에서 핵심 쿠키 중 1개 이상 + 전체 쿠키 문자열 저장 방식으로 완화.
static NSString * const kCookie1PSID = @"__Secure-1PSID";
static NSString * const kCookie1PSIDTS = @"__Secure-1PSIDTS";
static NSString * const kCookie3PSID = @"__Secure-3PSID";
static NSString * const kCookieSID = @"SID";
static NSString * const kCookieStringKey = @"cookieString";
static NSString * const kPrefsPath = @"/var/mobile/Library/Preferences/com.csw.sirigemini.plist";

@implementation SiriGeminiLoginWebViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Google 로그인";

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    [self.view addSubview:self.webView];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"완료"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(saveCookiesAndFinish)];

    // 601078: 초기 URL을 gemini.google.com으로 — 미로그인 시 Google 로그인으로
    // 자동 이동하고, 로그인 완료 시 Gemini 홈으로 진입하면서 Gemini 쿠키가 발급됨.
    // (이전 accounts.google.com 초기 로드에서는 Gemini 쿠키가 발급되지 않았음)
    NSURL *url = [NSURL URLWithString:@"https://gemini.google.com/"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];

    // 보조: 하단 Gemini 바로가기 버튼
    UIToolbar *toolbar = [[UIToolbar alloc] init];
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    UIBarButtonItem *geminiItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Gemini 열기"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(openGemini:)];
    toolbar.items = @[geminiItem];
    [self.view addSubview:toolbar];
    [NSLayoutConstraint activateConstraints:@[
        [toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [toolbar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
    ]];
}

- (void)openGemini:(id)sender {
    [self.webView loadRequest:[NSURLRequest requestWithURL:
        [NSURL URLWithString:@"https://gemini.google.com/"]]];
}

// WKWebsiteDataStore의 WKHTTPCookieStore에서 로그인 쿠키 추출 → plist 저장.
// 601078 전면 개선: .google.com / gemini.google.com 쿠키 전체를 수집하고,
// 핵심 쿠키(SID, __Secure-1PSID, __Secure-3PSID, __Secure-1PSIDTS) 중 1개 이상이면
// 성공 판정. 전체를 "name=value; ..." 문자열(cookieString)로 저장해 RPC에서 주입.
- (void)saveCookiesAndFinish {
    WKHTTPCookieStore *store = self.webView.configuration.websiteDataStore.httpCookieStore;
    [store getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        NSString *psid = nil, *psidts = nil, *psid3 = nil, *sid = nil;
        NSMutableArray<NSString *> *pairs = [NSMutableArray array];
        NSMutableArray<NSString *> *collectedNames = [NSMutableArray array];
        for (NSHTTPCookie *c in cookies) {
            NSString *domain = c.domain ?: @"";
            BOOL relevant = ([domain containsString:@"google.com"] ||
                             [domain containsString:@"gemini.google.com"]);
            if (!relevant) continue;
            [collectedNames addObject:[NSString stringWithFormat:@"%@(%@)", c.name, domain]];
            if (c.value.length == 0) continue;
            [pairs addObject:[NSString stringWithFormat:@"%@=%@", c.name, c.value]];
            if ([c.name isEqualToString:kCookie1PSID]) psid = c.value;
            else if ([c.name isEqualToString:kCookie1PSIDTS]) psidts = c.value;
            else if ([c.name isEqualToString:kCookie3PSID]) psid3 = c.value;
            else if ([c.name isEqualToString:kCookieSID]) sid = c.value;
        }
        NSString *allCookiesString = [pairs componentsJoinedByString:@"; "];
        BOOL hasCore = (sid.length > 0 || psid.length > 0 || psid3.length > 0 || psidts.length > 0);
        NSLog(@"[SiriGemini] cookies: %lu relevant (SID:%@ 1PSID:%@ 3PSID:%@ 1PSIDTS:%@) names=%@",
              (unsigned long)[collectedNames count],
              sid.length > 0 ? @"Y" : @"n", psid.length > 0 ? @"Y" : @"n",
              psid3.length > 0 ? @"Y" : @"n", psidts.length > 0 ? @"Y" : @"n",
              [collectedNames componentsJoinedByString:@", "]);

        NSString *message;
        if (hasCore && allCookiesString.length > 0) {
            NSMutableDictionary *prefs =
                [[NSDictionary dictionaryWithContentsOfFile:kPrefsPath] mutableCopy] ?: [NSMutableDictionary dictionary];
            prefs[kCookieStringKey] = allCookiesString;
            if (psid) prefs[kCookie1PSID] = psid;       // 기존 호환 유지
            if (psidts) prefs[kCookie1PSIDTS] = psidts; // 기존 호환 유지
            BOOL ok = [prefs writeToFile:kPrefsPath atomically:YES];
            // Tweak 프로세스에 설정 변경 브로드캐스트
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 CFSTR("com.csw.sirigemini.settingschanged"),
                                                 NULL, NULL, YES);
            message = ok ? [NSString stringWithFormat:
                            @"Google 로그인 쿠키 저장 완료 (쿠키 %lu개 감지, SID:%@ 1PSID:%@ 3PSID:%@ 1PSIDTS:%@)",
                            (unsigned long)[pairs count],
                            sid.length > 0 ? @"O" : @"X", psid.length > 0 ? @"O" : @"X",
                            psid3.length > 0 ? @"O" : @"X", psidts.length > 0 ? @"O" : @"X"]
                         : @"plist 저장 실패 (경로/권한 확인 필요)";
        } else {
            NSString *names = [collectedNames count] > 0
                ? [collectedNames componentsJoinedByString:@", "]
                : @"(수집된 Google 쿠키 없음)";
            message = [NSString stringWithFormat:
                       @"로그인 쿠키를 찾지 못했습니다. WebView에서 Google 로그인을 먼저 완료하세요. [수집: %@]",
                       names];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert =
                [UIAlertController alertControllerWithTitle:@"SiriGemini"
                                                    message:message
                                             preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"확인"
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    }];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    // 601078: gemini.google.com 도달 여부 확인 로그 (쿠키 발급 도메인 판정에 사용).
    NSString *host = webView.URL.host ?: @"";
    BOOL onGemini = ([host containsString:@"gemini.google.com"]);
    NSLog(@"[SiriGemini] login webview finished: %@ (onGemini:%@)", webView.URL, onGemini ? @"YES" : @"NO");
}

@end
