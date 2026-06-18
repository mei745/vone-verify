#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// --- 配置区 ---
#define SERVER_URL @"https://vonekeji.cn/verify.php" // 你的服务器地址
#define PLUGIN_NAME @"VoneVerify"

%hook SpringBoard // 如果是针对特定App，这里改成 %hook AppDelegate 或对应的类

- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig;

    // 1. 检查是否已经验证过 (防止每次打开都弹)
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"Vone_Is_Activated"]) {
        return; // 已激活，直接放行
    }

    // 2. 创建弹窗
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"需要验证"
                                                                   message:@"请输入激活码以使用本功能"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    // 3. 添加输入框
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"输入激活码";
        textField.secureTextEntry = NO; // 如果不想显示明文，改为 YES
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    // 4. 定义验证逻辑 (Block)
    void (^verifyAction)(UIAlertAction *) = ^(UIAlertAction *action) {
        UITextField *inputField = alert.textFields.firstObject;
        NSString *code = inputField.text;

        if (code.length == 0) {
            // 没输东西，弹窗会消失，然后 App 会因为下面的 crash 逻辑重启，再次弹窗
            return;
        }

        // --- 开始网络请求 ---
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *urlString = [NSString stringWithFormat:@"%@?code=%@", SERVER_URL, code];
            NSURL *url = [NSURL URLWithString:urlString];
            NSData *data = [NSData dataWithContentsOfURL:url]; // 简单的 GET 请求

            dispatch_async(dispatch_get_main_queue(), ^{
                if (data) {
                    NSError *error = nil;
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

                    // 假设服务器返回 {"status": 1} 代表成功
                    if (!error && [json[@"status"] intValue] == 1) {
                        // 验证成功
                        [defaults setBool:YES forKey:@"Vone_Is_Activated"];
                        [defaults synchronize];
                        NSLog(@"[VoneVerify] 激活成功！");
                    } else {
                        // 验证失败，再次弹出 Alert
                        UIAlertController *failAlert = [UIAlertController alertControllerWithTitle:@"错误"
                                                                                           message:@"激活码无效，请重试"
                                                                                    preferredStyle:UIAlertControllerStyleAlert];
                        [failAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                        // 获取当前顶层控制器来展示弹窗 (简单粗暴法)
                        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:failAlert animated:YES completion:nil];
                    }
                } else {
                     // 网络错误处理
                     UIAlertController *netAlert = [UIAlertController alertControllerWithTitle:@"网络错误"
                                                                                         message:@"无法连接服务器"
                                                                                      preferredStyle:UIAlertControllerStyleAlert];
                     [netAlert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:nil]];
                     [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:netAlert animated:YES completion:nil];
                }
            });
        });
    };

    // 5. 添加按钮
    [alert addAction:[UIAlertAction actionWithTitle:@"验证" style:UIAlertActionStyleDefault handler:verifyAction]];

    // 6. 强制展示 (使用 keyWindow 确保在最上层)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

%end
