#import <UIKit/UIKit.h>
#include <dlfcn.h> // 用于 exit(0)

// === 配置区域 ===
#define VERIFY_API_URL @"https://vonekeji.cn/verify.php"
#define PREFS_KEY   @"vone_activation_code"
#define PREFS_STATUS @"vone_is_activated"

// 声明我们要Hook的微信主类
@interface MicroMessengerAppDelegate : UIResponder <UIApplicationDelegate>
@end

// --- 辅助函数：获取当前最顶层的控制器 ---
UIViewController *TopMostViewController() {
    UIWindow *window = nil;

    // 兼容 iOS 13+ (SceneDelegate)
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in scenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *w in windowScene.windows) {
                    if (w.isKeyWindow) {
                        window = w;
                        break;
                    }
                }
            }
        }
    } else {
        // 兼容旧版 iOS
        window = [UIApplication sharedApplication].keyWindow;
    }

    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}

// --- 核心逻辑：显示激活弹窗 ---
void ShowActivationAlert() {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔒 Vone Verify 授权验证"
                                                                   message:@"检测到您尚未激活，请输入正确的激活码。\n⚠️ 输入错误将导致应用重启"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    // 添加输入框
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"请输入激活码 (例如: VIP888)";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone; // 禁用首字母大写
    }];

    // 添加验证按钮
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"立即验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        // 1. 获取输入框的内容
        UITextField *inputField = alert.textFields.firstObject;
        NSString *code = inputField.text;

        // 2. 【关键修改】检查是否为空或纯空格
        if (code.length == 0 || [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0) {
            // 如果为空，弹出一个小提示，并且因为这里没有执行 dismiss，原窗口不会消失
            UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"提示" message:@"激活码不能为空！" preferredStyle:UIAlertControllerStyleAlert];
            [emptyAlert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleCancel handler:nil]];
            [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:emptyAlert animated:YES completion:nil];
            return; // 直接返回，不执行下面的网络请求
        }

        // 3. 开始网络验证
        NSURL *url = [NSURL URLWithString:VERIFY_API_URL];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";

        // 构建 POST 参数 (假设后端接收 code=xxx)
        NSString *postBody = [NSString stringWithFormat:@"code=%@", code];
        request.HTTPBody = [postBody dataUsingEncoding:NSUTF8StringEncoding];

        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    NSLog(@"[VoneVerify] Network Error: %@", error.localizedDescription);
                    // 网络错误也视为验证失败，可以选择不弹窗直接重启，或者提示网络错误
                    UIAlertView *failAlert = [[UIAlertView alloc] initWithTitle:@"网络错误" message:@"无法连接服务器，请检查网络" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
                    [failAlert show];
                    // 网络错误通常不建议直接杀进程，给用户重试机会
                    return;
                }

                NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[VoneVerify] Server Response: %@", result);

                // 简单的成功判断：包含 success 或者 code:1 (根据你的PHP返回值调整)
                BOOL isSuccess = [result containsString:@"success"] || [result containsString:@"\"code\":1"];

                if (isSuccess) {
                    // === 验证成功 ===
                    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                    [defaults setObject:code forKey:PREFS_KEY];
                    [defaults setBool:YES forKey:PREFS_STATUS];
                    [defaults synchronize];

                    UIAlertView *successAlert = [[UIAlertView alloc] initWithTitle:@"🎉 激活成功" message:@"感谢您的支持！" delegate:nil cancelButtonTitle:@"进入应用" otherButtonTitles:nil];
                    [successAlert show];
                } else {
                    // === 验证失败 ===
                    UIAlertView *failAlert = [[UIAlertView alloc] initWithTitle:@"❌ 验证失败" message:@"激活码无效或已过期\n应用即将重启" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
                    [failAlert show];

                    // 延迟 2 秒后强制重启应用
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        exit(0);
                    });
                }
            });
        }] resume];
    }];

    [alert addAction:confirmAction];

    // 设置弹窗样式，防止被底部遮挡
    alert.modalPresentationStyle = UIModalPresentationOverFullScreen;

    // 获取最顶层控制器并弹出
    UIViewController *topVC = TopMostViewController();
    if (topVC) {
        [topVC presentViewController:alert animated:YES completion:nil];
    }
}

// --- Hook 入口 ---
%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isActivated = [defaults boolForKey:PREFS_STATUS];

    // 如果没有激活，就弹窗
    if (!isActivated) {
        // 稍微延迟一点弹出，确保 UI 已经加载完毕
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ShowActivationAlert();
        });
    }

    return YES;
}

%end
