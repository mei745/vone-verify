#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// 你的验证地址 (记得先把 codes.json 放到你的网站上)
#define VERIFY_URL @"https://vonekeji.cn/codes.json"
#define PREFS_KEY @"vone_activation_code"
#define PREFS_STATUS @"vone_is_activated"

// === 修改点 1：Hook 微信的 AppDelegate 类 ===
// 微信的主代理类名通常比较固定，使用这个类名能确保在微信启动时触发
@interface MicroMessengerAppDelegate : UIResponder <UIApplicationDelegate>
@end

%hook MicroMessengerAppDelegate

// === 修改点 2：重写启动方法 ===
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 1. 调用原始方法，确保微信能正常启动
    BOOL result = %orig;

    // 2. 获取用户默认设置
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isActivated = [defaults boolForKey:PREFS_STATUS];

    // 3. 如果未激活，延迟弹窗
    if (!isActivated) {
        // 使用 dispatch_after 避免阻塞启动
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            
            // 创建UIAlertController
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Vone Verify" 
                                                                           message:@"请输入激活码以解锁功能" 
                                                                    preferredStyle:UIAlertControllerStyleAlert];

            // 添加文本输入框
            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"例如: VIP88888";
                textField.secureTextEntry = NO;
            }];

            // 添加确认按钮
            UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                UITextField *codeField = alert.textFields.firstObject;
                NSString *inputCode = codeField.text;

                if (inputCode.length > 0) {
                    NSString *codeToCheck = [inputCode copy];
                    
                    // 网络验证
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
                                // 检查激活码是否存在
                                if (json[codeToCheck]) {
                                    success = YES;
                                    message = @"激活码有效，功能已解锁！";
                                    
                                    // 保存激活状态
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
                        
                        // 回到主线程更新UI
                        dispatch_async(dispatch_get_main_queue(), ^{
                            UIAlertController *tipAlert = [UIAlertController alertControllerWithTitle:success ? @"成功" : @"失败" 
                                                                                              message:message 
                                                                                       preferredStyle:UIAlertControllerStyleAlert];
                            [tipAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                            // 使用 keyWindow 展示弹窗
                            [[[UIApplication sharedApplication] keyWindow].rootViewController presentViewController:tipAlert animated:YES completion:nil];
                        });
                    }];
                    [task resume];
                }
            }];

            [alert addAction:confirmAction];
            // 展示弹窗
            [[[UIApplication sharedApplication] keyWindow].rootViewController presentViewController:alert animated:YES completion:nil];
        });
    }

    // 返回原始方法的执行结果
    return result;
}

%end
