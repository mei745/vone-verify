#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// === 配置区域 ===
#define VERIFY_URL @"https://vonekeji.cn/codes.json" // 你的验证地址
#define PREFS_KEY @"voneyz_saved_code"               // 本地存储激活码的Key

// === 核心逻辑：强制弹窗函数 (全局函数) ===
static void ShowForceVerifyAlert() {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window || !window.rootViewController) return;

    // 防止重复弹窗：如果当前已经有弹窗了，就不再弹
    if (window.rootViewController.presentedViewController) return;

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

    UIAlertAction *verifyAction = [UIAlertAction actionWithTitle:@"立即验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *field = alert.textFields.firstObject;
        NSString *inputCode = field.text;

        if (inputCode.length > 0) {
            // === 修改点：使用异步请求，不卡死界面 ===
            NSURLSession *session = [NSURLSession sharedSession];
            // 注意：这里为了演示，假设你的服务器返回 {"status": "success"}
            // 如果你的服务器需要 POST，请自行修改 request
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?code=%@", VERIFY_URL, inputCode]];
            NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                BOOL isSuccess = NO;
                if (!error && data) {
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([json[@"status"] isEqualToString:@"success"]) {
                        isSuccess = YES;
                    }
                }

                // 回到主线程处理 UI
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (isSuccess) {
                        // 1. 验证成功：保存新码
                        [[NSUserDefaults standardUserDefaults] setObject:inputCode forKey:PREFS_KEY];
                        [[NSUserDefaults standardUserDefaults] synchronize];

                        // 2. 验证成功：关闭弹窗，不再弹出
                        [window.rootViewController dismissViewControllerAnimated:YES completion:nil];
                    } else {
                        // 3. 验证失败：提示用户，并再次弹窗
                        UIAlertController *failAlert = [UIAlertController alertControllerWithTitle:@"验证失败" message:@"激活码无效或网络错误" preferredStyle:UIAlertControllerStyleAlert];
                        [failAlert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:nil]];
                        [window.rootViewController presentViewController:failAlert animated:YES completion:^{
                            // 等用户看完失败提示后，再弹出输入框
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                [window.rootViewController dismissViewControllerAnimated:YES completion:^{
                                    ShowForceVerifyAlert(); // 重新弹出输入框
                                }];
                            });
                        }];
                    }
                });
            }];
            [task resume];

        } else {
            // 没输入内容，直接重弹
            [window.rootViewController dismissViewControllerAnimated:YES completion:^{
                 ShowForceVerifyAlert();
            }];
        }
    }];

    [alert addAction:verifyAction];
    alert.view.tintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];

    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// === 辅助函数：启动时的检查 (改为异步，防止卡死) ===
static void CheckActivationOnLaunch() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedCode = [defaults stringForKey:PREFS_KEY];

    if (!savedCode || savedCode.length == 0) {
        // 从来没输入过，直接弹窗
        dispatch_async(dispatch_get_main_queue(), ^{
             ShowForceVerifyAlert();
        });
        return;
    }

    // === 修改点：有码也要去服务器查一下，但是用异步 ===
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

        // 如果无效，回到主线程弹窗
        if (!isValid) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ShowForceVerifyAlert();
            });
        }
        // 如果有效，什么都不做，让用户正常使用
    }];
    [task resume];
}

%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    // === 修改点：延迟 1 秒执行检查 ===
    // 必须等微信的主界面（RootVC）加载出来，否则弹窗会因为找不到 Window 而失败
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CheckActivationOnLaunch();
    });

    return YES;
}

%end
