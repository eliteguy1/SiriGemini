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
    // 601078-UI: 배경색 미지정 시 투명하게 뒤 화면이 비치므로 불투명 지정.
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"Google 로그인";

    // 좌측 취소 / 우측 완료 (모달 dismiss 구조).
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"취소"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(cancelAndDismiss:)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"완료"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(saveCookiesAndFinish)];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    // 601078-UI: 기본 WKWebView UA는 Google이 차단(disallowed_useragent)할 수 있어
    // Safari 실기기 UA로 위장.
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.customUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
    // 601078-UI: viewDidLoad 시점 bounds는 0x0일 수 있으므로 autoresizing 대신
    // Safe Area 오토레이아웃으로 크기 확정.
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    [self.view addSubview:self.webView];
    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
    ]];

    // 601078-UI: 로딩 인디케이터 (중앙).
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];
    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    // NOTE: 기존 하단 "Gemini 열기" 툴바는 제거 — 초기 URL이 이미 gemini.google.com이며,
    // top/height 제약 없는 모호한 레이아웃이 렌더링 불량의 한 축이었음.
    NSURL *url = [NSURL URLWithString:@"https://gemini.google.com/"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)cancelAndDismiss:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
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
        BOOL savedOK = NO;
        if (hasCore && allCookiesString.length > 0) {
            NSMutableDictionary *prefs =
                [[NSDictionary dictionaryWithContentsOfFile:kPrefsPath] mutableCopy] ?: [NSMutableDictionary dictionary];
            prefs[kCookieStringKey] = allCookiesString;
            if (psid) prefs[kCookie1PSID] = psid;       // 기존 호환 유지
            if (psidts) prefs[kCookie1PSIDTS] = psidts; // 기존 호환 유지
            BOOL ok = [prefs writeToFile:kPrefsPath atomically:YES];
            savedOK = ok;
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
            // 601078-UI: 저장 성공 시 확인을 누르면 모달 자동 닫기.
            [alert addAction:[UIAlertAction actionWithTitle:@"확인"
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction * _Nonnull action) {
                (void)action;
                if (savedOK) {
                    [self dismissViewControllerAnimated:YES completion:nil];
                }
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    }];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    (void)navigation;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.spinner startAnimating];
    });
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    // 601078: gemini.google.com 도달 여부 확인 로그 (쿠키 발급 도메인 판정에 사용).
    NSString *host = webView.URL.host ?: @"";
    BOOL onGemini = ([host containsString:@"gemini.google.com"]);
    NSLog(@"[SiriGemini] login webview finished: %@ (onGemini:%@)", webView.URL, onGemini ? @"YES" : @"NO");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.spinner stopAnimating];
    });
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)navigation;
    NSLog(@"[SiriGemini] login webview failed: %@", error);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.spinner stopAnimating];
    });
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)navigation;
    NSLog(@"[SiriGemini] login webview provisional failed: %@", error);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.spinner stopAnimating];
    });
}

@end
