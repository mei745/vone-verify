#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <objc/runtime.h> // 必须引入，用于获取第三方类

#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify"
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.yourcompany.vone-verify.plist"

// === 核心修复：声明 WeChat 的分类 ===
// 这告诉编译器：WeChat 类现在有下面这些方法了，请放心编译
@interface WeChat (VoneVerify)
- (void)vone_verifyCodeWithServer:(NSString *)code;
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg;
@end
// ==============================

%hook WeChat

// 1. 实现自定义的验证方法
%new
- (void)vone_verifyCodeWithServer:(NSString *)code {
    NSURL *url = [NSURL URLWithString:VERIFY_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    NSString *postString = [NSString stringWithFormat:@"code=%@&udid=%@",
                            code,
                            [[[UIDevice currentDevice] identifierForVendor] UUIDString]];
    request.HTTPBody = [postString dataUsingEncoding:NSUTF8StringEncoding];

    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *status = json[@"status"];

            dispatch_async(dispatch_get_main_queue(), ^{
                if ([status isEqualToString:@"success"]) {
                    NSLog(@"[VoneVerify] Activation Success!");
                } else if ([status isEqualToString:@"frozen"]) {
                    [self vone_showAlertWithTitle:@"激活失效" message:@"您的激活码已被冻结，请联系管理员。"];
                } else {
                    [self vone_showAlertWithTitle:@"验证失败" message:@"无效的激活码，请检查网络或联系作者。"];
                }
            });
        } else {
             dispatch_async(dispatch_get_main_queue(), ^{
                 [self vone_showAlertWithTitle:@"网络错误" message:@"无法连接验证服务器。"];
             });
        }
    }] resume];
}

// 2. 实现自定义的弹窗方法
%new
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];

    // 获取当前最顶层的 ViewController 来展示弹窗
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

// 3. 构造函数：插件加载时立即运行
%ctor {
    %orig;

    // 延迟 2 秒执行，确保微信 UI 已经初始化完毕
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // 读取本地 plist
        NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
        NSString *savedCode = settings[@"activation_code"];

        if (savedCode && savedCode.length > 0) {
            // === 关键修复：使用 objc_getClass 和 performSelector ===
            // 这样既绕过了编译器的类型检查，又避免了 ARC 警告
            Class wechatClass = objc_getClass("WeChat");
            id wechatInstance = [wechatClass performSelector:NSSelectorFromString(@"sharedInstance")];

            if (wechatInstance) {
                [wechatInstance vone_verifyCodeWithServer:savedCode];
            }
        }
    });
}

%end
