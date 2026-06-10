#import <UIKit/UIKit.h>
#include <objc/runtime.h>

// ================= 配置区域 =================
#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify" // 你的验证接口
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.yourcompany.vone-verify.plist"
// =============================================

// 【关键修复】定义 Category 接口，解决 "Forward Declaration" 报错
@interface MicroMessengerAppDelegate (VoneVerify)
- (void)vone_startActivationCheck;
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg isBlocking:(BOOL)blocking;
@end

%hook MicroMessengerAppDelegate

// 1. 实现自定义方法：显示弹窗
%new
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg isBlocking:(BOOL)blocking {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window) return;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];

        if (blocking) {
            // 阻塞模式：必须输入激活码才能关闭
            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"请输入激活码";
                textField.secureTextEntry = YES;
            }];

            UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"提交验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                NSString *code = alert.textFields.firstObject.text;
                if (code.length > 0) {
                    // 用户点击提交后，再次发起网络请求
                    [self vone_verifyCodeWithServer:code];
                } else {
                    // 如果没填就点提交，继续弹窗
                    [self vone_showAlertWithTitle:@"提示" message:@"激活码不能为空" isBlocking:YES];
                }
            }];
            [alert addAction:confirmAction];
        } else {
            // 非阻塞模式（如验证成功）
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
            [alert addAction:okAction];
        }

        [window.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

// 2. 实现自定义方法：联网验证逻辑
%new
- (void)vone_verifyCodeWithServer:(NSString *)code {
    // 显示一个加载中的提示（可选，这里简化为不显示，直接请求）
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@&code=%@", VERIFY_URL, code]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST"; // 根据你的服务器要求改为 GET 或 POST

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [self vone_showAlertWithTitle:@"网络错误" message:@"无法连接服务器，请检查网络" isBlocking:YES];
                return;
            }

            // 解析服务器返回的 JSON
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *status = json[@"status"]; // 假设服务器返回 {"status": "success"} 或 "fail"

            if ([status isEqualToString:@"success"]) {
                // 验证成功：保存激活码到本地 plist
                NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithContentsOfFile:PLIST_PATH];
                if (!prefs) prefs = [[NSMutableDictionary alloc] init];
                prefs[@"activation_code"] = code;
                [prefs writeToFile:PLIST_PATH atomically:YES];

                [self vone_showAlertWithTitle:@"激活成功" message:@"插件已激活，感谢您的支持！" isBlocking:NO];
            } else {
                // 验证失败：继续弹窗让用户重试
                [self vone_showAlertWithTitle:@"激活失败" message:@"激活码无效或已过期" isBlocking:YES];
            }
        });
    }];
    [task resume];
}

// 3. 实现自定义方法：启动检查入口
%new
- (void)vone_startActivationCheck {
    // 读取本地已保存的激活码
    NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithContentsOfFile:PLIST_PATH];
    NSString *savedCode = prefs[@"activation_code"];

    if (savedCode && savedCode.length > 0) {
        // 如果有缓存，静默验证一次（防止用户修改服务器数据或激活码过期）
        [self vone_verifyCodeWithServer:savedCode];
    } else {
        // 如果没有缓存，延迟 4 秒弹出输入框
        // 这里的 4 秒就是你要求的 3-6 秒区间
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self vone_showAlertWithTitle:@"需要激活" message:@"本插件需要激活码才能使用，请联系管理员获取。" isBlocking:YES];
        });
    }
}

// 4. Hook 微信启动生命周期
// applicationDidBecomeActive: 是微信启动完成并显示主界面的时刻
- (void)applicationDidBecomeActive:(id)arg1 {
    %orig; // 先执行微信原本的逻辑

    // 为了防止每次切后台再回来都弹窗，我们可以加一个简单的静态变量判断是否已经检查过
    static BOOL hasChecked = NO;
    if (!hasChecked) {
        hasChecked = YES;
        [self vone_startActivationCheck];
    }
}

%end
