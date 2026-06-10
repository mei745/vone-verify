#import <UIKit/UIKit.h>
#include <objc/runtime.h>

// 配置项
#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify"
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.yourcompany.vone-verify.plist"

// ==========================================
// 【关键修复】必须在 %hook 之前定义 Category 接口
// 这告诉编译器：MicroMessengerAppDelegate 现在有了下面这些新方法
// ==========================================
@interface MicroMessengerAppDelegate (VoneVerify)
- (void)vone_checkActivationStatus;
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg;
@end

%hook MicroMessengerAppDelegate

// 1. 实现自定义的弹窗方法
%new
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg {
    // 获取当前顶层控制器，防止弹窗被遮挡或崩溃
    UIViewController *rootVC = self.window.rootViewController;
    if (!rootVC) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];

    [rootVC presentViewController:alert animated:YES completion:nil];
}

// 2. 核心验证逻辑
%new
- (void)vone_checkActivationStatus {
    // 读取本地激活状态
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
    NSString *savedCode = settings[@"activation_code"];
    BOOL isActivated = [settings[@"is_activated"] boolValue];

    // 如果已激活，直接跳过
    if (isActivated && savedCode.length > 0) {
        NSLog(@"[VoneVerify] 插件已激活，跳过验证。");
        return;
    }

    // --- 模拟验证流程 ---
    // 注意：实际项目中这里应该发起网络请求
    // 为了演示效果，这里假设验证失败，弹出提示
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self vone_showAlertWithTitle:@"需要激活" message:@"检测到插件未激活，请联系管理员获取激活码。\n\n(此处应弹出输入框或跳转设置页)"];
    });
}

// 3. Hook 启动完成方法
- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig; // 先执行微信原始逻辑

    // 使用 dispatch_once 确保只在每次冷启动时检查一次
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 【核心修改】延迟 4 秒执行，完美落在 3-6 秒区间内
        // 此时微信的主线程 UI 已经完全渲染完毕，弹窗不会导致白屏或卡顿
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self vone_checkActivationStatus];
        });
    });
}

%end
