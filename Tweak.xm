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

    // 如果还没激活，弹出窗口
    if (!isActivated) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Vone Verify" message:@"请输入激活码以解锁功能" preferredStyle:UIAlertControllerStyleAlert];

            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"例如: VIP88888";
                textField.secureTextEntry = NO;
            }];

            UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                UITextField *codeField = alert.textFields.firstObject;
                NSString *inputCode = codeField.text;

                if (inputCode.length > 0) {
                    // 开始网络请求验证
                    NSURL *url = [NSURL URLWithString:VERIFY_URL];
                    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                        if (error) {
                            NSLog(@"[Vone] 网络错误: %@", error.localizedDescription);
                            return;
                        }

                        NSError *jsonError;
                        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

                        if (json && !jsonError) {
                            // 检查输入的码是否在字典里
                            if (json[inputCode]) {
                                // 激活成功！
                                [defaults setBool:YES forKey:PREFS_STATUS];
                                [defaults setObject:inputCode forKey:PREFS_KEY];
                                [defaults synchronize];

                                dispatch_async(dispatch_get_main_queue(), ^{
                                    UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"成功" message:@"激活码有效，功能已解锁！" preferredStyle:UIAlertControllerStyleAlert];
                                    [successAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                                    [[[UIApplication sharedApplication] keyWindow].rootViewController presentViewController:successAlert animated:YES completion:nil];
                                });
                            } else {
                                // 激活失败
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    UIAlertController *failAlert = [UIAlertController alertControllerWithTitle:@"失败" message:@"激活码无效，请重试。" preferredStyle:UIAlertControllerStyleAlert];
                                    [failAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                                    [[[UIApplication sharedApplication] keyWindow].rootViewController presentViewController:failAlert animated:YES completion:nil];
                                });
                            }
                        }
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
