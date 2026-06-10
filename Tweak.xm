#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify"
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.yourcompany.vone-verify.plist"

// 声明自定义方法接口，防止编译警告
@interface WeChat (VoneVerify)
- (void)vone_verifyCodeWithServer:(NSString *)code;
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg;
@end

%hook WeChat

// 新增：添加一个专门用来显示弹窗的方法
%new
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *ok = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
        [alert addAction:ok];

        // 获取当前最顶层的 ViewController 来展示弹窗
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        UIViewController *rootVC = window.rootViewController;
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }
        [rootVC presentViewController:alert animated:YES completion:nil];
    });
}

// 新增：验证逻辑
%new
- (void)vone_verifyCodeWithServer:(NSString *)code {
    NSLog(@"[VoneVerify] Starting verification for code: %@", code);

    NSURL *url = [NSURL URLWithString:VERIFY_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    NSString *postString = [NSString stringWithFormat:@"code=%@&udid=%@",
                            code,
                            [[[UIDevice currentDevice] identifierForVendor] UUIDString]];
    request.HTTPBody = [postString dataUsingEncoding:NSUTF8StringEncoding];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[VoneVerify] Network Error: %@", error.localizedDescription);
            return;
        }
        if (!data) {
            NSLog(@"[VoneVerify] No Data Received");
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *status = json[@"status"];
        NSLog(@"[VoneVerify] Server Response: %@", status);

        if ([status isEqualToString:@"success"]) {
            NSLog(@"[VoneVerify] Activation Success!");
            // 验证成功，不弹窗，或者弹个欢迎窗
        } else if ([status isEqualToString:@"frozen"]) {
            [self vone_showAlertWithTitle:@"激活失效" message:@"您的激活码已被冻结，请联系管理员。"];
        } else {
            [self vone_showAlertWithTitle:@"验证失败" message:@"无效的激活码，请检查网络或联系作者。"];
        }
    }] resume];
}

%end

// === 关键修改：使用 ctor 确保代码在插件加载时运行 ===
%ctor {
    // 延迟 2 秒执行，等待微信 UI 初始化完成，避免崩溃
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"[VoneVerify] Tweak Loaded! Checking activation...");

        // 读取本地配置
        NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
        NSString *savedCode = settings[@"activation_code"];

        if (savedCode && savedCode.length > 0) {
            // 获取 WeChat 单例来调用我们的新方法
            // 注意：这里假设 WeChat 是单例，如果不是，可能需要用 [WeChat new] 或其他方式
            id wechatInstance = [%c(WeChat) shareInstance]; // 尝试获取单例
            if (!wechatInstance) {
                wechatInstance = [[%c(WeChat) alloc] init]; // 如果拿不到单例，直接新建一个实例来跑验证逻辑
            }

            [wechatInstance vone_verifyCodeWithServer:savedCode];
        } else {
            NSLog(@"[VoneVerify] No saved code found.");
            // 可选：如果没有码，也可以在这里弹窗让用户输入
        }
    });
}
