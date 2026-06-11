#import <UIKit/UIKit.h>
#include <objc/runtime.h>

// ================= 配置区域 =================
#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify" // 你的验证接口
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.yourcompany.vone-verify.plist"
// =============================================

// 【关键修复】这里必须用 @interface ... (Category)，绝对不能用 @class
@interface MicroMessengerAppDelegate (VoneVerify)
- (void)vone_startActivationCheck;
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg isBlocking:(BOOL)blocking;
- (void)vone_verifyCodeWithServer:(NSString *)code;
@end

%hook MicroMessengerAppDelegate

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    // 启动后延迟 4 秒检查，避开微信启动时的 UI 繁忙期
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self vone_startActivationCheck];
    });
}

%new
- (void)vone_startActivationCheck {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.yourcompany.vone-verify"];
    NSString *savedCode = [defaults stringForKey:@"activation_code"];

    if (!savedCode || savedCode.length == 0) {
        [self vone_showAlertWithTitle:@"需要激活" message:@"本插件需要激活码才能使用，请联系管理员获取。" isBlocking:YES];
    } else {
        [self vone_verifyCodeWithServer:savedCode];
    }
}

%new
- (void)vone_verifyCodeWithServer:(NSString *)code {
    NSURL *url = [NSURL URLWithString:VERIFY_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    // 【语法修复】先格式化字符串，再转 Data，避免 .dataUsingEncoding 报错
    NSString *bodyString = [NSString stringWithFormat:@"code=%@", code];
    request.HTTPBody = [bodyString dataUsingEncoding:NSUTF8StringEncoding];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self vone_showAlertWithTitle:@"网络错误" message:@"无法连接服务器，请检查网络。" isBlocking:NO];
            });
            return;
        }

        // 简单的成功判断逻辑（根据你的服务器实际返回修改）
        NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        BOOL isSuccess = [responseString containsString:@"success"] || [responseString isEqualToString:@"1"];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!isSuccess) {
                [self vone_showAlertWithTitle:@"激活失败" message:@"激活码无效或已过期" isBlocking:YES];
            }
        });
    }];
    [task resume];
}

%new
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg isBlocking:(BOOL)blocking {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];

    // 获取当前顶层控制器来弹窗
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

%end
