#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// --- 配置区 ---
#define SERVER_URL @"https://vonekeji.cn/verify.php" // 你的验证接口
#define PLUGIN_NAME @"VoneVerify"

// --- 全局变量 ---
static BOOL isVerified = NO;
static BOOL hasShownVerifyUI = NO; // 标记是否已经尝试显示过UI
static UIWindow *verifyWindow = nil;

// --- 辅助函数：获取设备唯一标识 ---
NSString* getDeviceUUID() {
    return [[UIDevice currentDevice] identifierForVendor].UUIDString;
}

// --- 核心逻辑：显示验证界面 ---
void ShowVerificationUI() {
    if (hasShownVerifyUI) return; // 防止重复调用
    hasShownVerifyUI = YES;

    NSLog(@"[%@] 正在初始化验证窗口...", PLUGIN_NAME);

    // 1. 创建独立的 Window，层级设为最高，防止被遮挡
    verifyWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    verifyWindow.windowLevel = CGFLOAT_MAX; // 关键：最高层级
    verifyWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8]; // 半透明黑色背景

    // 2. 构建 UI
    UIViewController *rootVC = [[UIViewController alloc] init];
    verifyWindow.rootViewController = rootVC;

    // 容器视图
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(30, 0, [UIScreen mainScreen].bounds.size.width - 60, 200)];
    container.center = CGPointMake([UIScreen mainScreen].bounds.size.width / 2, [UIScreen mainScreen].bounds.size.height / 2);
    container.backgroundColor = [UIColor whiteColor];
    container.layer.cornerRadius = 12;
    container.clipsToBounds = YES;
    [rootVC.view addSubview:container];

    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, container.bounds.size.width, 30)];
    titleLabel.text = @"温馨提示";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [container addSubview:titleLabel];

    // 提示语
    UILabel *msgLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 55, container.bounds.size.width, 20)];
    msgLabel.text = @"请输入激活码";
    msgLabel.textAlignment = NSTextAlignmentCenter;
    msgLabel.font = [UIFont systemFontOfSize:14];
    msgLabel.textColor = [UIColor grayColor];
    [container addSubview:msgLabel];

    // 输入框
    UITextField *inputField = [[UITextField alloc] initWithFrame:CGRectMake(15, 90, container.bounds.size.width - 30, 40)];
    inputField.placeholder = @"请输入激活码";
    inputField.borderStyle = UITextBorderStyleRoundedRect;
    inputField.keyboardType = UIKeyboardTypeAlphabet;
    [container addSubview:inputField];

    // 按钮
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(0, 145, container.bounds.size.width, 45);
    [btn setTitle:@"验证" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:16];

    // 3. 点击事件处理
    [btn addTarget:nil action:@selector(handleVerifyClick:) forControlEvents:UIControlEventTouchUpInside];

    // 将输入框和按钮存入关联对象，以便在 C 函数中读取
    objc_setAssociatedObject(btn, "inputField", inputField, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(btn, "statusLabel", msgLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [container addSubview:btn];

    // 4. 显示窗口
    [verifyWindow makeKeyAndVisible];
    NSLog(@"[%@] 验证窗口已显示", PLUGIN_NAME);
}

// --- 按钮点击处理函数 (必须是 C 函数或静态方法) ---
static void handleVerifyClick(UIButton *sender) {
    UITextField *inputField = objc_getAssociatedObject(sender, "inputField");
    UILabel *statusLabel = objc_getAssociatedObject(sender, "statusLabel");
    NSString *code = inputField.text;

    if (code.length == 0) {
        statusLabel.text = @"激活码不能为空";
        statusLabel.textColor = [UIColor redColor];
        return;
    }

    statusLabel.text = @"验证中...";
    statusLabel.textColor = [UIColor blueColor];

    // 发起网络请求
    NSURL *url = [NSURL URLWithString:SERVER_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    NSString *body = [NSString stringWithFormat:@"code=%@&uuid=%@", code, getDeviceUUID()];
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                statusLabel.text = @"网络错误";
                return;
            }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *status = json[@"status"]; // 假设服务器返回 {"status": "success"}

            if ([status isEqualToString:@"success"]) {
                isVerified = YES;
                // 保存验证状态
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"VoneVerify_Status"];
                [[NSUserDefaults standardUserDefaults] synchronize];

                // 隐藏验证窗口
                verifyWindow.hidden = YES;
                verifyWindow = nil;
                NSLog(@"[%@] 验证成功，窗口已关闭", PLUGIN_NAME);
            } else {
                statusLabel.text = @"激活码无效";
                statusLabel.textColor = [UIColor redColor];
            }
        });
    }] resume];
}

// --- Hook 核心：拦截 UIWindow 显示 ---
%hook UIWindow

- (void)makeKeyAndVisible {
    %orig; // 先执行原逻辑，确保 App 正常启动

    // 检查是否已验证
    if (!isVerified) {
        isVerified = [[NSUserDefaults standardUserDefaults] boolForKey:@"VoneVerify_Status"];
    }

    // 如果未验证 且 尚未显示过 UI，则强制弹出
    if (!isVerified && !hasShownVerifyUI) {
        // 延迟一点点执行，确保当前 Window 已经完全初始化
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ShowVerificationUI();
        });
    }
}

%end
