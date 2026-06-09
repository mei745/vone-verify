#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// === 配置区域 ===
#define VERIFY_URL @"https://vonekeji.cn/codes.json" // 你的验证地址
#define PREFS_KEY @"vone_activation_code"            // 存储激活码的Key
#define PREFS_STATUS @"vone_is_activated"            // 存储是否已激活的Key (YES/NO)

// 声明我们要Hook的微信主类
@interface MicroMessengerAppDelegate : UIResponder <UIApplicationDelegate>
@end

%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isActivated = [defaults boolForKey:PREFS_STATUS];

    // 只有在未激活状态下才执行检查
    if (!isActivated) {
        // 延迟0.5秒弹出，确保微信界面已经加载完毕，避免崩溃
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showForceVerifyAlert];
        });
    }

    return YES;
}

%new
- (void)showForceVerifyAlert {
    // --- 强制验证弹窗逻辑 ---
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"授权验证"
                                                                   message:@"请输入激活码"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    // 添加输入框
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"请输入12位激活码";
        textField.secureTextEntry = NO;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];

    // “验证”按钮逻辑
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *codeField = alert.textFields.firstObject;
        NSString *inputCode = codeField.text;

        if (inputCode.length > 0) {
            // 开始网络请求验证
            NSURL *url = [NSURL URLWithString:VERIFY_URL];
            NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                BOOL success = NO;

                if (!error && data) {
                    NSError *jsonError;
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                    // 假设 codes.json 格式为 {"VIP888": true} 或 {"VIP888": "some value"}
                    // 只要 key 存在即视为有效
                    if (json && json[inputCode]) {
                        success = YES;
                    }
                }

                // 处理结果（必须回到主线程操作UI）
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (success) {
                        // === 验证成功 ===
                        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                        [defaults setBool:YES forKey:PREFS_STATUS];
                        [defaults setObject:inputCode forKey:PREFS_KEY];
                        [defaults synchronize];

                        // 提示成功，窗口会自动关闭
                        UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"激活成功"
                                                                                              message:@"欢迎使用！"
                                                                                       preferredStyle:UIAlertControllerStyleAlert];
                        [successAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                        [[[UIApplication sharedApplication] keyWindow].rootViewController presentViewController:successAlert animated:YES completion:nil];

                    } else {
                        // === 验证失败 ===
                        // 提示错误
                        UIAlertController *failAlert = [UIAlertController alertControllerWithTitle:@"验证失败"
                                                                                           message:@"激活码无效，请重新输入。"
                                                                                    preferredStyle:UIAlertControllerStyleAlert];

                        // 【关键】在错误提示点击“确定”后，立即再次弹出验证窗口
                        [failAlert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                            [self showForceVerifyAlert]; // 递归调用，实现无限循环
                        }]];

                        [[[UIApplication sharedApplication] keyWindow].rootViewController presentViewController:failAlert animated:YES completion:nil];
                    }
                });
            }];
            [task resume];
        } else {
            // 如果没输入内容直接点验证，也提示并重试
             UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"提示"
                                                                                message:@"请输入激活码。"
                                                                         preferredStyle:UIAlertControllerStyleAlert];
            [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self showForceVerifyAlert];
            }]];
            [[[UIApplication sharedApplication] keyWindow].rootViewController presentViewController:emptyAlert animated:YES completion:nil];
        }
    }];

    [alert addAction:confirmAction];

    // 设置样式，使其覆盖在最上层
    alert.modalPresentationStyle = UIModalPresentationOverCurrentContext;

    // 显示窗口
    [[[UIApplication sharedApplication] keyWindow].rootViewController presentViewController:alert animated:YES completion:nil];
}

%end
