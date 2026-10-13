#import "RootListController.h"
#import "LoginWebViewController.h"

@implementation SiriGeminiRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
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

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"SiriGemini";
}

@end
