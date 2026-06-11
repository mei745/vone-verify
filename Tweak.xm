#import <UIKit/UIKit.h>
#include <objc/runtime.h>

// ================= 配置区域 =================
#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify"
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.yourcompany.vone-verify.plist"
// =============================================

// 这里不再引用任何外部 .h 文件，直接定义我们需要的方法接口
// 这样编译器就知道 self 可以调用这些方法了
@interface MicroMessengerAppDelegate (VoneVerify)
- (void)vone_startActivationCheck;
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg isBlocking:(BOOL)blocking;
- (void)vone_verifyCodeWithServer:(NSString *)code;
@end

%hook MicroMessengerAppDelegate

- (void)applicationDidBecomeActive:(id)arg1 {
    %orig; // 先执行微信原本的业务逻辑

    // 延迟 4 秒执行，避开启动时的 UI 繁忙期
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self vone_startActivationCheck];
    });
}

// ================= 核心业务逻辑实现 =================

- (void)vone_startActivationCheck {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.yourcompany.vone-verify"];
    NSString *savedCode = [defaults stringForKey:@"activation_code"];

    if (!savedCode || savedCode.length == 0) {
        // 没有激活码，弹窗提示
        [self vone_showAlertWithTitle:@"需要激活" message:@"本插件需要激活码才能使用，请联系管理员获取。" isBlocking:YES];
    } else {
        // 有激活码，去服务器验证
        [self vone_verifyCodeWithServer:savedCode];
    }
}

- (void)vone_verifyCodeWithServer:(NSString *)code {
    // 构建请求 URL
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@&code=%@", VERIFY_URL, code]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"]; // 或者是 POST，取决于你的接口

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            // 网络错误
            dispatch_async(dispatch_get_main_queue(), ^{
                [self vone_showAlertWithTitle:@"网络错误" message:@"无法连接服务器，请检查网络。" isBlocking:NO];
            });
            return;
        }

        // 简单的解析逻辑（假设返回 JSON: {"status": 1} 为成功）
        // 注意：这里需要根据你实际的 PHP 接口返回值来修改判断逻辑
        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!jsonError && json) {
                // 假设 status 为 "success" 或 1 代表成功
                id status = json[@"status"];
                if ([status isEqual:@1] || [status isEqualToString:@"success"]) {
                    // 验证成功，什么都不做，或者存个标记
                    NSLog(@"[VoneVerify] 激活成功");
                } else {
                    // 验证失败
                    [self vone_showAlertWithTitle:@"激活失败" message:@"激活码无效或已过期" isBlocking:YES];
                }
            } else {
                 [self vone_showAlertWithTitle:@"解析错误" message:@"服务器响应异常" isBlocking:NO];
            }
        });
    }];
    [task resume];
}

- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg isBlocking:(BOOL)blocking {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];

    // 获取当前顶层控制器来展示弹窗
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }

    [rootVC presentViewController:alert animated:YES completion:nil];

    // 如果是阻塞式弹窗（必须激活），点击确定后退出微信
    if (blocking) {
        // 这里的逻辑是：用户点确定后，强制退出 App，逼迫他去找你要码
        // 也可以选择不退出，只是每次打开都弹
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
             exit(0);
        });
    }
}

%end
