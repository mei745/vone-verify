#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// --- 配置区 ---
// 1. 后台验证地址 (请确保这个地址能公网访问)
#define VERIFY_URL @"https://vonekeji.cn/admin.php?action=verify"

// 2. Plist 存储路径 (注意：文件名最好和 Tweak_NAME 一致)
#define PLIST_PATH @"/var/mobile/Library/Preferences/voneyz.plist" 

// --- 代码主体 ---
%hook WeChat // <--- 注意：根据你的 Makefile，这里改为 WeChat

// 这里选择一个微信启动时肯定会调用的方法，比 applicationDidFinishLaunching 更可靠
-(void)viewDidAppear:(BOOL)animated {
    %orig;

    // 防止重复验证 (可选)
    static BOOL hasVerified = NO;
    if (hasVerified) return;
    hasVerified = YES;

    // 1. 读取本地激活码
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
    NSString *savedCode = settings[@"activation_code"];

    if (!savedCode || savedCode.length == 0) {
        NSLog(@"[VoneYZ] 未找到激活码，请先输入。");
        // 这里可以弹出一个输入框 [self showInputAlert];
        return;
    }

    // 2. 开始验证
    [self verifyCodeWithServer:savedCode];
}

%new
-(void)verifyCodeWithServer:(NSString *)code {
    NSURL *url = [NSURL URLWithString:VERIFY_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    
    // --- 关键修复：对参数进行 URL 编码，防止特殊字符出错 ---
    NSString *escapedCode = [code stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *udid = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    NSString *escapedUDID = [udid stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    NSString *postString = [NSString stringWithFormat:@"code=%@&udid=%@", escapedCode, escapedUDID];
    request.HTTPBody = [postString dataUsingEncoding:NSUTF8StringEncoding];

    // 设置请求头 (有些 PHP 后台需要)
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        
        // --- 回调在后台线程，处理逻辑 ---
        if (error) {
            NSLog(@"[VoneYZ] 网络错误: %@", error.localizedDescription);
            // 提示用户网络错误 (如果需要UI，请用 dispatch_async 回主线程)
            return;
        }

        if (data) {
            NSError *jsonError;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                NSLog(@"[VoneYZ] JSON解析错误");
                return;
            }

            NSString *status = json[@"status"];
            
            // --- 核心逻辑判断 ---
            if ([status isEqualToString:@"success"]) {
                NSLog(@"[VoneYZ] ✅ 验证通过! 功能已解锁。");
                // TODO: 在这里写入解锁标志，或者直接调用你的功能代码
                // [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Activated"];
                
            } else if ([status isEqualToString:@"frozen"]) {
                NSLog(@"[VoneYZ] ❌ 激活码已被冻结，请联系管理员。");
                // TODO: 弹窗提示用户
                [self showAlertWithTitle:@"错误" message:@"激活码已被冻结"];
                
            } else {
                NSLog(@"[VoneYZ] ❌ 激活码无效或已过期。");
                // TODO: 弹窗提示
                [self showAlertWithTitle:@"错误" message:@"激活码无效"];
            }
        }
    }] resume];
}

// --- 辅助方法：弹窗提示 (用于在后台线程提示用户) ---
%new
-(void)showAlertWithTitle:(NSString *)title message:(NSString *)msg {
    // 确保在主线程执行 UI 操作
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showAlertWithTitle:title message:msg];
        });
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                   message:msg 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    
    // 获取当前最顶层的 ViewController 来展示弹窗
    UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    [vc presentViewController:alert animated:YES completion:nil];
}

%end
