#import <UIKit/UIKit.h>
#include <dlfcn.h> // 用于 exit(0)

// === 配置区域 ===
// 确认无误！就是我们要对接的 verify.php
#define VERIFY_API_URL @"https://vonekeji.cn/verify.php"

#define PREFS_KEY   @"vone_activation_code"
#define PREFS_STATUS @"vone_is_activated"

// 声明我们要Hook的微信主类
@interface MicroMessengerAppDelegate : UIResponder <UIApplicationDelegate>
@end

// --- 辅助函数：获取当前最顶层的控制器 ---
UIViewController *TopMostViewController() {
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    // 兼容 iOS 13+ 的多 Scene 架构
    if (@available(iOS 13.0, *)) {
        NSSet<UIWindowScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
        for (UIWindowScene *scene in scenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                window = scene.windows.firstObject;
                break;
            }
        }
    }
    
    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    return rootVC;
}

%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isActivated = [defaults boolForKey:PREFS_STATUS];

    if (!isActivated) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Vone Verify 授权验证"
                                                                           message:@"检测到您尚未激活，请输入正确的激活码。\n⚠️ 输入错误将导致应用重启"
                                                                    preferredStyle:UIAlertControllerStyleAlert];

            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"请输入激活码 (例如: VIP888)";
                textField.secureTextEntry = NO;
                textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters; // 自动大写，方便输入
                textField.clearButtonMode = UITextFieldViewModeWhileEditing;
            }];

            UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"立即验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                UITextField *codeField = alert.textFields.firstObject;
                NSString *inputCode = [codeField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

                if (inputCode.length == 0) {
                    exit(0); // 没输就重启
                    return;
                }

                // --- 开始网络验证 ---
                NSURL *url = [NSURL URLWithString:VERIFY_API_URL];
                NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
                [request setHTTPMethod:@"POST"];
                
                // 构造 POST 数据
                // 注意：这里假设 verify.php 接收的参数名是 'code'
                // 如果你的 PHP 里写的是 $_POST['key']，那这里就要改成 key=%@
                NSString *postString = [NSString stringWithFormat:@"code=%@", inputCode];
                [request setHTTPBody:[postString dataUsingEncoding:NSUTF8StringEncoding]];
                [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

                // 打印调试信息
                NSLog(@"[VoneVerify] 正在向 %@ 发送请求，参数: %@", VERIFY_API_URL, postString);

                NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                    BOOL success = NO;
                    NSString *failReason = @"网络请求失败";

                    if (error) {
                        failReason = error.localizedDescription;
                        NSLog(@"[VoneVerify] 网络错误: %@", failReason);
                    } else {
                        // 尝试将返回数据转为字符串（方便看看到底返回了啥）
                        NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                        NSLog(@"[VoneVerify] 服务器原始返回: %@", responseString);

                        // 尝试解析 JSON
                        NSError *jsonError;
                        id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

                        if (jsonObject) {
                            // 如果是字典格式 {"code": 1, "msg": "ok"}
                            if ([jsonObject isKindOfClass:[NSDictionary class]]) {
                                NSDictionary *json = (NSDictionary *)jsonObject;
                                // 常见的成功判断：code=1 或 status=success
                                if ([json[@"code"] intValue] == 1 || [[json[@"status"] lowercaseString] isEqualToString:@"success"]) {
                                    success = YES;
                                } else {
                                    failReason = json[@"msg"] ?: @"验证失败";
                                }
                            } 
                            // 如果是数组或者其他格式，按需处理
                        } else {
                            // 如果不是 JSON，可能是直接返回的字符串 "success" 或 "ok"
                            if ([responseString.lowercaseString containsString:@"success"] || 
                                [responseString.lowercaseString containsString:@"ok"] || 
                                [responseString.lowercaseString containsString:@"验证成功"]) {
                                success = YES;
                            } else {
                                failReason = responseString ?: @"服务器返回未知数据";
                            }
                        }
                    }

                    // 回到主线程处理 UI
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (success) {
                            // === 验证成功 ===
                            [defaults setBool:YES forKey:PREFS_STATUS];
                            [defaults setObject:inputCode forKey:PREFS_KEY];
                            [defaults synchronize];
                            NSLog(@"[VoneVerify] 激活成功，已保存状态。");

                            UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"验证成功"
                                                                                                  message:@"欢迎使用 Vone Verify！"
                                                                                           preferredStyle:UIAlertControllerStyleAlert];
                            [successAlert addAction:[UIAlertAction actionWithTitle:@"进入应用" style:UIAlertActionStyleDefault handler:nil]];
                            [TopMostViewController() presentViewController:successAlert animated:YES completion:nil];
                        } else {
                            // === 验证失败 ===
                            NSLog(@"[VoneVerify] 验证失败: %@", failReason);
                            UIAlertController *failAlert = [UIAlertController alertControllerWithTitle:@"验证失败"
                                                                                               message:[NSString stringWithFormat:@"%@\n即将重启应用...", failReason]
                                                                                        preferredStyle:UIAlertControllerStyleAlert];
                            [failAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                                exit(0);
                            }]];
                            [TopMostViewController() presentViewController:failAlert animated:YES completion:nil];
                        }
                    });
                }];
                [task resume];
            }];

            [alert addAction:confirmAction];
            [TopMostViewController() presentViewController:alert animated:YES completion:nil];
        });
    }

    return YES;
}

%end
