#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <objc/runtime.h>

#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify"
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.yourcompany.vone-verify.plist"

@interface WeChat (VoneVerify)
- (void)vone_verifyCodeWithServer:(NSString *)code;
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg;
@end

%hook WeChat

%new
- (void)vone_verifyCodeWithServer:(NSString *)code {
    NSURL *url = [NSURL URLWithString:VERIFY_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    NSString *body = [NSString stringWithFormat:@"code=%@", code];
    [request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self vone_showAlertWithTitle:@"验证失败" message:@"网络错误，请检查连接。"];
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *status = json[@"status"];

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([status isEqualToString:@"frozen"]) {
                [self vone_showAlertWithTitle:@"激活失效" message:@"您的激活码已被冻结，请联系管理员。"];
            } else if (![status isEqualToString:@"success"]) {
                [self vone_showAlertWithTitle:@"验证失败" message:@"无效的激活码，请检查网络或联系作者。"];
            }
        });
    }];
    [task resume];
}

%new
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];

    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

%end

%ctor {
    Class wechatClass = objc_getClass("WeChat");
    if (wechatClass) {
        id wechatInstance = [wechatClass performSelector:NSSelectorFromString(@"sharedInstance")];
        if (wechatInstance) {
            NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
            NSString *savedCode = settings[@"activation_code"];
            if (savedCode.length > 0) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [(WeChat *)wechatInstance vone_verifyCodeWithServer:savedCode];
                });
            }
        }
    }
}
