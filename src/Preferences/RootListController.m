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
    SiriGeminiLoginWebViewController *vc = [[SiriGeminiLoginWebViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"SiriGemini";
}

@end
