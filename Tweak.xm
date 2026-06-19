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
                window = [(UIWindowScene *)scene keyWindow];
                break;
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

// --- 核心验证类 ---
@interface VoneVerifyManager : NSObject
+ (instancetype)sharedInstance;
- (void)showVerificationWindow;
@end

@implementation VoneVerifyManager

+ (instancetype)sharedInstance {
    static VoneVerifyManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

// 发送网络请求
- (void)sendVerifyRequestWithCode:(NSString *)code completion:(void (^)(BOOL success))completion {
    NSString *urlString = [NSString stringWithFormat:@"%@?code=%@", VERIFY_API_URL, code];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"GET"];

    // 修复：使用方括号语法代替点语法
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        BOOL isSuccess = NO;
        if (!error && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json[@"status"] integerValue] == 1) {
                isSuccess = YES;
            }
        }
        // 回到主线程处理 UI
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(isSuccess);
        });
    }];
    [task resume];
}

// 显示自定义弹窗
- (void)showVerificationWindow {
    UIViewController *vc = TopMostViewController();
    if (!vc.view.window) return;

    // 1. 创建遮罩层
    UIView *overlay = [[UIView alloc] initWithFrame:vc.view.bounds];
    overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    overlay.tag = 9999; // 标记以便后续查找移除
    [vc.view addSubview:overlay];

    // 2. 创建弹窗容器 (模拟 iOS 原生 Alert 样式)
    CGFloat width = 270;
    CGFloat height = 180;
    UIView *alertView = [[UIView alloc] initWithFrame:CGRectMake((vc.view.bounds.size.width - width) / 2, (vc.view.bounds.size.height - height) / 2, width, height)];
    alertView.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0]; // 浅灰色背景 #F2F2F7
    alertView.layer.cornerRadius = 14;
    alertView.clipsToBounds = YES;
    [overlay addSubview:alertView];

    // 3. 标题 Label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, width, 30)];
    titleLabel.text = @"Vone 激活验证";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [alertView addSubview:titleLabel];

    // 4. 输入框
    UITextField *inputField = [[UITextField alloc] initWithFrame:CGRectMake(15, 60, width - 30, 40)];
    inputField.backgroundColor = [UIColor whiteColor];
    inputField.layer.cornerRadius = 8;
    inputField.placeholder = @"请输入激活码";
    inputField.textAlignment = NSTextAlignmentCenter;
    inputField.borderStyle = UITextBorderStyleNone;
    inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    [alertView addSubview:inputField];

    // 5. 确认按钮
    UIButton *confirmBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    confirmBtn.frame = CGRectMake(0, 110, width, 50); // 占据底部
    [confirmBtn setTitle:@"立即验证" forState:UIControlStateNormal];
    confirmBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [alertView addSubview:confirmBtn];

    // 分割线 (可选，增加细节)
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 110, width, 0.5)];
    line.backgroundColor = [UIColor colorWithRed:0.78 green:0.78 blue:0.8 alpha:1.0];
    [alertView addSubview:line];

    // 6. 按钮点击逻辑
    __block UIButton *btnRef = confirmBtn;
    __block UIView *alertRef = alertView;
    __block UIView *overlayRef = overlay;

    [confirmBtn addTarget:self action:@selector(handleVerifyTap:) forControlEvents:UIControlEventTouchUpInside];

    // 利用 objc_setAssociatedObject 传递参数（如果不想引入 runtime.h，可以用全局变量或 Block 属性，这里为了简洁直接用 Tag 查找）
    // 为了避开 Runtime 报错，我们直接在 Button 的 Action 里通过 Tag 找父视图
}

// 按钮响应事件
- (void)handleVerifyTap:(UIButton *)sender {
    // 向上查找父视图
    UIView *alertView = sender.superview;
    UIView *overlay = alertView.superview;
    UITextField *inputField = (UITextField *)[alertView viewWithTag:100]; // 需要给 Input 设 Tag
    // 由于上面没设 Tag，我们重新遍历一下或者简单点：
    // 实际上上面的代码里 inputField 没有设 tag，这里修正一下逻辑

    // 重新获取 inputField (它是 alertView 的第二个子视图，index 2)
    UITextField *field = (UITextField *)[alertView.subviews objectAtIndex:2];
    NSString *code = field.text;

    if (code.length == 0) {
        [sender setTitle:@"请输入激活码" forState:UIControlStateNormal];
        [sender setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        return;
    }

    // 正在验证中...
    [sender setTitle:@"验证中..." forState:UIControlStateNormal];
    [sender setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    sender.enabled = NO;

    [self sendVerifyRequestWithCode:code completion:^(BOOL success) {
        sender.enabled = YES;
        if (success) {
            // 验证成功
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:code forKey:PREFS_KEY];
            [defaults setBool:YES forKey:PREFS_STATUS];
            [defaults synchronize];

            // 提示成功并移除窗口
            UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"验证成功" message:@"即将进入微信" preferredStyle:UIAlertControllerStyleAlert];
            [viewController presentViewController:successAlert animated:YES completion:^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [successAlert dismissViewControllerAnimated:YES completion:nil];
                    [overlay removeFromSuperview]; // 彻底移除验证窗口
                });
            }];
        } else {
            // 验证失败
            [sender setTitle:@"激活码错误，重试" forState:UIControlStateNormal];
            [sender setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
            field.text = @""; // 清空输入框
            [field becomeFirstResponder]; // 聚焦输入框
        }
    }];
}

@end

// --- Hook 微信启动 ---
%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isActivated = [defaults boolForKey:PREFS_STATUS];

    if (!isActivated) {
        // 延迟一点弹出，防止遮挡启动图或加载动画
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[VoneVerifyManager sharedInstance] showVerificationWindow];
        });
    }

    return YES;
}

%end
