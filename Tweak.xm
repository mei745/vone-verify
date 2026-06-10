#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// 定义你的后台验证地址
#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify"
// 定义存储激活码的 plist 路径 (通常放在 /var/mobile/Library/Preferences/)
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.yourcompany.vone-verify.plist"

%hook SpringBoard // 或者 hook 你想限制的 App，比如 WeChat

-(void)applicationDidFinishLaunching:(id)arg1 {
    %orig;

    // 1. 读取本地保存的激活码
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
    NSString *savedCode = settings[@"activation_code"];

    // 如果本地没有码，或者你想每次启动都验证，可以在这里逻辑判断
    // 这里演示：如果有码，就去后台验证一下是否有效
    if (savedCode && savedCode.length > 0) {
        [self verifyCodeWithServer:savedCode];
    } else {
        // 如果没有码，弹出输入框 (可选功能)
        // [self showActivationAlert];
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
                            [[[UIDevice currentDevice] identifierForVendor] UUIDString]]; // 获取 UDID
    request.HTTPBody = [postString dataUsingEncoding:NSUTF8StringEncoding];

    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *status = json[@"status"];

            if ([status isEqualToString:@"success"]) {
                NSLog(@"[VoneVerify] Activation Success!");
                // 在这里写入标志位，允许功能运行
                // 例如：[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IsActivated"];
            } else if ([status isEqualToString:@"frozen"]) {
                NSLog(@"[VoneVerify] Code is frozen.");
                // 可以弹窗提示用户联系管理员
            } else {
                NSLog(@"[VoneVerify] Invalid Code.");
                // 验证失败，可以禁用功能或弹窗
            }
        }
    }] resume];
}

%end
