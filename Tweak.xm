#import <UIKit/UIKit.h>
#include <objc/runtime.h>
#include <sys/utsname.h>

// ================= 配置区域 =================
#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify" // 【修改】你的后端验证接口地址
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.vone.verify.plist"
// =============================================

// 获取设备唯一标识符 (UUID)
NSString *getDeviceUUID() {
    NSString *uuid = [[NSUserDefaults standardUserDefaults] stringForKey:@"vone_device_uuid"];
    if (!uuid) {
        uuid = [[NSProcessInfo processInfo] globallyUniqueString];
        [[NSUserDefaults standardUserDefaults] setObject:uuid forKey:@"vone_device_uuid"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    return uuid;
}

// 本地存储激活码
void saveActivationCode(NSString *code) {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:PLIST_PATH];
    if (!prefs) prefs = [NSMutableDictionary dictionary];
    [prefs setObject:code forKey:@"activation_code"];
    [prefs writeToFile:PLIST_PATH atomically:YES];
}

NSString *loadActivationCode() {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:PLIST_PATH];
    return [prefs objectForKey:@"activation_code"];
}

// 显示原生输入弹窗
void showInputAlert(void (^completion)(NSString *code)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"输入您购买的授权卡密" message:nil preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"请输入您的授权卡密";
        textField.secureTextEntry = NO;
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        // 点击取消后，延迟 0.5秒 再次弹出，实现“无法彻底关闭”
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            showInputAlert(completion);
        });
    }];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *textField = alert.textFields.firstObject;
        NSString *inputCode = textField.text;
        if (inputCode.length > 0 && completion) {
            completion(inputCode);
        } else {
            // 如果输入为空点击确定，也视为取消，重新弹出
            showInputAlert(completion);
        }
    }];

    [alert addAction:cancelAction];
    [alert addAction:okAction];

    // 寻找当前顶层控制器来展示弹窗
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

// 显示提示弹窗（欢迎或错误）
void showMessageAlert(NSString *title, NSString *msg, BOOL blocking) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];

    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

// 核心验证逻辑
void startVerificationProcess() {
    NSString *savedCode = loadActivationCode();
    NSString *deviceUUID = getDeviceUUID();

    // 如果没有保存的激活码，直接弹窗
    if (!savedCode || savedCode.length == 0) {
        showInputAlert(nil); // 这里传入 nil，因为第一次只是让用户输，还没法校验
        return;
    }

    // 有激活码，进行网络校验
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?code=%@&uuid=%@", VERIFY_URL, savedCode, deviceUUID]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            // 网络错误处理：为了防破解，网络不通通常视为验证失败或重试
            dispatch_async(dispatch_get_main_queue(), ^{
                showMessageAlert(@"网络错误", @"无法连接服务器，请检查网络。", YES);
            });
            return;
        }

        NSString *resultStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        // 假设后端返回 "OK" 代表成功，其他均为失败信息
        if ([resultStr isEqualToString:@"OK"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // 验证成功，短暂提示
                UIAlertController *toast = [UIAlertController alertControllerWithTitle:@"欢迎使用" message:@"授权验证通过" preferredStyle:UIAlertControllerStyleAlert];
                UIWindow *window = [UIApplication sharedApplication].keyWindow;
                [window.rootViewController presentViewController:toast animated:YES completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [toast dismissViewControllerAnimated:YES completion:nil];
                    });
                }];
            });
        } else {
            // 验证失败（过期、被顶号、无效），清除本地缓存并强制弹窗
            saveActivationCode(@"");
            dispatch_async(dispatch_get_main_queue(), ^{
                showMessageAlert(@"激活失败", resultStr ?: @"激活码无效或已过期", YES);
                // 提示完后进入死循环弹窗
                showInputAlert(nil);
            });
        }
    }] resume];
}

%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    // 延迟 2秒 执行，防止影响微信启动动画导致闪退
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        startVerificationProcess();
    });

    return YES;
}

%end
