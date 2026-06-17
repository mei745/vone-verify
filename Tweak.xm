#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// --- 配置区 ---
#define SERVER_URL @"https://vonekeji.cn/verify.php" // 你的验证接口
#define PLUGIN_NAME @"VoneVerify"

// --- 全局变量 ---
static BOOL isVerified = NO;
static UIWindow *verifyWindow = nil;
static dispatch_once_t onceToken;

// 获取设备唯一标识 (UUID)
NSString* getDeviceUUID() {
    return [[UIDevice currentDevice] identifierForVendor].UUIDString;
}

// 检查是否已验证 (利用 NSUserDefaults 持久化)
BOOL checkIfVerified() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedCode = [defaults stringForKey:@"VoneVerify_Code"];
    if (savedCode && savedCode.length > 0) {
        // 这里简单判断是否有值，实际项目中建议校验时间戳或再次联网校验
        return YES;
    }
    return NO;
}

// 保存验证状态
void saveVerificationStatus(NSString *code) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:code forKey:@"VoneVerify_Code"];
    [defaults synchronize];
}

%hook UIApplication

// Hook setDelegate: 是因为这是所有 App 启动必经之路，比 didFinishLaunching 更稳
- (void)setDelegate:(id<UIApplicationDelegate>)delegate {
    %orig;

    // 确保只执行一次
    dispatch_once(&onceToken, ^{
        // 如果已经验证过，直接返回，不弹窗
        if (checkIfVerified()) {
            NSLog(@"[VoneVerify] Already verified, skipping popup.");
            return;
        }

        NSLog(@"[VoneVerify] Triggering verification UI...");

        // 1. 创建独立窗口，层级设为最高，防止被遮挡
        verifyWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        verifyWindow.windowLevel = CGFLOAT_MAX; // 关键：最高层级
        verifyWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8]; // 半透明遮罩
        verifyWindow.hidden = NO;

        // 2. 构建验证界面
        UIView *alertView = [[UIView alloc] initWithFrame:CGRectMake(30, 0, [UIScreen mainScreen].bounds.size.width - 60, 200)];
        alertView.center = verifyWindow.center;
        alertView.backgroundColor = [UIColor whiteColor];
        alertView.layer.cornerRadius = 12;
        alertView.clipsToBounds = YES;

        // 标题
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, alertView.bounds.size.width, 40)];
        titleLabel.text = @"温馨提示";
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.font = [UIFont boldSystemFontOfSize:18];

        // 提示语
        UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 55, alertView.bounds.size.width, 30)];
        descLabel.text = @"请输入激活码";
        descLabel.textAlignment = NSTextAlignmentCenter;
        descLabel.textColor = [UIColor grayColor];
        descLabel.font = [UIFont systemFontOfSize:14];

        // 输入框
        UITextField *inputField = [[UITextField alloc] initWithFrame:CGRectMake(20, 95, alertView.bounds.size.width - 40, 40)];
        inputField.borderStyle = UITextBorderStyleRoundedRect;
        inputField.placeholder = @"请输入激活码";
        inputField.clearButtonMode = UITextFieldViewModeWhileEditing;

        // 按钮
        UIButton *verifyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        verifyBtn.frame = CGRectMake(20, 145, alertView.bounds.size.width - 40, 40);
        [verifyBtn setTitle:@"验证" forState:UIControlStateNormal];
        verifyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];

        // 3. 按钮点击逻辑 (Block 写法修复)
        [verifyBtn addTarget:nil action:@selector(verifyAction:) forControlEvents:UIControlEventTouchUpInside];

        // 将控件添加到视图
        [alertView addSubview:titleLabel];
        [alertView addSubview:descLabel];
        [alertView addSubview:inputField];
        [alertView addSubview:verifyBtn];
        [verifyWindow addSubview:alertView];

        // 4. 利用 Runtime 关联对象传递数据，避免全局变量混乱
        objc_setAssociatedObject(verifyBtn, "inputFieldRef", inputField, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(verifyBtn, "alertViewRef", alertView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

%new
+ (void)verifyAction:(UIButton *)sender {
    UITextField *inputField = objc_getAssociatedObject(sender, "inputFieldRef");
    UIView *alertView = objc_getAssociatedObject(sender, "alertViewRef");
    NSString *code = inputField.text;

    if (!code || code.length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"请输入激活码" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        // 注意：这里需要用 verifyWindow 的 rootViewController 来 presentViewController
        // 为简化，这里直接用系统 Alert 可能会因为层级问题不显示，建议用自定义 Toast
        // 此处为了代码简洁，仅做日志输出，实际应替换为自定义提示
        NSLog(@"[VoneVerify] Code is empty");
        return;
    }

    // 禁用按钮防止重复点击
    sender.enabled = NO;
    sender.titleLabel.text = @"验证中...";

    // 5. 发起网络请求 (语法修复重点)
    NSString *urlString = [NSString stringWithFormat:@"%@?code=%@&uuid=%@", SERVER_URL, code, getDeviceUUID()];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    // 构造 Body (修复 .dataUsingEncoding 语法错误)
    NSString *bodyStr = [NSString stringWithFormat:@"code=%@&uuid=%@", code, getDeviceUUID()];
    request.HTTPBody = [bodyStr dataUsingEncoding:NSUTF8StringEncoding]; // 正确写法

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            sender.enabled = YES;
            sender.titleLabel.text = @"验证"; // 恢复按钮文字

            if (error) {
                NSLog(@"[VoneVerify] Network Error: %@", error.localizedDescription);
                // 这里可以加个简单的抖动动画提示失败
                return;
            }

            // 解析 JSON
            NSError *jsonError = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

            if (!jsonError) {
                // 假设后端返回 {"status": 1} 表示成功
                NSInteger status = [json[@"status"] integerValue];
                if (status == 1) {
                    saveVerificationStatus(code);
                    isVerified = YES;

                    // 验证成功，隐藏窗口
                    [UIView animateWithDuration:0.3 animations:^{
                        verifyWindow.alpha = 0;
                    } completion:^(BOOL finished) {
                        [verifyWindow setHidden:YES];
                        verifyWindow = nil;
                    }];
                } else {
                    NSLog(@"[VoneVerify] Verification Failed: %@", json[@"msg"]);
                }
            }
        });
    }] resume];
}

%end
