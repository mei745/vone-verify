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

// --- 核心验证类 (单例模式) ---
@interface VoneVerifyManager : NSObject
@property (nonatomic, strong) UIView *verifyWindow;
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, strong) UIButton *verifyBtn;
@property (nonatomic, strong) UILabel *statusLabel;
+ (instancetype)sharedInstance;
- (void)showVerifyWindowIfNeeded;
- (void)hideVerifyWindow;
@end

@implementation VoneVerifyManager

+ (instancetype)sharedInstance {
    static VoneVerifyManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VoneVerifyManager alloc] init];
    });
    return instance;
}

- (void)showVerifyWindowIfNeeded {
    // 如果已经激活过，直接返回
    if ([[NSUserDefaults standardUserDefaults] boolForKey:PREFS_STATUS]) {
        return;
    }

    // 如果窗口已经存在，就不要重复创建了
    if (_verifyWindow) {
        return;
    }

    // 1. 创建全屏遮罩层
    _verifyWindow = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _verifyWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4]; // 半透明黑色背景
    _verifyWindow.tag = 9999;

    // 2. 创建弹窗主体 (模拟原生 UIAlertController 样式)
    CGFloat width = 270;
    CGFloat height = 180; // 初始高度
    UIView *alertView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    alertView.center = CGPointMake([UIScreen mainScreen].bounds.size.width / 2, [UIScreen mainScreen].bounds.size.height / 2);
    alertView.backgroundColor = [UIColor colorWithRed:0.96 green:0.96 blue:0.96 alpha:1.0]; // 原生灰白色
    alertView.layer.cornerRadius = 14;
    alertView.clipsToBounds = YES;
    alertView.tag = 100;

    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, width, 30)];
    titleLabel.text = @"Vone 激活验证";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    titleLabel.textColor = [UIColor blackColor];
    [alertView addSubview:titleLabel];

    // 输入框
    _codeField = [[UITextField alloc] initWithFrame:CGRectMake(15, 50, width - 30, 35)];
    _codeField.placeholder = @"请输入激活码...";
    _codeField.borderStyle = UITextBorderStyleRoundedRect;
    _codeField.keyboardType = UIKeyboardTypeAlphabet; // 假设激活码包含字母
    _codeField.clearButtonMode = UITextFieldViewModeWhileEditing;
    [alertView addSubview:_codeField];

    // 状态提示 Label (用于显示“不能为空”或“验证失败”)
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 90, width, 20)];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.font = [UIFont systemFontOfSize:13];
    _statusLabel.textColor = [UIColor redColor];
    _statusLabel.text = @"";
    [alertView addSubview:_statusLabel];

    // 验证按钮
    _verifyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _verifyBtn.frame = CGRectMake(0, 120, width, 44);
    [_verifyBtn setTitle:@"立即验证" forState:UIControlStateNormal];
    _verifyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [_verifyBtn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    [_verifyBtn addTarget:self action:@selector(didTapVerify) forControlEvents:UIControlEventTouchUpInside];
    [alertView addSubview:_verifyBtn];

    // 分割线 (模拟原生样式)
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 119, width, 1)];
    line.backgroundColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:0.5];
    [alertView addSubview:line];

    [_verifyWindow addSubview:alertView];

    // 添加到 KeyWindow
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow && @available(iOS 13.0, *)) {
         for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
             if (scene.activationState == UISceneActivationStateForegroundActive) {
                 keyWindow = scene.windows.firstObject;
                 break;
             }
         }
    }

    if (keyWindow) {
        [keyWindow addSubview:_verifyWindow];
    }
}

// 点击验证按钮的逻辑
- (void)didTapVerify {
    NSString *code = _codeField.text;

    // 1. 判空逻辑 (不关闭窗口)
    if (code.length == 0) {
        _statusLabel.text = @"激活码不能为空！";
        // 简单的震动反馈 (可选，这里为了稳定先不加 AudioToolbox)
        return;
    }

    // 2. 锁定界面，防止重复点击
    _verifyBtn.enabled = NO;
    _verifyBtn.alpha = 0.5;
    _verifyBtn.titleLabel.text = @"验证中...";
    _statusLabel.text = @"";

    // 3. 发起网络请求
    NSString *urlString = [NSString stringWithFormat:@"%@?code=%@", VERIFY_API_URL, code];
    NSURL *url = [NSURL URLWithString:urlString];

    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // 恢复按钮状态
            _verifyBtn.enabled = YES;
            _verifyBtn.alpha = 1.0;
            [_verifyBtn setTitle:@"立即验证" forState:UIControlStateNormal];

            BOOL isSuccess = NO;

            if (!error && data) {
                NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                // 假设服务器返回 "ok" 或者 "success" 代表成功，根据你的实际接口调整
                if ([result.lowercaseString containsString:@"ok"] || [result.lowercaseString containsString:@"success"]) {
                    isSuccess = YES;
                }
            }

            if (isSuccess) {
                // === 验证成功 ===
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:PREFS_STATUS];
                [[NSUserDefaults standardUserDefaults] setObject:code forKey:PREFS_KEY];
                [[NSUserDefaults standardUserDefaults] synchronize];

                // 显示成功提示
                _statusLabel.textColor = [UIColor systemGreenColor];
                _statusLabel.text = @"验证成功，即将进入...";

                // 延迟 1 秒后移除窗口
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self hideVerifyWindow];
                });

            } else {
                // === 验证失败 (窗口保留) ===
                _statusLabel.textColor = [UIColor redColor];
                _statusLabel.text = @"激活码错误或已失效，请重试";
            }
        });
    }] resume];
}

// 移除窗口
- (void)hideVerifyWindow {
    if (_verifyWindow) {
        [_verifyWindow removeFromSuperview];
        _verifyWindow = nil;
    }
}

@end

// === Hook 微信启动入口 ===
%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    // 延迟 0.5 秒弹出，等待微信界面初始化
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[VoneVerifyManager sharedInstance] showVerifyWindowIfNeeded];
    });

    return YES;
}

%end
