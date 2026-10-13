#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface SiriGeminiLoginWebViewController : UIViewController <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
- (void)saveCookiesAndFinish;
@end
