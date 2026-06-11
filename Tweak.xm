#import <UIKit/UIKit.h>
#include <objc/runtime.h>

// ================= 配置区域 =================
#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify" // 你的验证接口
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.yourcompany.vone-verify.plist"
// =============================================

// 辅助函数：获取 Plist 中的激活码
static NSString *getSavedCode() {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
    return prefs[@"activation_code"];
}

// 辅助函数：显示弹窗 (使用 objc_msgSend 避开编译检查)
static void showMyAlert(id self, NSString *title, NSString *msg, BOOL blocking) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *action = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:action];

    // 找到当前显示的 ViewController
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

// 辅助函数：联网验证
static void verifyWithServer(id self, NSString *code) {
    if (!code || code.length == 0) return;

    NSURLSession *session = [NSURLSession sharedSession];
    // 构造请求
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:VERIFY_URL]];
    request.HTTPMethod = @"POST";

    // 构造 Body: code=xxxxx
    NSString *bodyStr = [NSString stringWithFormat:@"code=%@", code];
    request.HTTPBody = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];

    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                showMyAlert(self, @"网络错误", @"无法连接服务器，请检查网络。", NO);
            });
            return;
        }

        // 简单的成功判断 (假设返回 "success" 字符串)
        NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if ([result containsString:@"success"]) {
             // 验证成功，这里可以保存状态到 Plist
             NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:PLIST_PATH];
             if (!prefs) prefs = [NSMutableDictionary dictionary];
             prefs[@"is_activated"] = @YES;
             [prefs writeToFile:PLIST_PATH atomically:YES];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                showMyAlert(self, @"激活失败", @"激活码无效或已过期", YES);
            });
        }
    }] resume];
}

// 主逻辑：启动检查
%hook MicroMessengerAppDelegate

- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig; // 先执行原始逻辑

    // 延迟 5 秒执行，防止影响启动动画
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSString *savedCode = getSavedCode();

        // 如果没有激活码，或者需要强制校验
        if (!savedCode) {
            showMyAlert(self, @"需要激活", @"本插件需要激活码才能使用，请联系管理员获取。", YES);
        } else {
            // 有激活码，后台静默验证
            verifyWithServer(self, savedCode);
        }
    });
}

%end
