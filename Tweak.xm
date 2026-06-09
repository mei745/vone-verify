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
    // 1. 先执行微信原本的启动逻辑
    %orig;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isActivated = [defaults boolForKey:PREFS_STATUS];

    // 2. 判断逻辑：如果没有激活，才执行下面的弹窗代码
    if (!isActivated) {
        // 延迟2秒弹出，防止和微信启动动画冲突导致卡顿
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

            // === 这里修改标题文字 ===
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"正版授权"
                                                                           message:@"请输入激活码"
                                                                    preferredStyle:UIAlertControllerStyleAlert];

            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"请输入您的激活码";
                textField.secureTextEntry = NO;
            }];

            // “验证”按钮点击事件
            UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                UITextField *codeField = alert.textFields.firstObject;
                NSString *inputCode = codeField.text;

                if (inputCode.length > 0) {
                    NSString *codeToCheck = [inputCode copy];

                    // 发起网络请求
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
                                // 检查服务器返回的字典里有没有这个码
                                if (json[codeToCheck]) {
                                    success = YES;
                                    message = @"激活成功！欢迎使用。";

                                    // === 关键：写入“已激活”状态 ===
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        [defaults setBool:YES forKey:PREFS_STATUS]; // 标记为已激活
                                        [defaults setObject:codeToCheck forKey:PREFS_KEY];
                                        [defaults synchronize];
                                    });
                                } else {
                                    message = @"激活码无效，请重试。";
                                    // 注意：这里没有修改 PREFS_STATUS，所以下次启动还会弹窗
                                }
                            } else {
                                message = @"服务器数据解析失败";
                            }
                        }

                        // 显示结果提示
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

            // 设置弹窗不可取消（用户必须点验证或杀后台）
        alert.modalPresentationStyle = UIModalPresentationOverCurrentContext;

            [[[UIApplication sharedApplication] keyWindow].rootViewController presentViewController:alert animated:YES completion:nil];
        });
    }

    return YES;
}

%end
