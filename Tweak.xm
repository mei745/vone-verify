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
                                                                   message:@"系统检测到环境变化或授权失效，请重新验证激活码以继续使用。"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"请输入您的激活码";
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        textField.text = [defaults stringForKey:PREFS_KEY]; // 自动填入旧码
    }];

    UIAlertAction *verifyAction = [UIAlertAction actionWithTitle:@"立即验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *field = alert.textFields.firstObject;
        NSString *inputCode = field.text;

        if (inputCode.length > 0) {
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
                        // 【条件2】验证成功：保存新码，并弹出欢迎提示框
                        [[NSUserDefaults standardUserDefaults] setObject:inputCode forKey:PREFS_KEY];
                        [[NSUserDefaults standardUserDefaults] synchronize];
                        
                        UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"验证成功"
                                                                                              message:@"欢迎使用！"
                                                                                       preferredStyle:UIAlertControllerStyleAlert];
                        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                            // 点击确定后，彻底关闭拦截界面，用户进入微信
                            [window.rootViewController dismissViewControllerAnimated:YES completion:nil];
                        }];
                        [successAlert addAction:okAction];
                        [window.rootViewController presentViewController:successAlert animated:YES completion:nil];
                        
                    } else {
                        // 【条件1】验证失败：不弹任何提示，瞬间关掉当前输入框，立刻重弹一个新的
                        [window.rootViewController dismissViewControllerAnimated:NO completion:^{
                            ShowForceVerifyAlert();
                        }];
                    }
                });
            }] resume];

        } else {
            // 没输入内容，同样关掉重弹
            [window.rootViewController dismissViewControllerAnimated:NO completion:^{
                 ShowForceVerifyAlert();
            }];
        }
    }];

    [alert addAction:verifyAction];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// === 辅助函数：启动时的强制联网验证 ===
static void CheckActivationOnLaunch() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedCode = [defaults stringForKey:PREFS_KEY];

    // 如果没有本地缓存的激活码，直接弹窗要求输入
    if (!savedCode || savedCode.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ShowForceVerifyAlert();
        });
        return;
    }

    // 【条件3】有本地缓存也必须去服务器查询最新状态（支持后期注销/停用）
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?code=%@", VERIFY_URL, savedCode]];

    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        BOOL isValid = NO;

        if (!error && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json[@"status"] isEqualToString:@"success"]) {
                isValid = YES;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!isValid) {
                // 服务器返回无效、被注销/停用，或者断网无法验证 -> 强制弹窗拦截
                ShowForceVerifyAlert();
            }
            // 如果 isValid 为 YES，什么都不做，微信正常显示主界面
        });

    }] resume];
}

%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig; 

    // 延迟 1 秒执行检查，确保微信的主窗口已经初始化完毕
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CheckActivationOnLaunch();
    });

    return YES;
}

%end
