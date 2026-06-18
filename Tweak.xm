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

    // 修复编译报错：将 @available 独立出来
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in scenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                    window = windowScene.keyWindow;
                    break;
                }
            }
        }
    } else {
        window = [UIApplication sharedApplication].keyWindow;
    }

    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}

// --- 核心逻辑类 ---
%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    // 检查是否已激活
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isActivated = [defaults boolForKey:PREFS_STATUS];

    if (!isActivated) {
        // 延迟一点弹出，防止遮挡启动动画
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showVerificationWindow];
        });
    }

    return YES;
}

%new
- (void)showVerificationWindow {
    // 获取主窗口
    UIWindow *mainWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                mainWindow = scene.windows.firstObject;
                break;
            }
        }
    } else {
        mainWindow = [UIApplication sharedApplication].keyWindow;
    }

    // 创建遮罩层（背景变暗）
    UIView *overlayView = [[UIView alloc] initWithFrame:mainWindow.bounds];
    overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4]; // 半透明黑色背景
    overlayView.tag = 9999; // 标记以便后续查找
    [mainWindow addSubview:overlayView];

    // 计算弹窗尺寸
    CGFloat width = 270;
    CGFloat height = 180;
    CGFloat x = (mainWindow.bounds.size.width - width) / 2;
    CGFloat y = (mainWindow.bounds.size.height - height) / 2;

    // 创建弹窗容器（模拟原生 Alert 的灰色背景）
    UIView *alertView = [[UIView alloc] initWithFrame:CGRectMake(x, y, width, height)];
    alertView.backgroundColor = [UIColor colorWithRed:0.96 green:0.96 blue:0.96 alpha:1.0]; // iOS 原生浅灰
    alertView.layer.cornerRadius = 14;
    alertView.clipsToBounds = YES;
    alertView.tag = 1000;

    // 标题 Label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, width, 25)];
    titleLabel.text = @"Vone 激活验证";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [alertView addSubview:titleLabel];

    // 输入框
    UITextField *inputField = [[UITextField alloc] initWithFrame:CGRectMake(15, 55, width - 30, 30)];
    inputField.placeholder = @"请输入激活码";
    inputField.borderStyle = UITextBorderStyleRoundedRect;
    inputField.backgroundColor = [UIColor whiteColor];
    inputField.clearButtonMode = UITextFieldViewModeWhileEditing;
    inputField.keyboardType = UIKeyboardTypeAlphabet; // 或者 NumberPad
    [alertView addSubview:inputField];

    // 分割线（模拟原生风格）
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 100, width, 0.5)];
    line.backgroundColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:1.0];
    [alertView addSubview:line];

    // 按钮
    UIButton *verifyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    verifyBtn.frame = CGRectMake(0, 100, width, 80);
    [verifyBtn setTitle:@"立即验证" forState:UIControlStateNormal];
    verifyBtn.titleLabel.font = [UIFont systemFontOfSize:17];
    [verifyBtn setTitleColor:[UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0] forState:UIControlStateNormal]; // 原生蓝
    [verifyBtn addTarget:self action:@selector(handleVerifyClick:) forControlEvents:UIControlEventTouchUpInside];

    // 利用 Tag 传递数据给按钮事件
    verifyBtn.tag = 2000;

    [alertView addSubview:verifyBtn];
    [overlayView addSubview:alertView];

    // 简单的入场动画
    alertView.transform = CGAffineTransformMakeScale(1.1, 1.1);
    alertView.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{
        alertView.transform =
