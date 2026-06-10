#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// === 配置区域 ===
#define VERIFY_URL @"https://vonekeji.cn/codes.json" // 你的验证地址
#define PREFS_KEY @"voneyz_saved_code"               // 本地存储激活码的Key

// === 核心逻辑：强制弹窗函数 ===
static void ShowForceVerifyAlert() {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window || !window.rootViewController) return;

    // 防止重复弹窗：如果当前已经有弹窗显示，就不要再次创建
    if (window.rootViewController.presentedViewController) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"正版授权验证"
                                                                   message:@"请输入验证激活码以继续使用。"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"请输入您的12位激活码";
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        textField.text = [defaults stringForKey:PREFS_KEY]; // 自动填入旧码
    }];

    UIAlertAction *verifyAction = [UIAlertAction actionWithTitle:@"立即验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *field = alert.textFields.firstObject;
        NSString *inputCode = field.text;

        if (inputCode.length > 0) {
            // === 点击验证后，发起异步网络请求 ===
            NSURLSession *session = [NSURLSession sharedSession];
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?code=%@", VERIFY_URL, inputCode]];

            [[session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                BOOL isSuccess = NO;

                if (!error && data) {
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([json[@"status"] isEqualToString:@"success"]) {
                        isSuccess = YES;
                    }
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    if (isSuccess) {
                        // 1. 验证成功：保存新码
                        [[NSUserDefaults standardUserDefaults] setObject:inputCode forKey:PREFS_KEY];
                        [[NSUserDefaults standardUserDefaults] synchronize];
                        // 2. 关闭弹窗，不再做任何事（用户进入微信）
                        [window.rootViewController dismissViewControllerAnimated:YES completion:nil];
                    } else {
                        // 3. 【关键修改】验证失败：关闭当前弹窗，并立即重新弹出输入框
                        [window.rootViewController dismissViewControllerAnimated:NO completion:^{
                            ShowForceVerifyAlert();
                        }];
                    }
                });
            }] resume];

        } else {
            // 没输入内容，关掉当前弹窗，马上重弹一个空的
            [window.rootViewController dismissViewControllerAnimated:NO completion:^{
                 ShowForceVerifyAlert();
            }];
        }
    }];

    [alert addAction:verifyAction];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// === 辅助函数：启动时的静默验证 ===
static void CheckActivationOnLaunch() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedCode = [defaults stringForKey:PREFS_KEY];

    // 情况 A：从来没输过码 -> 直接弹窗
    if (!savedCode || savedCode.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ShowForceVerifyAlert();
        });
        return;
    }

    // 情况 B：有码，去服务器查一下是否还有效
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?code=%@", VERIFY_URL, savedCode]];

    // 使用 NSURLSession 进行异步请求，绝对不会卡死微信启动
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        BOOL isValid = NO;

        if (!error && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json[@"status"] isEqualToString:@"success"]) {
                isValid = YES;
            }
        }

        // 回到主线程处理 UI
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!isValid) {
                // 服务器说无效，或者断网了 -> 弹窗拦截
                ShowForceVerifyAlert();
            }
            // 如果 isValid 为 YES，什么都不做，微信正常显示
        });

    }] resume];
}

%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig; // 先执行微信原本的启动逻辑

    // 延迟 1 秒执行检查。确保微信的主窗口已经初始化完毕
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CheckActivationOnLaunch();
    });

    return YES;
}

%end
