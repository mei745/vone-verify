#import <UIKit/UIKit.h>
#include <dlfcn.h> // 用于 exit(0)

// === 配置区域 ===
#define VERIFY_API_URL @"https://vonekeji.cn/verify.php"
#define PREFS_KEY      @"vone_activation_code"
#define PREFS_STATUS   @"vone_is_activated"

@interface MicroMessengerAppDelegate : UIResponder <UIApplicationDelegate>
@end

// --- 辅助函数：获取当前最顶层的控制器 ---
UIViewController *TopMostViewController() {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in scenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *w in windowScene.windows) {
                    if (w.isKeyWindow) {
                        window = w;
                        break;
                    }
                }
            }
        }
    } else {
        window = [UIApplication sharedApplication].keyWindow;
    }
    return window.rootViewController;
}

// --- 核心逻辑：显示验证窗口 ---
void ShowVerificationWindow() {
    UIViewController *rootVC = TopMostViewController();
    if (!rootVC) return;

    UIWindow *keyWindow = rootVC.view.window;
    CGFloat width = 270;

    // 1. 创建遮罩层 (半透明黑色)
    UIView *overlayView = [[UIView alloc] initWithFrame:keyWindow.bounds];
    overlayView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    overlayView.tag = 9999; // 标记一下，方便以后查找

    // 2. 创建主弹窗容器 (模仿系统 Alert 的浅灰色背景)
    UIView *alertView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 180)];
    alertView.center = CGPointMake(keyWindow.bounds.size.width / 2, keyWindow.bounds.size.height / 2);
    alertView.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0]; // 系统灰
    alertView.layer.cornerRadius = 14;
    alertView.clipsToBounds = YES;

    // 3. 标题 Label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, width, 30)];
    titleLabel.text = @"Vone 激活验证";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    titleLabel.textColor = [UIColor blackColor];
    [alertView addSubview:titleLabel];

    // 4. 输入框 TextField
    UITextField *codeField = [[UITextField alloc] initWithFrame:CGRectMake(15, 60, width - 30, 30)];
    codeField.borderStyle = UITextBorderStyleRoundedRect;
    codeField.placeholder = @"请输入激活码...";
    codeField.clearButtonMode = UITextFieldViewModeWhileEditing;
    codeField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    codeField.autocorrectionType = UITextAutocorrectionTypeNo;
    codeField.keyboardType = UIKeyboardTypeAlphabet; // 假设是字母数字混合
    [alertView addSubview:codeField];

    // 5. 验证按钮 Button
    UIButton *verifyBtn = [[UIButton alloc] initWithFrame:CGRectMake(15, 105, width - 30, 44)];
    verifyBtn.backgroundColor = [UIColor systemBlueColor];
    [verifyBtn setTitle:@"立即验证" forState:UIControlStateNormal];
    [verifyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    verifyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    verifyBtn.layer.cornerRadius = 8;
    [alertView addSubview:verifyBtn];

    // 6. 分割线 (为了更像系统弹窗，我们在按钮上方加一条线，或者把按钮做成独立区域)
    // 这里我们采用更简单的做法：直接在按钮上方加个细线，或者保持简洁。
    // 为了完全复刻截图效果，我们把按钮区域稍微分开一点。
    UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(0, 100, width, 0.5)];
    separator.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.3];
    [alertView addSubview:separator];

    // 调整布局让按钮在分割线下面
    verifyBtn.frame = CGRectMake(0, 100.5, width, 44);
    verifyBtn.layer.cornerRadius = 0; // 底部按钮通常不需要圆角，或者是整体圆角
    // 修正：为了好看，我们保留整体圆角，按钮内部不需要圆角
    alertView.layer.cornerRadius = 14;

    // 重新调整高度，把按钮放到底部
    alertView.frame = CGRectMake(0, 0, width, 150);
    titleLabel.frame = CGRectMake(0, 15, width, 30);
    codeField.frame = CGRectMake(15, 55, width - 30, 30);
    separator.frame = CGRectMake(0, 95, width, 0.5);
    verifyBtn.frame = CGRectMake(0, 95.5, width, 54.5); // 填满底部

    // 将弹窗添加到遮罩层
    [overlayView addSubview:alertView];

    // --- 交互逻辑 ---

    // 点击遮罩层不做反应（强制验证）
    // overlayView.userInteractionEnabled = NO; // 如果想让用户点外面关闭，就设为NO，但你要的是强制，所以不用管

    // 点击验证按钮
    [verifyBtn addTarget:nil action:@selector(handleVerifyClick:) forControlEvents:UIControlEventTouchUpInside];

    // 使用 Associated Object 传递数据给 Target-Action
    // 注意：这里我们需要一个临时的对象来持有 block，或者使用静态变量。
    // 为了简单，我们用 objc_setAssociatedObject 绑定到 button 上。
    // 需要引入 runtime
    void (^verifyBlock)(void) = ^{
        NSString *code = codeField.text;

        // 1. 判空
        if (code.length == 0) {
            // 震动反馈
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
            // 修改按钮文字提示
            [verifyBtn setTitle:@"激活码不能为空!" forState:UIControlStateNormal];
            [verifyBtn setBackgroundColor:[UIColor systemRedColor]];
            // 2秒后恢复
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [verifyBtn setTitle:@"立即验证" forState:UIControlStateNormal];
                [verifyBtn setBackgroundColor:[UIColor systemBlueColor]];
            });
            return; // 结束，窗口不消失
        }

        // 2. 设置 Loading 状态
        [verifyBtn setTitle:@"验证中..." forState:UIControlStateNormal];
        verifyBtn.enabled = NO;
        verifyBtn.backgroundColor = [UIColor grayColor];

        // 3. 发起网络请求
        NSString *urlString = [NSString stringWithFormat:@"%@?code=%@", VERIFY_API_URL, code];
        NSURL *url = [NSURL URLWithString:urlString];
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // 恢复按钮状态
                verifyBtn.enabled = YES;
                [verifyBtn setTitle:@"立即验证" forState:UIControlStateNormal];
                [verifyBtn setBackgroundColor:[UIColor systemBlueColor]];

                BOOL isSuccess = NO;

                if (error) {
                    NSLog(@"网络错误: %@", error.localizedDescription);
                } else {
                    NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    NSLog(@"服务器返回: %@", result);

                    // 简单的判断逻辑：包含 success 或 1 视为成功
                    // 根据你的 PHP 返回值调整，比如 "ok", "success", "1"
                    if ([result.lowercaseString containsString:@"success"] ||
                        [result.lowercaseString containsString:@"ok"] ||
                        [result isEqualToString:@"1"]) {
                        isSuccess = YES;
                    }
                }

                if (isSuccess) {
                    // === 验证成功 ===
                    // 保存激活码
                    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                    [defaults setObject:code forKey:PREFS_KEY];
                    [defaults setBool:YES forKey:PREFS_STATUS];
                    [defaults synchronize];

                    // 显示成功提示 (这里可以用系统自带的，反正马上要销毁了)
                    UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"验证成功" message:@"欢迎使用 Vone 插件" preferredStyle:UIAlertControllerStyleAlert];
                    [successAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                         // 点击确定后，移除整个验证窗口
                         [overlayView removeFromSuperview];
                    }]];
                    [rootVC presentViewController:successAlert animated:YES completion:nil];

                } else {
                    // === 验证失败 ===
                    // 震动反馈
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
                    // 修改按钮文字提示
                    [verifyBtn setTitle:@"激活码错误，请重试" forState:UIControlStateNormal];
                    [verifyBtn setBackgroundColor:[UIColor systemRedColor]];
                    // 窗口保留，用户可继续输入
                }
            });
        }];
        [task resume];
    };

    // 绑定 Block 到按钮 (需要 Runtime)
    objc_setAssociatedObject(verifyBtn, "verifyBlock", verifyBlock, OBJC_ASSOCIATION_COPY);

    // 真正的 Target Action
    [verifyBtn addTarget:nil action:@selector(triggerVerifyBlock:) forControlEvents:UIControlEventTouchUpInside];

    // 添加到窗口
    [keyWindow addSubview:overlayView];
}

// --- 辅助 C 函数：触发 Block ---
// 必须定义在全局，且参数匹配
void triggerVerifyBlock(UIButton *sender) {
    void (^block)(void) = objc_getAssociatedObject(sender, "verifyBlock");
    if (block) {
        block();
    }
}

// --- Hook 入口 ---
%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    // 检查是否已激活
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isActivated = [defaults boolForKey:PREFS_STATUS];

    if (!isActivated) {
        // 延迟一点点显示，防止遮挡启动动画
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ShowVerificationWindow();
        });
    }

    return YES;
}

%end
