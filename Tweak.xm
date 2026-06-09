#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// 你的验证地址 (记得先把 codes.json 放到你的网站上)
#define VERIFY_URL @"https://vonekeji.cn/codes.json"
#define PREFS_KEY @"vone_activation_code"
#define PREFS_STATUS @"vone_is_activated"

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isActivated = [defaults boolForKey:PREFS_STATUS];

    // 如果还没激活，延迟2秒弹出窗口（避免桌面启动时卡顿）
    if (!isActivated) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Vone Verify" 
                                                                           message:@"请输入激活码以解锁功能" 
                                                                    preferredStyle:UIAlertControllerStyleAlert];

            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"例如: VIP88888";
                textField.secureTextEntry = NO;
            }];

            UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                UITextField *codeField = alert.textFields.firstObject;
                NSString *inputCode = codeField.text;

                if (inputCode.length > 0) {
                    // 保存当前的输入码，用于 Block 捕获
                    NSString *codeToCheck = [inputCode copy];
                    
                    // 开始网络请求验证 (后台线程执行)
                    NSURL *url = [NSURL URLWithString:VERIFY_URL];
                    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                        BOOL success = NO;
                        NSString *message = @"";
                        
                        if (error) {
                            message = [NSString stringWithFormat:@"网络错误: %@", error.localizedDescription];
                        } else {
                            NSError *jsonError;
                            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                            if (json && !jsonError) {
                                // 检查输入的码是否在字典里
                                if (json[codeToCheck]) {
                                    success = YES;
                                    message = @"激活码有效，功能已解锁！";
                                    
                                    // 执行保存逻辑 (切回主线程保证安全)
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        [defaults setBool:YES forKey:PREFS_STATUS];
                                        [defaults setObject:codeToCheck forKey:PREFS_KEY];
                                        [defaults synchronize];
                                    });
                                } else {
                                    message = @"激活码无效，请重试。";
                                }
                            } else {
                                message = @"服务器数据解析失败";
                            }
                        }
                        
                        // --- 关键：所有 UI 提示必须回到主线程 ---
                        dispatch_async(dispatch_get_main_queue(), ^{
                            UIAlertController *tipAlert = [UIAlertController alertControllerWithTitle:success ? @"成功" : @"失败" 
                                                                                              message:message 
                                                                                       preferredStyle:UIAlertControllerStyleAlert];
                            [tipAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                            [[[UIApplication sharedApplication] keyWindow].rootViewController presentViewController:tipAlert animated:YES completion:nil];
                        });
                    }];
                    [task resume];
                }
            }];

            [alert addAction:confirmAction];
            [[[UIApplication sharedApplication] keyWindow].rootViewController presentViewController:alert animated:YES completion:nil];
        });
    }
}

%end
