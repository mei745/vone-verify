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
@end

%hook MicroMessengerAppDelegate

// 微信启动完成后的回调
- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig; // 必须先执行原始逻辑

    // 延迟 4 秒执行检查，避免影响微信主界面加载
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self vone_startActivationCheck];
    });
}

%new
- (void)vone_startActivationCheck {
    // 1. 读取本地保存的激活码
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
    NSString *savedCode = prefs[@"activation_code"];

    if (!savedCode || savedCode.length == 0) {
        // 如果没有激活码，直接弹窗
        [self vone_showAlertWithTitle:@"需要激活" message:@"本插件需要激活码才能使用，请联系管理员获取。" isBlocking:YES];
        return;
    }

    // 2. 有激活码，进行联网验证
    NSURL *url = [NSURL URLWithString:VERIFY_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSString stringWithFormat:@"code=%@", savedCode].dataUsingEncoding:NSUTF8StringEncoding];
    request.timeoutInterval = 10.0;

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                // 网络错误
                [self vone_showAlertWithTitle:@"网络错误" message:@"无法连接服务器，请检查网络。" isBlocking:NO];
                return;
            }

            // 3. 解析服务器返回结果 (假设服务器返回 JSON: {"status": "success"})
            NSError *jsonError;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            NSString *status = json[@"status"];

            if ([status isEqualToString:@"success"]) {
                // 验证成功，什么都不做，或者可以存个标记
                NSLog(@"[VoneVerify] Activation Success");
            } else {
                // 验证失败
                [self vone_showAlertWithTitle:@"激活失败" message:@"激活码无效或已过期" isBlocking:YES];
            }
        });
    }] resume];
}

%new
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg isBlocking:(BOOL)blocking {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (blocking) {
            // 如果是阻塞式弹窗，点击确定后退出微信或强制关闭
            exit(0);
        }
    }];
    [alert addAction:okAction];

    // 获取当前显示的 ViewController
    UIViewController *rootVC = [UIApplication sharedApplication].delegate.window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

%end
