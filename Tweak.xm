#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <objc/runtime.h> // 引入运行时头文件以使用 objc_getClass

#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify"
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.yourcompany.vone-verify.plist"

// 全局变量，用于标记是否激活成功
static BOOL isActivated = NO;

// === 核心逻辑写在 %new 块中 ===
%hook WeChat // 这里直接 Hook WeChat 类，不需要提前声明

// 自定义的验证方法
%new
- (void)vone_verifyCodeWithServer:(NSString *)code {
    NSURL *url = [NSURL URLWithString:VERIFY_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    // 构造参数
    NSString *postString = [NSString stringWithFormat:@"code=%@&udid=%@",
                            code,
                            [[[UIDevice currentDevice] identifierForVendor] UUIDString]];
    request.HTTPBody = [postString dataUsingEncoding:NSUTF8StringEncoding];

    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *status = json[@"status"];

            dispatch_async(dispatch_get_main_queue(), ^{
                if ([status isEqualToString:@"success"]) {
                    isActivated = YES;
                    NSLog(@"[VoneVerify] ✅ 激活成功！");
                } else if ([status isEqualToString:@"frozen"]) {
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"激活失效"
                                                                    message:@"您的激活码已被冻结，请联系管理员。"
                                                                   delegate:nil
                                                          cancelButtonTitle:@"确定"
                                                          otherButtonTitles:nil];
                    [alert show];
                } else {
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"验证失败"
                                                                    message:@"无效的激活码，请检查网络或联系作者。"
                                                                   delegate:nil
                                                          cancelButtonTitle:@"确定"
                                                          otherButtonTitles:nil];
                    [alert show];
                }
            });
        } else {
             NSLog(@"[VoneVerify] ❌ 网络请求失败: %@", error.localizedDescription);
        }
    }] resume];
}

%end

// === 插件加载入口 (%ctor) ===
%ctor {
    // 1. 读取本地 plist
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
    NSString *savedCode = settings[@"activation_code"];

    if (savedCode && savedCode.length > 0) {
        // 2. 获取 WeChat 单例
        // 注意：不同版本的微信单例获取方式可能不同，这里尝试通用的 shareInstance
        Class wechatClass = objc_getClass("WeChat");
        id wechatInstance = nil;

        if (wechatClass && [wechatClass respondsToSelector:@selector(shareInstance)]) {
            wechatInstance = [wechatClass shareInstance];
        } else if (wechatClass && [wechatClass respondsToSelector:@selector(sharedInstance)]) {
            wechatInstance = [wechatClass sharedInstance];
        }

        // 3. 如果找到了实例，就调用验证方法
        if (wechatInstance) {
            // 延迟 2 秒执行，确保 UI 和网络环境准备就绪
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [wechatInstance vone_verifyCodeWithServer:savedCode];
            });
        } else {
            NSLog(@"[VoneVerify] ⚠️ 未找到 WeChat 单例，无法自动验证。");
        }
    } else {
        NSLog(@"[VoneVerify] ℹ️ 本地没有保存激活码，跳过验证。");
    }
}
