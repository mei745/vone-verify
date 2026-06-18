#import <UIKit/UIKit.h>
#include <dlfcn.h> // 用于 exit(0)

// === 配置区域 ===
#define VERIFY_URL @"https://vonekeji.cn/codes.json" // 你的数据库地址
#define PREFS_KEY @"vone_activation_code"            // 存储激活码的Key
#define PREFS_STATUS @"vone_is_activated"            // 存储是否已激活的Key

// 声明我们要Hook的微信主类
@interface MicroMessengerAppDelegate : UIResponder <UIApplicationDelegate>
@end

// --- 辅助函数：获取当前最顶层的控制器 ---
UIViewController *TopMostViewController() {
    UIViewController *rootVC = [[UIApplication sharedApplication].keyWindow rootViewController];
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    return rootVC;
}

%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 1. 先执行微信原本的启动逻辑
    BOOL result = %orig;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isActivated = [defaults boolForKey:PREFS_STATUS];

    // 2. 判断逻辑：如果没有激活，才执行下面的弹窗代码
    if (!isActivated) {
        // 延迟1秒弹出，确保微信主窗口已经加载完毕
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔒 Vone Verify 授权验证"
                                                                           message:@"检测到您尚未激活，请输入正确的激活码。\n⚠️ 输入错误将导致应用重启"
                                                                    preferredStyle:UIAlertControllerStyleAlert];

            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"请输入激活码 (例如: VIP888)";
                textField.secureTextEntry = NO;
                textField.textAlignment = NSTextAlignmentCenter;
            }];

            // === 验证按钮逻辑 ===
            UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"立即验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                UITextField *codeField = alert.textFields.firstObject;
                NSString *inputCode = codeField.text;

                if (inputCode.length == 0) {
                    // 没输入就点验证，直接自杀重启
                    exit(0); 
                }

                // 发起网络请求
                NSURL *url = [NSURL URLWithString:VERIFY_URL];
                NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                    
                    BOOL success = NO;

                    if (!error && data) {
                        NSError *jsonError;
                        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                        
                        // 核心逻辑：检查 JSON 里是否包含这个 Key
                        if (json && !jsonError) {
                            if (json[inputCode]) {
                                success = YES;
                            }
                        }
                    }

                    // 回到主线程处理结果
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (success) {
                            // --- 验证成功 ---
                            [defaults setBool:YES forKey:PREFS_STATUS];
                            [defaults setObject:inputCode forKey:PREFS_KEY];
                            [defaults synchronize];
                            
                            UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"🎉 验证成功"
                                                                                                  message:@"欢迎使用，即将进入"
                                                                                           preferredStyle:UIAlertControllerStyleAlert];
                            [successAlert addAction:[UIAlertAction actionWithTitle:@"进入" style:UIAlertActionStyleDefault handler:nil]];
                            [TopMostViewController() presentViewController:successAlert animated:YES completion:nil];
                            
                        } else {
                            // --- 验证失败 ---
                            // 不保存任何状态，直接自杀。
                            // 微信重启后，因为 PREFS_STATUS 还是 NO，所以会再次弹窗。
                            exit(0); 
                        }
                    });
                }];
                [task resume];
            }];

            [alert addAction:confirmAction];
            
            // 让弹窗无法通过点击背景关闭
            alert.modalPresentationStyle = UIModalPresentationOverFullScreen; 
            
            // 显示弹窗
            [TopMostViewController() presentViewController:alert animated:YES completion:nil];
        });
    }

    return result;
}

%end
