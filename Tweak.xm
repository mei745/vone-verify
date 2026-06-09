#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// === 配置区域 ===
#define VERIFY_URL @"https://vonekeji.cn/codes.json" // 你的验证地址
#define PREFS_KEY @"vone_activation_code"            // 存储激活码的Key
#define PREFS_STATUS @"vone_is_activated"            // 存储是否已激活的Key (YES/NO)

// === 核心逻辑：强制弹窗函数 (定义为全局函数以避免编译报错) ===
static void ShowForceVerifyAlert() {
    // 获取当前最顶层的窗口
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"授权验证"
                                                                   message:@"请输入激活码"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"请输入您的12位激活码";
        textField.secureTextEntry = NO;
    }];

    // “验证”按钮的逻辑
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *codeField = alert.textFields.firstObject;
        NSString *inputCode = codeField.text;

        if (inputCode.length == 0) {
            // 如果没输入，直接再次弹出（死循环）
            ShowForceVerifyAlert();
            return;
        }

        // 开始网络请求验证
        NSURL *url = [NSURL URLWithString:VERIFY_URL];
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            BOOL success = NO;

            if (!error && data) {
                NSError *jsonError;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                if (json && json[inputCode]) {
                    success = YES;
                }
            }

            // 切回主线程处理 UI
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    // --- 成功：保存状态，不再弹窗 ---
                    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                    [defaults setBool:YES forKey:PREFS_STATUS];
                    [defaults setObject:inputCode forKey:PREFS_KEY];
                    [defaults synchronize];

                    UIAlertController *tip = [UIAlertController alertControllerWithTitle:@"验证成功" message:@"欢迎使用！" preferredStyle:UIAlertControllerStyleAlert];
                    [tip addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                    [window.rootViewController presentViewController:tip animated:YES completion:nil];
                } else {
                    // --- 失败：提示错误，并立即再次弹出验证框 ---
                    UIAlertController *tip = [UIAlertController alertControllerWithTitle:@"验证失败" message:@"错误，请检查后再试" preferredStyle:UIAlertControllerStyleAlert];
                    [tip addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                        // 点击“确定”后，立刻重新弹出验证框
                        ShowForceVerifyAlert();
                    }]];
                    [window.rootViewController presentViewController:tip animated:YES completion:nil];
                }
            });
        }];
        [task resume];
    }];

    [alert addAction:confirmAction];

    // 设置样式为覆盖当前上下文（防止背景变黑）
    alert.modalPresentationStyle = UIModalPresentationOverCurrentContext;

    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// === Hook 微信启动流程 ===
%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isActivated = [defaults boolForKey:PREFS_STATUS];

    // 延迟 2 秒执行，确保微信界面加载完毕
    if (!isActivated) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ShowForceVerifyAlert();
        });
    }

    return YES;
}

%end
