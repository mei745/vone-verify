#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// === 配置区域 ===
#define VERIFY_URL @"https://vonekeji.cn/codes.json" // 你的验证地址
#define PREFS_KEY @"voneyz_saved_code"               // 本地存储激活码的Key

// === 核心逻辑：强制弹窗函数 (全局函数) ===
static void ShowForceVerifyAlert() {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;

    // 如果已经有弹窗了，不要重复弹
    if (window.rootViewController.presentedViewController) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"正版授权验证"
                                                                   message:@"系统检测到环境变化，请重新验证激活码以继续使用。"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"请输入您的激活码";
        textField.secureTextEntry = NO;
        // 自动填入上次保存的码，方便用户
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        textField.text = [defaults stringForKey:PREFS_KEY];
    }];

    UIAlertAction *verifyAction = [UIAlertAction actionWithTitle:@"立即验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *field = alert.textFields.firstObject;
        NSString *inputCode = field.text;

        if (inputCode.length > 0) {
            // === 关键修改：点击验证时，再次发起网络检查 ===
            NSURLSession *session = [NSURLSession sharedSession];
            // 注意：这里用 GET 请求演示，实际根据你的后端接口调整
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?code=%@", VERIFY_URL, inputCode]];
            NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (!error && data) {
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    // 假设服务器返回 {"status": "success"} 代表有效
                    if ([json[@"status"] isEqualToString:@"success"]) {
                        // 验证通过，保存新码
                        [[NSUserDefaults standardUserDefaults] setObject:inputCode forKey:PREFS_KEY];
                        [[NSUserDefaults standardUserDefaults] synchronize];
                        // 验证成功，关闭弹窗
                        dispatch_async(dispatch_get_main_queue(), ^{
                             [window.rootViewController dismissViewControllerAnimated:YES completion:nil];
                        });
                        return;
                    }
                }

                // 如果走到这里，说明验证失败（网络错误或服务器返回失败）
                dispatch_async(dispatch_get_main_queue(), ^{
                    // 验证失败，递归调用，再次弹出窗口（或者你可以改成显示一个 Alert 提示错误）
                    ShowForceVerifyAlert();
                });
            }];
            [task resume];

        } else {
            // 没输入，直接重弹
            ShowForceVerifyAlert();
        }
    }];

    [alert addAction:verifyAction];
    alert.view.tintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];

    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// === 辅助函数：启动时的静默验证 ===
static void CheckActivationOnLaunch() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedCode = [defaults stringForKey:PREFS_KEY];

    // 如果没有保存过码，直接弹窗
    if (!savedCode || savedCode.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ShowForceVerifyAlert();
        });
        return;
    }

    // === 关键逻辑：有码，也要去服务器查一下是否被停用 ===
    // 使用同步请求阻塞一下，防止用户看到主界面一瞬间（虽然体验稍差，但为了安全）
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?code=%@", VERIFY_URL, savedCode]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];

    BOOL isValid = NO;

    if (!error && data) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json[@"status"] isEqualToString:@"success"]) {
            isValid = YES;
        }
    }

    if (!isValid) {
        // 服务器说这个码无效，弹窗让用户重新输
        dispatch_async(dispatch_get_main_queue(), ^{
            ShowForceVerifyAlert();
        });
    }
    // 如果 isValid 为 YES，什么都不做，微信正常启动
}

%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    // 延迟 0.5 秒执行检查，确保 window 已经创建好，避免空指针崩溃
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CheckActivationOnLaunch();
    });

    return YES;
}

%end
