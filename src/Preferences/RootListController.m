#import "RootListController.h"
#import "LoginWebViewController.h"

static NSString * const kPrefsPath = @"/var/mobile/Library/Preferences/com.csw.sirigemini.plist";

@implementation SiriGeminiRootListController

// 로그인 상태 판정: cookieString 또는 __Secure-1PSID 존재 시 로그인됨.
- (BOOL)siriGeminiIsLoggedIn {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    NSString *cookieString = prefs[@"cookieString"];
    NSString *psid = prefs[@"__Secure-1PSID"];
    return (cookieString.length > 0 || psid.length > 0);
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSArray *loaded = [self loadSpecifiersFromPlistName:@"Root" target:self];
        NSMutableArray *specs = [loaded mutableCopy] ?: [NSMutableArray array];
        BOOL loggedIn = [self siriGeminiIsLoggedIn];

        for (PSSpecifier *spec in [specs copy]) {
            // action은 ivar(protected)라 propertyForKey:@"action"(PSActionKey 문자열)으로 식별.
            NSString *actionName = [spec propertyForKey:@"action"];
            // 1) 로그인 버튼 라벨 동적 변경.
            if ([actionName isEqualToString:@"openGoogleLogin:"]) {
                spec.name = loggedIn ? @"Google 계정 재연결 (로그인됨 ✓)"
                                     : @"Google 로그인 (로그인 필요)";
            }
            // 2) 미로그인 시 로그아웃 버튼 숨김.
            else if ([actionName isEqualToString:@"logoutGoogle:"]) {
                if (!loggedIn) [specs removeObject:spec];
            }
            // 3) 하단 그룹 푸터에 상태 텍스트 동적 구성.
            else if (spec.cellType == PSGroupCell && [spec propertyForKey:@"footerText"] != nil) {
                [spec setProperty:(loggedIn ? @"현재 상태: Google 계정 연동 완료 (Siri 사용 가능)"
                                            : @"현재 상태: 미로그인 (Google 로그인이 필요합니다)")
                           forKey:@"footerText"];
            }
        }
        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (void)openGoogleLogin:(id)sender {
    // 601078-UI: Settings 네비게이션 스택 분리 — 모달로 띄워 안전하게 표시.
    SiriGeminiLoginWebViewController *vc = [[SiriGeminiLoginWebViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)logoutGoogle:(id)sender {
    (void)sender;
    NSMutableDictionary *prefs =
        [[NSDictionary dictionaryWithContentsOfFile:kPrefsPath] mutableCopy] ?: [NSMutableDictionary dictionary];
    [prefs removeObjectForKey:@"cookieString"];
    [prefs removeObjectForKey:@"__Secure-1PSID"];
    [prefs removeObjectForKey:@"__Secure-1PSIDTS"];
    BOOL ok = [prefs writeToFile:kPrefsPath atomically:YES];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.csw.sirigemini.settingschanged"),
                                         NULL, NULL, YES);
    [self reloadSpecifiers];
    NSString *message = ok ? @"로그아웃 완료 (저장된 쿠키가 삭제되었습니다)"
                           : @"plist 저장 실패 (경로/권한 확인 필요)";
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"SiriGemini"
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"확인"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"SiriGemini";
}

// 모달이 닫히고 복귀 시 로그인 상태 즉시 반영.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

@end
