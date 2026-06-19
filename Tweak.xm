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

    // 修复 @available 编译报错：必须独立使用 if 语句块
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

    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    return rootVC;
}

// --- 核心验证类 ---
@interface VoneVerifyManager : NSObject
+ (void)showVerifyWindow;
@end

@implementation VoneVerifyManager

+ (void)showVerifyWindow {
    // 如果已经验证过，直接返回
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:PREFS_STATUS]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = TopMostViewController();

        // 创建全屏遮罩层
        UIView *overlay = [[UIView alloc] initWithFrame:vc.view.bounds];
        overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        overlay.tag = 9999; // 标记以便后续查找
        [vc.view addSubview:overlay];

        // 创建弹窗容器 (模拟 UIAlertController 风格)
        CGFloat width = 270;
        CGFloat height = 180;
        UIView *alertView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
        alertView.center = vc.view.center;
        alertView.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0]; // 浅灰背景
        alertView.layer.cornerRadius = 14;
        alertView.clipsToBounds = YES;
        [overlay addSubview:alertView];

        // 标题
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, width, 30)];
        titleLabel.text = @"Vone 激活验证";
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.font = [UIFont boldSystemFontOfSize:17];
        [alertView addSubview:titleLabel];

        // 输入框
        UITextField *inputField = [[UITextField alloc] initWithFrame:CGRectMake(15, 60, width - 30, 35)];
        inputField.placeholder = @"请输入激活码";
        inputField.backgroundColor = [UIColor whiteColor];
        inputField.layer.cornerRadius = 8;
        inputField.clearButtonMode = UITextFieldViewModeWhileEditing;
        inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        inputField.autocorrectionType = UITextAutocorrectionTypeNo;
        inputField.borderStyle = UITextBorderStyleNone;
        inputField.textAlignment = NSTextAlignmentCenter;
        [alertView addSubview:inputField];

        // 确认按钮
        UIButton *confirmBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        confirmBtn.frame = CGRectMake(15, 110, width - 30, 40);
        [confirmBtn setTitle:@"立即验证" forState:UIControlStateNormal];
        confirmBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        confirmBtn.backgroundColor = [UIColor systemBlueColor];
        confirmBtn.layer.cornerRadius = 8;
        [confirmBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [alertView addSubview:confirmBtn];

        // 使用 Tag 来传递数据，避免 Runtime 报错
        overlay.tag = 1001;
        confirmBtn.tag = 1002;
        inputField.tag = 1003;

        // 按钮点击事件
        [confirmBtn addTarget:self action:@selector(handleVerifyClick:) forControlEvents:UIControlEventTouchUpInside];
    });
}

+ (void)handleVerifyClick:(UIButton *)sender {
    // 通过层级关系找到输入框和遮罩层
    UIView *alertView = sender.superview;
    UITextField *inputField = [alertView viewWithTag:1003];
    UIView *overlay = alertView.superview;
    NSString *code = [inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (code.length == 0) {
        [sender setTitle:@"请输入激活码" forState:UIControlStateNormal];
        [sender setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        return;
    }

    [sender setTitle:@"验证中..." forState:UIControlStateNormal];
    sender.enabled = NO;

    // 发起网络请求
    NSURL *url = [NSURL URLWithString:VERIFY_API_URL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = [[NSString stringWithFormat:@"code=%@", code] dataUsingEncoding:NSUTF8StringEncoding];

    [NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            sender.enabled = YES;

            BOOL isSuccess = NO;
            if (!error && data) {
                NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                // 假设服务器返回 "success" 表示验证通过
                if ([result.lowercaseString containsString:@"success"]) {
                    isSuccess = YES;
                }
            }

            if (isSuccess) {
                // 验证成功：保存状态
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                [defaults setBool:YES forKey:PREFS_STATUS];
                [defaults setObject:code forKey:PREFS_KEY];
                [defaults synchronize];

                // 移除遮罩层
                [overlay removeFromSuperview];
            } else {
                // 验证失败：提示错误，但不移除窗口
                [sender setTitle:@"激活码错误，请重试" forState:UIControlStateNormal];
                [sender setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
            }
        });
    }] resume];
}

@end

// --- Hook 微信启动 ---
%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    // 延迟一点弹出，防止影响微信初始化动画
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [VoneVerifyManager showVerifyWindow];
    });

    return YES;
}

%end
