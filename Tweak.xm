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

- (void)applicationDidBecomeActive:(id)arg1 {
    %orig;
    // 延迟 3 秒执行，避免启动时 UI 冲突
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self vone_startActivationCheck];
    });
}

%new
- (void)vone_startActivationCheck {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedCode = [defaults stringForKey:@"vone_activation_code"];

    if (!savedCode || savedCode.length == 0) {
        [self vone_showAlertWithTitle:@"需要激活" message:@"本插件需要激活码才能使用，请联系管理员获取。" isBlocking:YES];
        return;
    }

    // 有激活码，去服务器验证
    [self vone_verifyCodeWithServer:savedCode];
}

%new
- (void)vone_verifyCodeWithServer:(NSString *)code {
    NSURL *url = [NSURL URLWithString:VERIFY_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    // 构造 POST 数据
    NSString *postString = [NSString stringWithFormat:@"code=%@", code];
    NSData *postData = [postString dataUsingEncoding:NSUTF8StringEncoding];
    request.HTTPBody = postData;

    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self vone_showAlertWithTitle:@"网络错误" message:@"无法连接服务器，请检查网络。" isBlocking:NO];
            });
            return;
        }

        // 解析 JSON
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *status = json[@"status"]; // 假设服务器返回 {"status": "success"} 或 "fail"

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([status isEqualToString:@"success"]) {
                // 激活成功，什么都不做，或者存个标记
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"vone_is_activated"];
            } else {
                [self vone_showAlertWithTitle:@"激活失败" message:@"激活码无效或已过期" isBlocking:YES];
            }
        });
    }] resume];
}

%new
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg isBlocking:(BOOL)blocking {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];

    // 强制在最顶层窗口显示
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (window) {
        [window.rootViewController presentViewController:alert animated:YES completion:nil];
    }
}

%end
