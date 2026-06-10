#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// === 配置区域 ===
#define VERIFY_URL @"https://vonekeji.cn/codes.json" // 你的验证地址
#define PREFS_KEY @"voneyz_saved_code"               // 本地存储激活码的Key

// === 核心逻辑：强制弹窗函数 ===
static void ShowForceVerifyAlert() {
    // 1. 获取 KeyWindow
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) {
        // 如果没有 keyWindow，尝试获取最顶层的 Window
        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *win in windows) {
            if (win.visible && win.windowLevel == UIWindowLevelNormal) {
                window = win;
                break;
            }
        }
    }
    if (!window) return;

    // 2. 防止重复弹窗 (关键修复)
    UIViewController *rootVC = window.rootViewController;
    // 如果已经有弹窗了，不要重复弹
    if (rootVC.presentedViewController) {
        // 如果已经有弹窗，直接返回，或者尝试 dismiss 掉再弹（这里选择直接返回，防止闪烁）
        return;
    }

    // 3. 创建弹窗
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"正版授权验证"
                                                                   message:@"系统检测到环境变化，请重新验证激活码以继续使用。"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"请输入您的激活码";
        textField.secureTextEntry = NO;
        // 自动填入上次保存的码
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        textField.text = [defaults stringForKey:PREFS_KEY];
    }];

    UIAlertAction *verifyAction = [UIAlertAction actionWithTitle:@"立即验证" style:UIAlertActionStyleDefault handler:nil]; // 先不设置 handler，后面统一处理

    [alert addAction:verifyAction];
    alert.view.tintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];

    // 4. 显示弹窗
    [rootVC presentViewController:alert animated:YES completion:nil];

    // 5. 手动处理“立即验证”的点击逻辑 (为了支持异步网络请求)
    // 给“立即验证”按钮添加点击监听
    [alert addAction:[UIAlertAction actionWithTitle:@" " style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *field = alert.textFields.firstObject;
        NSString *inputCode = field.text;

        if (inputCode.length == 0) {
            // 没输入，重弹
            [alert dismissViewControllerAnimated:NO completion:^{
                ShowForceVerifyForce(); // 强制重弹
            }];
            return;
        }

        // 保存输入的码
        [[NSUserDefaults standardUserDefaults] setObject:inputCode forKey:PREFS_KEY];
        [[NSUserDefaults standardUserDefaults] synchronize];

        // --- 开始异步验证 ---
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?code=%@", VERIFY_URL, inputCode]];
        NSURLSession *session = [NSURLSession sharedSession];
        NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            BOOL isValid = NO;
            if (!error && data) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if ([json[@"status"] isEqualToString:@"success"]) {
                    isValid = YES;
                }
            }

            // 回到主线程处理 UI
            dispatch_async(dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:NO completion:nil];
                if (!isValid) {
                    // 验证失败，强制重弹
                    ShowForceVerifyForce();
                }
                // 验证成功，什么都不做，窗口消失，正常使用
            });
        }];
        [task resume];
    }]];
}

// 强制重弹函数 (用于绕过防重复弹窗逻辑)
static void ShowForceVerifyForce() {
    // 简单粗暴：先尝试 dismiss 掉当前的弹窗，然后再弹
    UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    if (topVC.presentedViewController) {
        [topVC.presentedViewController dismissViewControllerAnimated:NO completion:^{
            ShowForceVerifyAlert();
        }];
    } else {
        ShowForceVerifyAlert();
    }
}

// 全局标记，防止多次触发
static BOOL hasShownAlert = NO;

%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 调用原函数
    BOOL result = %orig;

    // 只有在主线程且确保只执行一次的情况下进行检查
    if (!hasShownAlert) {
        hasShownAlert = YES;

        // 延迟 1.5 秒执行，确保微信界面完全加载出来
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            
            // 1. 检查本地有没有保存的码
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSString *savedCode = [defaults stringForKey:PREFS_KEY];

            // 2. 如果没保存过，直接弹窗
            if (!savedCode || savedCode.length == 0) {
                ShowForceVerifyAlert();
                return;
            }

            // 3. 如果有保存的码，先去服务器验证一下是否被停用 (异步)
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?code=%@", VERIFY_URL, savedCode]];
            NSURLSession *session = [NSURLSession sharedSession];
            NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                BOOL isValid = NO;
                if (!error && data) {
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([json[@"status"] isEqualToString:@"success"]) {
                        isValid = YES;
                    }
                }

                // 回到主线程
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!isValid) {
                        // 服务器说无效（被停用），强制弹窗
                        ShowForceVerifyForce();
                    }
                    // 有效则什么都不做
                });
            });
            [task resume];
        });
    }

    return result;
}

%end
