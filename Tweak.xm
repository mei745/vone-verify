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
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                window = ((UIWindowScene *)scene).windows.firstObject;
                break;
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

// --- 核心逻辑类：自定义验证弹窗 ---
@interface VoneVerifyManager : NSObject
+ (void)showVerifyWindowIfNeeded;
@end

@implementation VoneVerifyManager

// 网络请求封装
+ (void)requestVerifyWithCode:(NSString *)code completion:(void (^)(BOOL success, NSString *msg))completion {
    NSURL *url = [NSURL URLWithString:VERIFY_API_URL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = [NSString stringWithFormat:@"code=%@", code].dataUsingEncoding:NSUTF8StringEncoding;
    req.timeoutInterval = 10;

    [NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"网络请求失败");
            });
            return;
        }

        // 简单的解析逻辑，根据你的PHP接口返回调整
        // 假设返回 JSON: {"status": 1, "msg": "ok"} 或 {"status": 0, "msg": "invalid"}
        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

        BOOL isSuccess = NO;
        NSString *message = @"未知错误";

        if (!jsonError && json) {
            // 这里根据你实际的API返回值修改判断条件
            // 比如有的接口是 status=1，有的是 code=200
            if ([json[@"status"] integerValue] == 1 || [json[@"code"] integerValue] == 200) {
                isSuccess = YES;
                message = @"激活成功";
            } else {
                message = json[@"msg"] ?: @"激活码无效";
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(isSuccess, message);
        });
    }] resume];
}

+ (void)showVerifyWindowIfNeeded {
    // 检查是否已经激活
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:PREFS_STATUS]) {
        return; // 已激活，直接放行
    }

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

    if (!mainWindow) return;

    // 创建覆盖层 View (模拟 UIAlertController 样式)
    UIView *overlay = [[UIView alloc] initWithFrame:mainWindow.bounds];
    overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4]; // 半透明黑色背景
    overlay.tag = 9999; // 标记以便查找

    // 弹窗容器 (浅灰色背景)
    CGFloat width = 270;
    CGFloat height = 180; // 稍微高一点容纳输入框
    UIView *alertView = [[UIView alloc] initWithFrame:CGRectMake((mainWindow.bounds.size.width - width) / 2, (mainWindow.bounds.size.height - height) / 2, width, height)];
    alertView.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0]; // iOS 系统灰 #F2F2F7
    alertView.layer.cornerRadius = 14;
    alertView.clipsToBounds = YES;
    [overlay addSubview:alertView];

    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, width, 30)];
    titleLabel.text = @"Vone 激活验证";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    titleLabel.textColor = [UIColor blackColor];
    [alertView addSubview:titleLabel];

    // 输入框
    UITextField *inputField = [[UITextField alloc] initWithFrame:CGRectMake(15, 60, width - 30, 30)];
    inputField.placeholder = @"请输入激活码";
    inputField.borderStyle = UITextBorderStyleRoundedRect;
    inputField.keyboardType = UIKeyboardTypeAlphabet; // 或者是 NumberPad，看你的码类型
    inputField.clearButtonMode = UITextFieldViewModeWhileEditing;
    inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [alertView addSubview:inputField];

    // 分割线 (视觉装饰)
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 105, width, 0.5)];
    line.backgroundColor = [UIColor colorWithRed:0.78 green:0.78 blue:0.8 alpha:1.0];
    [alertView addSubview:line];

    // 确认按钮
    UIButton *confirmBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    confirmBtn.frame = CGRectMake(0, 105, width, 75); // 占据下半部分
    [confirmBtn setTitle:@"立即验证" forState:UIControlStateNormal];
    confirmBtn.titleLabel.font = [UIFont systemFontOfSize:17];
    [alertView addSubview:confirmBtn];

    // 点击空白处不做处理，强制用户操作
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ignoreTap)];
    [overlay addGestureRecognizer:tap];

    // 按钮点击事件
    __block UIView *currentOverlay = overlay;
    __block UIButton *currentBtn = confirmBtn;
    __block UITextField *currentInput = inputField;

    [confirmBtn addTarget:self action:@selector(handleVerifyClick:) forControlEvents:UIControlEventTouchUpInside];

    // 利用 Associated Object 传递上下文变量 (为了在静态方法里访问局部变量)
    objc_setAssociatedObject(confirmBtn, "overlay", overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(confirmBtn, "input", inputField, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [mainWindow addSubview:overlay];
}

// 忽略背景点击
+ (void)ignoreTap {}

// 验证按钮点击处理
+ (void)handleVerifyClick:(UIButton *)sender {
    UIView *overlay = objc_getAssociatedObject(sender, "overlay");
    UITextField *input = objc_getAssociatedObject(sender, "input");

    NSString *code = input.text;

    // 1. 判空逻辑
    if (code.length == 0) {
        // 简单的震动反馈
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        // 改变按钮文字提示错误，但不关闭窗口
        [sender setTitle:@"激活码不能为空！" forState:UIControlStateNormal];
        [sender setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        return; // 直接返回，窗口保留
    }

    // 2. Loading 状态
    sender.enabled = NO;
    [sender setTitle:@"验证中..." forState:UIControlStateNormal];
    [sender setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];

    // 3. 发起网络请求
    [self requestVerifyWithCode:code completion:^(BOOL success, NSString *msg) {
        if (success) {
            // --- 验证成功逻辑 ---
            // 保存状态
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setBool:YES forKey:PREFS_STATUS];
            [defaults setObject:code forKey:PREFS_KEY];
            [defaults synchronize];

            // 显示成功提示 (可选，或者直接消失)
            UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"提示" message:@"激活成功，欢迎使用！" preferredStyle:UIAlertControllerStyleAlert];
            [successAlert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                // 点击“好的”后，彻底移除验证窗口
                [overlay removeFromSuperview];
            }]];

            // 注意：这里需要获取当前的 TopVC 来弹成功提示
            UIViewController *vc = TopMostViewController();
            [vc presentViewController:successAlert animated:YES completion:nil];

        } else {
            // --- 验证失败逻辑 ---
            sender.enabled = YES;
            [sender setTitle:@"重试" forState:UIControlStateNormal];
            [sender setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];

            // 弹窗提示错误，但不关闭主验证窗口
            UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"验证失败" message:msg preferredStyle:UIAlertControllerStyleAlert];
            [errorAlert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:nil]]; // 点击重试只是关掉小弹窗，大窗口还在

            UIViewController *vc = TopMostViewController();
            [vc presentViewController:errorAlert animated:YES completion:nil];
        }
    }];
}

@end

// === Hook 微信启动逻辑 ===
%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    // 延迟一点执行，确保界面加载完毕
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [VoneVerifyManager showVerifyWindowIfNeeded];
    });

    return YES;
}

%end
