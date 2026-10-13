#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface SiriGeminiLoginWebViewController : UIViewController <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
- (void)saveCookiesAndFinish;
- (void)cancelAndDismiss:(id)sender;
@end
