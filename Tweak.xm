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
                [self vone_showAlertWithTitle:@"验证失败" message:@"网络请求超时或错误"];
            });
            return;
        }

        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (!jsonError && json) {
            NSString *status = json[@"status"];
            if ([status isEqualToString:@"success"]) {
                [[NSUserDefaults standardUserDefaults] setObject:@(YES) forKey:@"VoneActivated"];
                [[NSUserDefaults standardUserDefaults] synchronize];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self vone_showAlertWithTitle:@"激活失效" message:@"您的激活码已被冻结，请联系管理员。"];
                });
            }
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self vone_showAlertWithTitle:@"验证失败" message:@"无效的激活码，请检查网络或联系作者。"];
            });
        }
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
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isActivated = [defaults boolForKey:@"VoneActivated"];

    if (!isActivated) {
        Class wechatClass = objc_getClass("WeChat");
        if (wechatClass) {
            id wechatInstance = [wechatClass performSelector:NSSelectorFromString(@"sharedInstance")];
            if (wechatInstance) {
                NSString *savedCode = [defaults stringForKey:@"VoneActivationCode"];
                if (savedCode.length > 0) {
                    [(WeChat *)wechatInstance vone_verifyCodeWithServer:savedCode];
                } else {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        UIAlertController *inputAlert = [UIAlertController alertControllerWithTitle:@"请输入激活码" message:nil preferredStyle:UIAlertControllerStyleAlert];
                        [inputAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                            textField.placeholder = @"输入激活码";
                        }];

                        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                            UITextField *textField = inputAlert.textFields.firstObject;
                            if (textField.text.length > 0) {
                                [defaults setObject:textField.text forKey:@"VoneActivationCode"];
                                [defaults synchronize];

                                Class wcClass = objc_getClass("WeChat");
                                id wcInst = [wcClass performSelector:NSSelectorFromString(@"sharedInstance")];
                                if (wcInst) {
                                    [(WeChat *)wcInst vone_verifyCodeWithServer:textField.text];
                                }
                            }
                        }];

                        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
                        [inputAlert addAction:confirmAction];
                        [inputAlert addAction:cancelAction];

                        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                        while (rootVC.presentedViewController) {
                            rootVC = rootVC.presentedViewController;
                        }
                        [rootVC presentViewController:inputAlert animated:YES completion:nil];
                    });
                }
            }
        }
    }
}
