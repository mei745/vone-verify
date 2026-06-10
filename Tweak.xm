#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <objc/runtime.h> // 必须引入，用于获取第三方类

#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify"
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.yourcompany.vone-verify.plist"

// === 核心 Hook 块 ===
%hook WeChat

// 1. 定义自定义方法 (必须用 %new)
%new
- (void)vone_verifyCodeWithServer:(NSString *)code {
    NSURL *url = [NSURL URLWithString:VERIFY_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    // 构造参数
    NSString *udid = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    NSString *postString = [NSString stringWithFormat:@"code=%@&udid=%@", code, udid];
    request.HTTPBody = [postString dataUsingEncoding:NSUTF8StringEncoding];

    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *status = json[@"status"];

            // 回到主线程弹窗
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([status isEqualToString:@"success"]) {
                    NSLog(@"[VoneVerify] 激活成功!");
                } else if ([status isEqualToString:@"frozen"]) {
                    [self vone_showAlertWithTitle:@"激活失效" message:@"您的激活码已被冻结，请联系管理员。"];
                } else {
                    [self vone_showAlertWithTitle:@"验证失败" message:@"无效的激活码，请检查网络或联系作者。"];
                }
            });
        }
    }] resume];
}

%new
- (void)vone_showAlertWithTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];

    // 获取当前显示的控制器来弹窗
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

%end

// === 构造函数 (插件加载时立即执行) ===
%ctor {
    // 延迟 3 秒执行，确保微信 UI 已经初始化完毕
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

        // 1. 读取本地激活码
        NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
        NSString *savedCode = settings[@"activation_code"];

        if (savedCode && savedCode.length > 0) {
            // 2. 动态获取 WeChat 类 (解决编译器找不到类的问题)
            Class wechatClass = objc_getClass("WeChat");
            if (wechatClass) {
                // 3. 动态调用 sharedInstance (解决编译器找不到方法的问题)
                // 注意：这里假设微信的单例方法是 sharedInstance，如果是 shareInstance 请自行修改字符串
                id wechatInstance = [wechatClass performSelector:NSSelectorFromString(@"sharedInstance")];

                if (wechatInstance) {
                    // 4. 调用我们在上面定义的验证方法
                    [wechatInstance vone_verifyCodeWithServer:savedCode];
                } else {
                    NSLog(@"[VoneVerify] 错误：无法获取 WeChat 单例对象");
                }
            } else {
                NSLog(@"[VoneVerify] 错误：未找到 WeChat 类，请确认包名是否正确");
            }
        }
    });
}
