#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <objc/runtime.h>

#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify"

// 【关键修改】1. 必须在 Hook 之前定义 Category 接口
// 这告诉编译器："WeChat 类现在有了这些新方法"
@interface WeChat (VoneVerify)
- (void)vone_verifyCodeWithServer:(NSString *)code;
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg;
@end

%hook WeChat

// 2. 实现验证方法
%new
- (void)vone_verifyCodeWithServer:(NSString *)code {
    NSURL *url = [NSURL URLWithString:VERIFY_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    NSString *body = [NSString stringWithFormat:@"code=%@", code];
    [request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];

    // 使用 NSURLSession 进行网络请求
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            // 假设服务器返回 "success" 表示验证通过
            NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if ([result isEqualToString:@"success"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self vone_showAlertWithTitle:@"激活成功" message:@"插件已激活！"];
                });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self vone_showAlertWithTitle:@"激活失败" message:@"激活码无效或已过期。"];
                });
            }
        } else {
             dispatch_async(dispatch_get_main_queue(), ^{
                [self vone_showAlertWithTitle:@"网络错误" message:@"无法连接服务器，请检查网络。"];
            });
        }
    }] resume];
}

// 3. 实现弹窗辅助方法
%new
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];

    // 获取当前显示的控制器来展示弹窗
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

// 4. 示例：在某个初始化方法中调用验证 (例如 -init 或 -applicationDidFinishLaunching:)
// 注意：你需要根据实际逆向出来的微信入口点来修改这里的方法名
- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig; // 执行原始逻辑

    // 模拟从本地读取保存的激活码
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedCode = [defaults stringForKey:@"vone_activation_code"];

    if (savedCode.length > 0) {
        // 【关键修改】直接调用 self 的方法，不需要 performSelector，也不需要 sharedInstance
        // 因为此时 self 就是 WeChat 的实例
        [self vone_verifyCodeWithServer:savedCode];
    }
}

%end
