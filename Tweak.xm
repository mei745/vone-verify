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
            // === 关键修改：点击验证时，再次发起同步网络检查 ===
            // 这里为了演示逻辑清晰，复用了下面的 checkAndProceed 逻辑
            // 但为了用户体验，我们通常希望点击按钮后有 loading，这里简化处理，直接再次校验

            NSURLSession *session = [NSURLSession sharedSession];
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?code=%@", VERIFY_URL, inputCode]];
            NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (!error && data) {
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    // 假设服务器返回 {"status": "success"} 代表有效
                    if ([json[@"status"] isEqualToString:@"success"]) {
                        // 验证通过，保存新码（以防用户换了新码）
                        [[NSUserDefaults standardUserDefaults] setObject:inputCode forKey:PREFS_KEY];
                        [[NSUserDefaults standardUserDefaults] synchronize];
                        // 验证成功，什么都不做，窗口消失，正常使用
                        dispatch_async(dispatch_get_main_queue(), ^{
                             [window.rootViewController dismissViewControllerAnimated:YES completion:nil];
                        });
                        return;
                    }
                }

                // 如果走到这里，说明验证失败（网络错误或服务器返回失败）
                dispatch_async(dispatch_get_main_queue(), ^{
                    // 验证失败，递归调用，再次弹出窗口
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

    if (!savedCode || savedCode.length == 0) {
        // 从来没输入过，直接弹窗
        ShowForceVerifyAlert();
        return;
    }

    // === 关键逻辑：有码，也要去服务器查一下是否被停用 ===
    // 注意：这里使用同步请求是为了阻塞启动，防止用户看到主界面一瞬间
    // 在生产环境中，建议加一个 Loading 遮罩层，体验更好
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
        // 服务器说这个码无效（可能被你停用了），弹窗让用户重新输
        dispatch_async(dispatch_get_main_queue(), ^{
            ShowForceVerifyAlert();
        });
    }
    // 如果 isValid 为 YES，什么都不做，微信正常启动
}

%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    // 在主线程异步执行检查，避免卡死 SpringBoard 导致看门狗重启，
    // 但因为是同步网络请求，微信界面会稍微晚一点点出来，这是为了安全必须的代价
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CheckActivationOnLaunch();
    });

    return YES;
}

%end
