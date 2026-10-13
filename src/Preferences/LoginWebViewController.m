#import "LoginWebViewController.h"

// Cookie names per step-1 spec — UNVERIFIED (recall), runtime verification required.
static NSString * const kCookie1PSID = @"__Secure-1PSID";
static NSString * const kCookie1PSIDTS = @"__Secure-1PSIDTS";
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

    NSURL *url = [NSURL URLWithString:@"https://accounts.google.com/"];
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
- (void)saveCookiesAndFinish {
    WKHTTPCookieStore *store = self.webView.configuration.websiteDataStore.httpCookieStore;
    [store getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        NSString *psid = nil, *psidts = nil;
        for (NSHTTPCookie *c in cookies) {
            if ([c.name isEqualToString:kCookie1PSID]) psid = c.value;
            else if ([c.name isEqualToString:kCookie1PSIDTS]) psidts = c.value;
        }

        NSString *message;
        if (psid.length > 0 && psidts.length > 0) {
            NSMutableDictionary *prefs =
                [[NSDictionary dictionaryWithContentsOfFile:kPrefsPath] mutableCopy] ?: [NSMutableDictionary dictionary];
            prefs[kCookie1PSID] = psid;
            prefs[kCookie1PSIDTS] = psidts;
            BOOL ok = [prefs writeToFile:kPrefsPath atomically:YES];
            // Tweak 프로세스에 설정 변경 브로드캐스트
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 CFSTR("com.csw.sirigemini.settingschanged"),
                                                 NULL, NULL, YES);
            message = ok ? @"Google 로그인 쿠키 저장 완료" : @"plist 저장 실패 (경로/권한 확인 필요)";
        } else {
            message = @"로그인 쿠키를 찾지 못했습니다. WebView에서 Google 로그인을 먼저 완료하세요.";
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
    // 로그인 완료 후 gemini.google.com 쿠키가 심어지므로, navigation 완료 시점에
    // 자동 저장하지는 않고 사용자가 "완료"를 눌러 명시적으로 저장한다.
    NSLog(@"[SiriGemini] login webview finished: %@", webView.URL);
}

@end
