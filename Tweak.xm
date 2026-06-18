#import <UIKit/UIKit.h>
#include <dlfcn.h> // 用于 exit(0)

// === 配置区域 ===
#define VERIFY_API_URL @"https://vonekeji.cn/verify.php"
#define PREFS_KEY   @"vone_activation_code"
#define PREFS_STATUS @"vone_is_activated"

// 声明我们要Hook的微信主类
@interface MicroMessengerAppDelegate : UIResponder <UIApplicationDelegate>
@end

// --- 辅助函数：获取当前最顶层的控制器 (已修复 iOS 16.2 SDK 报错) ---
UIViewController *TopMostViewController() {
    UIWindow *window = nil;

    // 兼容 iOS 13+ (SceneDelegate)
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in scenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                // 找到活跃的窗口
                if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                    window = windowScene.windows.firstObject;
                    break;
                }
            }
        }
        // 如果没找到活跃窗口，尝试取第一个窗口
        if (!window && scenes.count > 0) {
             for (UIScene *scene in scenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    window = ((UIWindowScene *)scene).windows.firstObject;
                    break;
                }
            }
        }
    } else {
        // 兼容 iOS 12 及以下
        window = [UIApplication sharedApplication].keyWindow;
    }

    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    return rootVC;
}

%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 1. 先执行微信原本的启动逻辑
    %orig;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isActivated = [defaults boolForKey:PREFS_STATUS];

    // 2. 判断逻辑：如果没有激活，才执行下面的弹窗代码
    if (!isActivated) {
        // 延迟2秒弹出，防止和微信启动动画冲突导致卡顿
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Vone Verify - 必须激活"
                                                                           message:@"请输入激活码以解锁功能\n(不输入将无法使用)"
                                                                    preferredStyle:UIAlertControllerStyleAlert];

            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"例如: VIP88888";
                textField.secureTextEntry = NO;
            }];

            // “验证”按钮点击事件
            UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                UITextField *codeField = alert.textFields.firstObject;
                NSString *inputCode = codeField.text;

                if (inputCode.length > 0) {
                    NSString *codeToCheck = [inputCode copy];

                    // === 发起 POST 网络请求 ===
                    NSURL *url = [NSURL URLWithString:VERIFY_API_URL];
                    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
                    [request setHTTPMethod:@"POST"];

                    // 构造 POST 参数: code=用户输入的码
                    NSString *postString = [NSString stringWithFormat:@"code=%@", codeToCheck];
                    [request setHTTPBody:[postString dataUsingEncoding:NSUTF8StringEncoding]];
                    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

                    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                        BOOL success = NO;
                        NSString *message = @"未知错误";

                        if (error) {
                            message = [NSString stringWithFormat:@"网络错误: %@", error.localizedDescription];
                        } else {
                            // 尝试解析 JSON
                            NSError *jsonError;
                            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

                            if (json && !jsonError) {
                                // 假设服务器返回 {"code": 200, "msg": "success"} 或类似结构
                                // 这里我们做一个宽容的判断：只要包含 "success" 或者 code 字段为 1/200 都算成功
                                id resultCode = json[@"code"];
                                NSString *resultMsg = json[@"msg"] ?: @"";

                                // 简单的判断逻辑，你可以根据你 verify.php 的实际返回值修改
                                if ([resultCode isEqual:@1] || [resultCode isEqual:@200] || [resultMsg.lowercaseString containsString:@"success"]) {
                                    success = YES;
                                    message = @"激活成功！欢迎使用。";

                                    // === 关键：写入“已激活”状态 ===
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        [defaults setBool:YES forKey:PREFS_STATUS];
                                        [defaults setObject:codeToCheck forKey:PREFS_KEY];
                                        [defaults synchronize];
                                    });
                                } else {
                                    message = resultMsg.length > 0 ? resultMsg : @"激活码无效，请重试。";
                                }
                            } else {
                                // 如果不是 JSON，可能是纯文本返回 (比如直接 echo "success")
                                NSString *textResponse = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                if ([textResponse.lowercaseString containsString:@"success"] || [textResponse isEqualToString:@"1"]) {
                                    success = YES;
                                    message = @"激活成功！";
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        [defaults setBool:YES forKey:PREFS_STATUS];
                                        [defaults setObject:codeToCheck forKey:PREFS_KEY];
                                        [defaults synchronize];
                                    });
                                } else {
                                    message = @"服务器响应异常";
                                }
                            }
                        }

                        // 显示结果提示
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (success) {
                                // 成功就消失弹窗，不用重启
                                [[[UIApplication sharedApplication] keyWindow].rootViewController dismissViewControllerAnimated:YES completion:nil];
                            } else {
                                // 失败则弹窗提示，并准备重启
                                UIAlertController *tipAlert = [UIAlertController alertControllerWithTitle:@"验证失败"
                                                                                                  message:[NSString stringWithFormat:@"%@\n即将重启应用...", message]
                                                                                           preferredStyle:UIAlertControllerStyleAlert];
                                [tipAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                                [[[UIApplication sharedApplication] keyWindow].rootViewController presentViewController:tipAlert animated:YES completion:nil];

                                // 延迟 2 秒后强制重启 (exit(0))
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                    exit(0);
                                });
                            }
                        });
                    }];
                    [task resume];
                }
            }];

            [alert addAction:confirmAction];

            // 设置弹窗不可取消
            alert.modalPresentationStyle = UIModalPresentationOverFullScreen; // 修正拼写

            UIViewController *topVC = TopMostViewController();
            if (topVC) {
                [topVC presentViewController:alert animated:YES completion:nil];
            }
        });
    }

    return YES;
}

%end
