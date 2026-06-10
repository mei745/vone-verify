#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// 定义你的后台验证地址
#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify"
// 定义存储激活码的 plist 路径
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.yourcompany.vone-verify.plist"

// === 修复部分开始 ===
// 声明 WeChat 类以及我们要用到的自定义方法
@interface WeChat : NSObject
- (void)verifyCodeWithServer:(NSString *)code;
- (void)showAlertWithTitle:(NSString *)title message:(NSString *)msg;
@end
// === 修复部分结束 ===

%hook WeChat // 确保这里 Hook 的是 WeChat，且 Makefile 里也是 WeChat

-(void)applicationDidFinishLaunching:(id)arg1 {
    %orig;

    // 1. 读取本地保存的激活码
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
    NSString *savedCode = settings[@"activation_code"];

    if (savedCode && savedCode.length > 0) {
        [self verifyCodeWithServer:savedCode];
    } else {
        // 如果没有码，可以在这里弹窗提示输入
        // [self showAlertWithTitle:@"未激活" message:@"请输入激活码"];
    }
}

%new
-(void)verifyCodeWithServer:(NSString *)code {
    NSURL *url = [NSURL URLWithString:VERIFY_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    // 构造 POST 参数
    NSString *postString = [NSString stringWithFormat:@"code=%@&udid=%@",
                            code,
                            [[[UIDevice currentDevice] identifierForVendor] UUIDString]];
    request.HTTPBody = [postString dataUsingEncoding:NSUTF8StringEncoding];

    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *status = json[@"status"];

            if ([status isEqualToString:@"success"]) {
                NSLog(@"[VoneVerify] Activation Success!");
                // 验证成功逻辑
            } else if ([status isEqualToString:@"frozen"]) {
                NSLog(@"[VoneVerify] Code is frozen.");
                // 回到主线程弹窗
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showAlertWithTitle:@"错误" message:@"激活码已被冻结"];
                });
            } else {
                NSLog(@"[VoneVerify] Invalid Code.");
                // 回到主线程弹窗
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showAlertWithTitle:@"错误" message:@"激活码无效"];
                });
            }
        }
    }] resume];
}

%new
-(void)showAlertWithTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];

    // 获取当前顶层控制器来展示 Alert
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

%end
