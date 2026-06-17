#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h> // ✅ 修复报错：必须引入这个头文件才能使用关联对象

// --- 配置区 ---
#define SERVER_URL @"https://vonekeji.cn/verify.php"

// --- 全局变量 ---
static BOOL isVerified = NO;
static UIWindow *verifyWindow = nil;

// 获取设备唯一标识
NSString* getDeviceUUID() {
    return [[UIDevice currentDevice] identifierForVendor].UUIDString;
}

// --- 核心逻辑函数 (独立于 Hook 之外，避免 Logos 预处理错误) ---
void PerformVerificationRequest(UILabel *statusLabel, UITextField *inputField) {
    NSString *uuid = getDeviceUUID();
    NSString *code = inputField.text;

    if (code.length == 0) {
        statusLabel.text = @"请输入激活码";
        statusLabel.textColor = [UIColor redColor];
        return;
    }

    statusLabel.text = @"正在验证...";
    statusLabel.textColor = [UIColor grayColor];

    // 构建请求
    NSURL *url = [NSURL URLWithString:SERVER_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    NSString *body = [NSString stringWithFormat:@"uuid=%@&code=%@", uuid, code];
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    // 发送异步请求
    [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                statusLabel.text = @"网络错误";
                statusLabel.textColor = [UIColor redColor];
                return;
            }

            // 简单的解析逻辑 (假设服务器返回 "success" 或 "fail")
            NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[VoneVerify] Server Response: %@", result);

            if ([result.lowercaseString containsString:@"success"]) {
                statusLabel.text = @"验证成功！";
                statusLabel.textColor = [UIColor greenColor];
                isVerified = YES;

                // 验证成功后隐藏窗口
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    verifyWindow.hidden = YES;
                    verifyWindow = nil;
                });
            } else {
                statusLabel.text = @"激活码无效";
                statusLabel.textColor = [UIColor redColor];
            }
        });
    }] resume];
}

// --- UI 构建与展示 ---
void ShowVerifyWindow() {
    // 如果已经验证过，直接返回
    if (isVerified) return;

    // 创建一个覆盖全屏的独立窗口，确保在最顶层
    verifyWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    verifyWindow.windowLevel = CGFLOAT_MAX; // ✅ 关键：设置为最高层级，防止被遮挡
    verifyWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.9]; // 半透明黑色背景
    verifyWindow.hidden = NO;

    // 创建卡片容器
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor whiteColor];
    card.layer.cornerRadius = 12;
    [verifyWindow addSubview:card];

    // 布局卡片 (使用 frame 布局以兼容旧版 SDK)
    CGFloat cardWidth = 280;
    CGFloat cardHeight = 220;
    card.frame = CGRectMake(([UIScreen mainScreen].bounds.size.width - cardWidth) / 2,
                            ([UIScreen mainScreen].bounds.size.height - cardHeight) / 2,
                            cardWidth, cardHeight);

    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, cardWidth, 30)];
    titleLabel.text = @"Vone Verify";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [card addSubview:titleLabel];

    // 输入框
    UITextField *inputField = [[UITextField alloc] initWithFrame:CGRectMake(20, 70, cardWidth - 40, 40)];
    inputField.placeholder = @"请输入激活码";
    inputField.borderStyle = UITextBorderStyleRoundedRect;
    inputField.textAlignment = NSTextAlignmentCenter;
    [card addSubview:inputField];

    // 状态提示标签
    UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 120, cardWidth, 20)];
    statusLabel.text = @"等待输入...";
    statusLabel.textAlignment = NSTextAlignmentCenter;
    statusLabel.font = [UIFont systemFontOfSize:12];
    statusLabel.textColor = [UIColor grayColor];
    [card addSubview:statusLabel];

    // 确认按钮
    UIButton *btn = [[UIButton alloc] initWithFrame:CGRectMake(20, 150, cardWidth - 40, 40)];
    [btn setTitle:@"验证" forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor systemBlueColor];
    btn.layer.cornerRadius = 8;
    [btn addTarget:nil action:@selector(handleVerifyBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:btn];

    // ✅ 关键：使用 Associated Objects 将控件绑定到按钮上，以便在点击事件中获取它们
    objc_setAssociatedObject(btn, "statusLabel", statusLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(btn, "inputField", inputField, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// --- 按钮点击处理函数 (必须是 C 函数或静态方法，不能是 Block) ---
static void handleVerifyBtnClick(UIButton *btn) {
    UILabel *statusLabel = objc_getAssociatedObject(btn, "statusLabel");
    UITextField *inputField = objc_getAssociatedObject(btn, "inputField");

    if (statusLabel && inputField) {
        PerformVerificationRequest(statusLabel, inputField);
    }
}

// --- Hook 入口 ---
%hook WeChatAppDelegate // 或者 %hook AppDelegate，视微信版本而定

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL orig = %orig;

    // 延迟 1 秒显示，确保微信主界面加载完成
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"[VoneVerify] Attempting to show verify window...");
        ShowVerifyWindow();
    });

    return orig;
}

%end
