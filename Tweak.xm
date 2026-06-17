#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h> // ✅ 必须引入，用于关联对象

// --- 配置区 ---
#define SERVER_URL @"https://vonekeji.cn/verify.php"

// --- 全局变量 ---
static BOOL isVerified = NO;
static UIWindow *verifyWindow = nil;

// 获取设备唯一标识
NSString* getDeviceUUID() {
    return [[UIDevice currentDevice] identifierForVendor].UUIDString;
}

// ✅ 核心修复：将网络请求封装为独立的 C 函数
// 这样 Logos 预处理器就不会干扰 Block 语法的解析了
void PerformVerification(UILabel *statusLabel, UITextField *inputField, UIButton *btn) {
    NSString *code = inputField.text;
    if (code.length == 0) {
        statusLabel.text = @"请输入激活码";
        statusLabel.textColor = [UIColor redColor];
        return;
    }

    statusLabel.text = @"验证中...";
    statusLabel.textColor = [UIColor orangeColor];
    btn.enabled = NO;

    NSString *urlString = [NSString stringWithFormat:@"%@?code=%@&uuid=%@", SERVER_URL, code, getDeviceUUID()];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    // 这里使用 Block 语法是完全安全的，因为它在 C 函数内部
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            btn.enabled = YES;
            if (error) {
                statusLabel.text = @"网络错误";
                statusLabel.textColor = [UIColor redColor];
                return;
            }

            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *msg = json[@"msg"];
            NSNumber *success = json[@"success"];

            if ([success boolValue]) {
                statusLabel.text = msg ?: @"验证成功";
                statusLabel.textColor = [UIColor greenColor];
                isVerified = YES;

                // 验证成功后，延迟隐藏窗口
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    verifyWindow.hidden = YES;
                    verifyWindow = nil;
                });
            } else {
                statusLabel.text = msg ?: @"验证失败";
                statusLabel.textColor = [UIColor redColor];
            }
        });
    }] resume];
}

// --- UI 构建逻辑 ---
%hook WeChatAppDelegate // 也可以尝试 %hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    // 延迟执行，确保微信主界面已经加载完毕
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (isVerified) return;

        // 创建一个独立的 Window，层级设为最高，防止被微信界面遮挡
        verifyWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        verifyWindow.windowLevel = CGFLOAT_MAX;
        verifyWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
        verifyWindow.hidden = NO;

        // 创建半透明背景遮罩
        UIView *bgView = [[UIView alloc] initWithFrame:verifyWindow.bounds];
        bgView.backgroundColor = [UIColor blackColor];
        bgView.alpha = 0.7;
        [verifyWindow addSubview:bgView];

        // 创建卡片容器
        UIView *card = [[UIView alloc] init];
        card.translatesAutoresizingMaskIntoConstraints = NO;
        card.backgroundColor = [UIColor whiteColor];
        card.layer.cornerRadius = 12;
        card.clipsToBounds = YES;
        [verifyWindow addSubview:card];

        // 布局约束
        [NSLayoutConstraint activateConstraints:@[
            [card.centerXAnchor constraintEqualToAnchor:verifyWindow.centerXAnchor],
            [card.centerYAnchor constraintEqualToAnchor:verifyWindow.centerYAnchor],
            [card.widthAnchor constraintEqualToConstant:280],
            [card.heightAnchor constraintEqualToConstant:220]
        ]];

        // 标题
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = @"VoneVerify 验证";
        titleLabel.font = [UIFont boldSystemFontOfSize:18];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:titleLabel];

        // 输入框
        UITextField *inputField = [[UITextField alloc] init];
        inputField.placeholder = @"请输入激活码";
        inputField.borderStyle = UITextBorderStyleRoundedRect;
        inputField.textAlignment = NSTextAlignmentCenter;
        inputField.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:inputField];

        // 状态标签
        UILabel *statusLabel = [[UILabel alloc] init];
        statusLabel.text = @"等待输入...";
        statusLabel.font = [UIFont systemFontOfSize:14];
        statusLabel.textColor = [UIColor grayColor];
        statusLabel.textAlignment = NSTextAlignmentCenter;
        statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:statusLabel];

        // 按钮
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        [btn setTitle:@"立即验证" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        btn.backgroundColor = [UIColor systemBlueColor];
        btn.layer.cornerRadius = 8;
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:btn];

        // 统一布局所有子控件
        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:30],
            [titleLabel.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],

            [inputField.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:20],
            [inputField.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
            [inputField.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
            [inputField.heightAnchor constraintEqualToConstant:40],

            [statusLabel.topAnchor constraintEqualToAnchor:inputField.bottomAnchor constant:15],
            [statusLabel.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],

            [btn.topAnchor constraintEqualToAnchor:statusLabel.bottomAnchor constant:20],
            [btn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
            [btn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
            [btn.heightAnchor constraintEqualToConstant:44]
        ]];

        // ✅ 绑定点击事件调用 C 函数
        [btn addTarget:nil action:@selector(handleVerifyClick:) forControlEvents:UIControlEventTouchUpInside];

        // 利用关联对象把控件传给 C 函数
        objc_setAssociatedObject(btn, "statusLabel", statusLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(btn, "inputField", inputField, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });

    return YES;
}

%end

// ✅ 定义一个全局的 C 函数作为 Target-Action 的入口
// 因为 block 不能直接作为 target-action，所以用这个函数做中转
void handleVerifyClick(UIButton *btn) {
    UILabel *statusLabel = objc_getAssociatedObject(btn, "statusLabel");
    UITextField *inputField = objc_getAssociatedObject(btn, "inputField");
    PerformVerification(statusLabel, inputField, btn);
}
