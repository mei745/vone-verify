#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// --- 配置区 ---
#define SERVER_URL @"https://vonekeji.cn/verify.php"

// --- 全局变量 ---
static BOOL isVerified = NO;
static UIWindow *verifyWindow = nil;

// 获取设备唯一标识
NSString* getDeviceUUID() {
    return [[UIDevice currentDevice] identifierForVendor].UUIDString;
}

// 显示验证界面的函数
void ShowVerifyWindow() {
    // 防止重复弹出
    if (verifyWindow || isVerified) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        verifyWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        verifyWindow.windowLevel = UIWindowLevelAlert + 1; // 关键：设置为最高层级，盖住一切
        verifyWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8]; //以此背景遮罩
        verifyWindow.hidden = NO;

        // 创建卡片视图
        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [UIColor whiteColor];
        card.layer.cornerRadius = 16;
        card.clipsToBounds = YES;
        [verifyWindow addSubview:card];

        // 使用 AutoLayout 居中 (不使用点语法，兼容性好)
        card.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [card.centerXAnchor constraintEqualToAnchor:verifyWindow.centerXAnchor],
            [card.centerYAnchor constraintEqualToAnchor:verifyWindow.centerYAnchor],
            [card.widthAnchor constraintEqualToConstant:300],
            [card.heightAnchor constraintEqualToConstant:400]
        ]];

        // 添加输入框和按钮 (简化示例)
        UITextField *input = [[UITextField alloc] initWithFrame:CGRectMake(20, 50, 260, 40)];
        input.placeholder = @"请输入激活码";
        input.borderStyle = UITextBorderStyleRoundedRect;
        [card addSubview:input];

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, 110, 260, 40);
        [btn setTitle:@"验证" forState:UIControlStateNormal];
        [card addSubview:btn];

        UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(20, 170, 260, 40)];
        status.textAlignment = NSTextAlignmentCenter;
        status.text = @"等待输入...";
        [card addSubview:status];

        // 点击事件处理
        [btn addTarget:nil action:@selector(handleVerifyClick:) forControlEvents:UIControlEventTouchUpInside];

        // 将状态标签和输入框传递给处理函数 (利用 tag 或关联对象，这里简单用 block 模拟)
        objc_setAssociatedObject(btn, "statusLabel", status, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(btn, "inputField", input, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

// 验证逻辑处理函数 (必须声明为 static void 才能在下面被调用)
static void handleVerifyLogic(NSString *code, UILabel *statusLabel) {
    statusLabel.text = @"验证中...";

    NSURL *url = [NSURL URLWithString:SERVER_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    NSString *body = [NSString stringWithFormat:@"uuid=%@&code=%@", getDeviceUUID(), code];
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];

    // 使用 NSURLConnection 发送同步请求 (为了不阻塞 UI，我们在后台线程做)
    // 注意：Theos 环境下有时 NSURLSession 会有奇怪的问题，NSURLConnection 更稳
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [NSURLConnection sendAsynchronousRequest:request queue:queue completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                statusLabel.text = @"网络错误";
            });
            return;
        }

        NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        // 假设服务器返回 "success" 代表验证通过
        BOOL success = [result containsString:@"success"];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                isVerified = YES;
                verifyWindow.hidden = YES;
                verifyWindow = nil;
            } else {
                statusLabel.text = @"验证失败";
            }
        });
    }];
}

// 这是一个辅助类，用来接收按钮点击事件
%hook NSObject
// 我们利用 runtime 动态添加方法，或者简单地在一个已有的类里 hook
%end

// 为了简化，我们直接在 %hook 块外部定义一个 C 函数来处理点击，但这需要 target-action 机制配合
// 这里采用一种简单的 trick：hook UIButton 的 sendActionsForControlEvents
%hook UIButton
- (void)sendActionsForControlEvents:(UIControlEvents)controlEvents {
    %orig;
    // 只有当它是我们的验证按钮时才拦截 (通过 tag 判断，记得给按钮设 tag)
    if (self.tag == 9999 && controlEvents == UIControlEventTouchUpInside) {
        // 找到对应的输入框和标签
        // 注意：在实际工程中最好用子类化，这里为了单文件演示，利用 window 遍历查找
        UIWindow *win = [UIApplication sharedApplication].windows.lastObject;
        if (win && win.windowLevel > UIWindowLevelNormal) {
             // 这种查找方式比较脆弱，建议用上面的 associatedObject 方式
             // 这里为了演示逻辑，假设我们通过某种方式拿到了输入框的内容
             // 实际开发建议把 ShowVerifyWindow 写成一个 UIViewController
        }
    }
}
%end


// --- 真正的入口 Hook ---
// 推荐 Hook didFinishLaunchingWithOptions，这是 App 启动最早且稳定的点
%hook AppDelegate // 微信通常是这个类名，如果是 SceneDelegate 需调整
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL orig = %orig;

    // 延迟 2 秒执行，确保微信的主 Window 已经创建完毕
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!isVerified) {
            ShowVerifyWindow();
        }
    });

    return orig;
}
%end
