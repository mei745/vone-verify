#import <UIKit/UIKit.h>
#include <dlfcn.h>

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
                if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                    window = windowScene.keyWindow;
                    break;
                }
            }
        }
        if (!window) window = [UIApplication sharedApplication].windows.firstObject;
    } else {
        window = [UIApplication sharedApplication].keyWindow;
    }

    UIViewController *topController = window.rootViewController;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    return topController;
}

// --- 核心逻辑类：激活管理器 ---
@interface VoneActivationManager : NSObject
+ (instancetype)sharedManager;
- (void)checkAndShowVerifyViewIfNeeded;
@end

@implementation VoneActivationManager

+ (instancetype)sharedManager {
    static VoneActivationManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

- (void)checkAndShowVerifyViewIfNeeded {
    // 1. 检查是否已激活
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isActivated = [defaults boolForKey:PREFS_STATUS];

    if (isActivated) {
        NSLog(@"[VoneVerify] 用户已激活，跳过验证。");
        return;
    }

    // 2. 未激活，显示验证窗口（强制置顶）
    [self showPersistentVerifyWindow];
}

// --- 创建并显示“死缠烂打”的验证窗口 ---
- (void)showPersistentVerifyWindow {
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    if (!mainWindow) return;

    // 防止重复添加
    UIView *existingOverlay = [mainWindow viewWithTag:99999];
    if (existingOverlay) return;

    // 创建全屏遮罩 View
    UIView *overlayView = [[UIView alloc] initWithFrame:mainWindow.bounds];
    overlayView.tag = 99999; // 标记ID
    overlayView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85]; // 深色背景
    overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    // 添加模糊效果 (可选，增加高级感)
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.frame = overlayView.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [overlayView addSubview:blurView];

    // --- 构建中间的卡片 ---
    CGFloat cardWidth = 300;
    CGFloat cardHeight = 240;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cardWidth, cardHeight)];
    card.center = overlayView.center;
    card.backgroundColor = [UIColor whiteColor];
    card.layer.cornerRadius = 16;
    card.clipsToBounds = YES;

    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 30, cardWidth - 40, 30)];
    titleLabel.text = @"🔒 Vone Verify 授权验证";
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    titleLabel.textColor = [UIColor darkGrayColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [card addSubview:titleLabel];

    // 说明文字
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 70, cardWidth - 40, 40)];
    descLabel.text = @"检测到您尚未激活，请输入正确的激活码。\n⚠️ 输入错误将导致应用重启";
    descLabel.font = [UIFont systemFontOfSize:13];
    descLabel.textColor = [UIColor grayColor];
    descLabel.numberOfLines = 0;
    descLabel.textAlignment = NSTextAlignmentCenter;
    [card addSubview:descLabel];

    // 输入框
    UITextField *codeField = [[UITextField alloc] initWithFrame:CGRectMake(20, 120, cardWidth - 40, 40)];
    codeField.placeholder = @"请输入激活码 (例如: VIP888)";
    codeField.borderStyle = UITextBorderStyleRoundedRect;
    codeField.clearButtonMode = UITextFieldViewModeWhileEditing;
    codeField.keyboardType = UIKeyboardTypeAlphabet; // 字母键盘
    codeField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters; // 自动大写
    [card addSubview:codeField];

    // 验证按钮
    UIButton *verifyBtn = [[UIButton alloc] initWithFrame:CGRectMake(20, 170, cardWidth - 40, 40)];
    verifyBtn.backgroundColor = [UIColor systemBlueColor];
    verifyBtn.layer.cornerRadius = 8;
    [verifyBtn setTitle:@"立即验证" forState:UIControlStateNormal];
    [verifyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [verifyBtn.titleLabel setFont:[UIFont boldSystemFontOfSize:16]];

    // 加载指示器 (初始隐藏)
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.center = verifyBtn.center;
    spinner.hidden = YES;
    [card addSubview:spinner];

    // --- 核心交互逻辑 ---
    __block typeof(self) weakSelf = self;
    [verifyBtn addTarget:nil action:@selector(buttonClicked:) forControlEvents:UIControlEventTouchUpInside];

    // 使用 objc_setAssociatedObject 传递参数给 C 函数风格的 target
    // 这里为了简单，我们用 Block 包装一下，或者直接在下面定义一个静态函数
    // 为了方便，我们创建一个临时的 Target 对象来处理点击

    void (^verifyAction)(void) = ^{
        NSString *inputCode = [codeField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        // 1. 判空逻辑：如果不为空，才开始验证；如果为空，啥也不做（窗口不消失）
        if (inputCode.length == 0) {
            // 抖动动画提示
            CABasicAnimation *shake = [CABasicAnimation animationWithKeyPath:@"position"];
            shake.duration = 0.05;
            shake.repeatCount = 5;
            shake.autoreverses = YES;
            shake.fromValue = [NSValue valueWithCGPoint:CGPointMake(card.center.x - 10, card.center.y)];
            shake.toValue = [NSValue valueWithCGPoint:CGPointMake(card.center.x + 10, card.center.y)];
            [card.layer addAnimation:shake forKey:@"shake"];
            return; // 【关键点】直接返回，窗口保留
        }

        // 2. 开始验证 UI 状态
        verifyBtn.enabled = NO;
        verifyBtn.alpha = 0.5;
        verifyBtn.titleLabel.text = @""; // 清空文字
        spinner.hidden = NO;
        [spinner startAnimating];

        // 3. 发起网络请求
        NSURL *url = [NSURL URLWithString:VERIFY_API_URL];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";
        NSString *postString = [NSString stringWithFormat:@"code=%@", inputCode];
        request.HTTPBody = [postString dataUsingEncoding:NSUTF8StringEncoding];
        request.timeoutInterval = 10;

        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // 恢复 UI
                verifyBtn.enabled = YES;
                verifyBtn.alpha = 1.0;
                [verifyBtn setTitle:@"立即验证" forState:UIControlStateNormal];
                spinner.hidden = YES;
                [spinner stopAnimating];

                BOOL success = NO;

                if (!error && data) {
                    NSString *resultStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    NSLog(@"[VoneVerify] Server Response: %@", resultStr);

                    // 简单的成功判断逻辑 (兼容 JSON 和 纯文本)
                    if ([resultStr containsString:@"\"code\":1"] ||
                        [resultStr containsString:@"\"success\":true"] ||
                        [resultStr.lowercaseString isEqualToString:@"success"] ||
                        [resultStr.lowercaseString isEqualToString:@"ok"]) {
                        success = YES;
                    }
                }

                if (success) {
                    // --- 验证成功 ---
                    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                    [defaults setObject:inputCode forKey:PREFS_KEY];
                    [defaults setBool:YES forKey:PREFS_STATUS];
                    [defaults synchronize];

                    // 移除窗口
                    [overlayView removeFromSuperview];

                    // 提示成功
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恭喜" message:@"激活成功！" preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"进入应用" style:UIAlertActionStyleDefault handler:nil]];
                    [TopMostViewController() presentViewController:alert animated:YES completion:nil];

                } else {
                    // --- 验证失败 ---
                    // 关键点：这里不调用 removeFromSuperview，窗口继续存在！
                    // 可以弹个 Toast 或者 Shake 动画
                    UIAlertController *failAlert = [UIAlertController alertControllerWithTitle:@"验证失败" message:@"激活码无效或网络错误，请重试。" preferredStyle:UIAlertControllerStyleAlert];
                    [failAlert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleCancel handler:nil]];
                    [TopMostViewController() presentViewController:failAlert animated:YES completion:nil];
                }
            });
        }] resume];
    };

    // 绑定点击事件
    [verifyBtn addTarget:self action:@selector(dummyAction) forControlEvents:UIControlEventTouchUpInside];
    // 利用 Associated Object 存 block (这是 OC 比较 trick 的写法，为了保持单文件简洁)
    objc_setAssociatedObject(verifyBtn, "verifyBlock", verifyAction, OBJC_ASSOCIATION_COPY);

    // 实际触发的方法
    objc_setAssociatedObject(verifyBtn, "targetAction", ^(id sender){
        void(^block)(void) = objc_getAssociatedObject(sender, "verifyBlock");
        if(block) block();
    }, OBJC_ASSOCIATION_COPY);

    // 由于上面写法比较复杂，我们换一种更稳健的方式：自定义 Delegate 或直接写在这个类里
    // 为了代码稳定性，我重写一下 Button 的 Target 部分：

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleVerifyTap:)];
    [verifyBtn addGestureRecognizer:tap];
    // 把需要的数据存到 verifyBtn 的父视图或者 tag 里不太好传，
    // 所以我们直接用实例变量或者关联对象把 overlayView 和 codeField 传进去。
    objc_setAssociatedObject(verifyBtn, "field_ref", codeField, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(verifyBtn, "overlay_ref", overlayView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(verifyBtn, "spinner_ref", spinner, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [card addSubview:verifyBtn];
    [overlayView addSubview:card];
    [mainWindow addSubview:overlayView];
}

// 处理点击
- (void)handleVerifyTap:(UITapGestureRecognizer *)recognizer {
    UIButton *btn = (UIButton *)recognizer.view;
    UITextField *field = objc_getAssociatedObject(btn, "field_ref");
    UIView *overlay = objc_getAssociatedObject(btn, "overlay_ref");
    UIActivityIndicatorView *spinner = objc_getAssociatedObject(btn, "spinner_ref");

    NSString *inputCode = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // 1. 判空：如果为空，只抖动，不消失
    if (inputCode.length == 0) {
        CABasicAnimation *shake = [CABasicAnimation animationWithKeyPath:@"position"];
        shake.duration = 0.06;
        shake.repeatCount = 4;
        shake.autoreverses = YES;
        CGPoint center = btn.superview.center;
        shake.fromValue = [NSValue valueWithCGPoint:CGPointMake(center.x - 15, center.y)];
        shake.toValue = [NSValue valueWithCGPoint:CGPointMake(center.x + 15, center.y)];
        [btn.superview.layer addAnimation:shake forKey:@"shake"];
        return; // 【关键】直接结束，窗口不动
    }

    // 2. Loading 状态
    btn.enabled = NO;
    btn.alpha = 0.5;
    [btn setTitle:@"" forState:UIControlStateNormal];
    spinner.hidden = NO;
    [spinner startAnimating];

    // 3. 网络请求
    NSURL *url = [NSURL URLWithString:VERIFY_API_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [[NSString stringWithFormat:@"code=%@", inputCode] dataUsingEncoding:NSUTF8StringEncoding];
    request.timeoutInterval = 10;

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // 恢复按钮状态
            btn.enabled = YES;
            btn.alpha = 1.0;
            [btn setTitle:@"立即验证" forState:UIControlStateNormal];
            spinner.hidden = YES;
            [spinner stopAnimating];

            BOOL success = NO;
            if (!error && data) {
                NSString *res = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                // 宽松匹配成功关键词
                if ([res containsString:@"\"code\":1"] || [res.lowercaseString containsString:@"success"]) {
                    success = YES;
                }
            }

            if (success) {
                // 成功：保存并移除窗口
                NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
                [def setBool:YES forKey:PREFS_STATUS];
                [def setObject:inputCode forKey:PREFS_KEY];
                [def synchronize];

                [overlay removeFromSuperview]; // 窗口消失

                UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"成功" message:@"欢迎使用 Vone Verify" preferredStyle:UIAlertControllerStyleAlert];
                [ok addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [TopMostViewController() presentViewController:ok animated:YES completion:nil];

            } else {
                // 失败：窗口保留，仅提示
                UIAlertController *err = [UIAlertController alertControllerWithTitle:@"验证失败" message:@"激活码错误或网络异常，请重新输入。" preferredStyle:UIAlertControllerStyleAlert];
                [err addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleCancel handler:nil]];
                [TopMostViewController() presentViewController:err animated:YES completion:nil];
                // 注意：这里没有 remove overlay，所以输入框还在！
            }
        });
    }] resume];
}

- (void)dummyAction {} // 占位符

@end

// --- Hook 入口 ---
%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    // 延迟一点执行，确保 Window 已经创建
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[VoneActivationManager sharedManager] checkAndShowVerifyViewIfNeeded];
    });

    return YES;
}

%end
