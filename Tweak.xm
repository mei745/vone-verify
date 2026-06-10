#import <UIKit/UIKit.h>
#include <objc/runtime.h>

// ================= 配置区域 =================
#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify" // 你的验证接口
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.yourcompany.vone-verify.plist"
// =============================================

// 【关键修复】必须在 %hook 之前定义 Category 接口
// 这告诉编译器：MicroMessengerAppDelegate 现在有了下面这些新方法
@interface MicroMessengerAppDelegate (VoneVerify)
- (void)vone_startActivationCheck;
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg isBlocking:(BOOL)blocking;
- (void)vone_verifyCodeWithServer:(NSString *)code;
@end

%hook MicroMessengerAppDelegate

// 1. 微信启动完成后的回调 (适配 iOS 13+ SceneDelegate 逻辑通常也兼容此 Hook)
- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig; // 先执行微信原本的逻辑

    // 使用 dispatch_once 确保只在第一次激活时检查，避免切后台回来重复弹窗
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 延迟 4 秒检查，避开微信启动时的 UI 渲染高峰
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self vone_startActivationCheck];
        });
    });
}

%new
- (void)vone_startActivationCheck {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.yourcompany.vone-verify"];
    NSString *savedCode = [defaults stringForKey:@"activation_code"];

    if (!savedCode || savedCode.length == 0) {
        // 没有保存过激活码，直接弹窗提示输入
        [self vone_showAlertWithTitle:@"需要激活" message:@"本插件需要激活码才能使用，请联系管理员获取。" isBlocking:YES];
    } else {
        // 有激活码，去服务器验证
        [self vone_verifyCodeWithServer:savedCode];
    }
}

%new
- (void)vone_verifyCodeWithServer:(NSString *)code {
    NSURL *url = [NSURL URLWithString:VERIFY_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    // 构建 POST 参数 (根据你的后端需求调整)
    NSString *postString = [NSString stringWithFormat:@"code=%@", code];
    request.HTTPBody = [postString dataUsingEncoding:NSUTF8StringEncoding];

    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            // 网络错误处理
            dispatch_async(dispatch_get_main_queue(), ^{
                [self vone_showAlertWithTitle:@"网络错误" message:@"无法连接服务器，请检查网络。" isBlocking:NO];
            });
            return;
        }

        // 解析 JSON 返回结果
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSNumber *status = json[@"status"]; // 假设后端返回 status: 1 为成功

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([status integerValue] == 1) {
                // 验证成功，不做任何操作，或者显示一个 Toast 提示成功
                NSLog(@"[VoneVerify] Activation Success");
            } else {
                // 验证失败（过期或无效）
                [self vone_showAlertWithTitle:@"激活失败" message:@"激活码无效或已过期" isBlocking:YES];
            }
        });
    }] resume];
}

%new
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg isBlocking:(BOOL)blocking {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                 message:msg
                                                          preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (blocking) {
            // 如果是阻塞式弹窗（如未激活），点击确定后退出微信
            exit(0);
        }
    }];
    [alert addAction:okAction];

    // 获取当前顶层控制器来展示弹窗
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIViewController *rootVC = window.rootViewController;

    // 寻找当前最上层的 ViewController
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }

    [rootVC presentViewController:alert animated:YES completion:nil];
}

%end
