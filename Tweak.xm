#import <UIKit/UIKit.h>
#include <dlfcn.h>
#import <objc/runtime.h>

// === 配置区域 ===
#define VERIFY_API_URL @"https://vonekeji.cn/verify.php"
#define PREFS_KEY      @"vone_activation_code"
#define PREFS_STATUS   @"vone_is_activated"
#define ALERT_TAG      9999
#define INPUT_TAG      100
#define DEVICE_UUID_KEY @"vone_device_uuid"

@interface MicroMessengerAppDelegate : UIResponder <UIApplicationDelegate>
@end

UIViewController *TopMostViewController() {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                window = scene.keyWindow;
                break;
            }
        }
    } else {
        window = [UIApplication sharedApplication].keyWindow;
    }

    UIViewController *topVC = window.rootViewController;
    while (YES) {
        if ([topVC isKindOfClass:[UINavigationController class]]) {
            topVC = [(UINavigationController *)topVC topViewController];
        } else if ([topVC isKindOfClass:[UITabBarController class]]) {
            topVC = [(UITabBarController *)topVC selectedViewController];
        } else if (topVC.presentedViewController) {
            topVC = topVC.presentedViewController;
        } else {
            break;
        }
    }
    return topVC;
}

// 获取设备唯一UUID（用于设备绑定）
- (NSString *)getDeviceUniqueUUID {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *uuid = [defaults stringForKey:DEVICE_UUID_KEY];
    if (!uuid || uuid.length == 0) {
        uuid = [[UIDevice currentDevice].identifierForVendor UUIDString];
        [defaults setObject:uuid forKey:DEVICE_UUID_KEY];
        [defaults synchronize];
    }
    return uuid;
}

@interface VoneVerifyManager : NSObject
+ (instancetype)sharedInstance;
// 启动全局校验入口
- (void)startGlobalAppVerify;
- (void)showInputCodeAlert;
- (void)dismissVerificationWindow;
@end

@implementation VoneVerifyManager
{
    NSURLSessionDataTask *_verifyTask;
    BOOL _isShowingAlert;
}

+ (instancetype)sharedInstance {
    static VoneVerifyManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (NSString *)getDeviceUniqueUUID {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *uuid = [defaults stringForKey:DEVICE_UUID_KEY];
    if (!uuid || uuid.length == 0) {
        uuid = [[UIDevice currentDevice].identifierForVendor UUIDString];
        [defaults setObject:uuid forKey:DEVICE_UUID_KEY];
        [defaults synchronize];
    }
    return uuid;
}

#pragma mark - 全局启动校验（每次APP重启都会执行）
- (void)startGlobalAppVerify {
    // 防止弹窗重复叠加
    if (_isShowingAlert) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *localSavedCode = [defaults stringForKey:PREFS_KEY];
    
    // 本地没有存储激活码，直接弹出输入框
    if (!localSavedCode || localSavedCode.length == 0) {
        [self showInputCodeAlert];
        return;
    }
    
    // 本地有码，联网二次校验有效性 + 设备绑定
    [self sendFullVerifyRequestWithCode:localSavedCode completion:^(NSInteger retCode) {
        switch (retCode) {
            case 1:
                // 校验通过：展示欢迎提示，自动关闭，正常使用APP
                [self showWelcomeToast];
                break;
            case 2:
                // 该激活码已绑定其他设备，清空本地记录，强制弹窗输入
                [self clearLocalActivateData];
                [self showTipAlertWithTitle:@"提示" message:@"该激活码已被其他设备使用，请重新输入激活码" complete:^{
                    [self showInputCodeAlert];
                }];
                break;
            case 0:
            default:
                // 激活码失效、错误，清空本地记录，强制弹窗
                [self clearLocalActivateData];
                [self showTipAlertWithTitle:@"激活码已失效" message:@"当前保存的激活码验证不通过，请重新输入" complete:^{
                    [self showInputCodeAlert];
                }];
                break;
        }
    }];
}

// 完整网络请求：携带code+设备uuid传给服务端
- (void)sendFullVerifyRequestWithCode:(NSString *)code completion:(void (^)(NSInteger retCode))completion {
    if (_verifyTask && _verifyTask.state == NSURLSessionTaskStateRunning) {
        [_verifyTask cancel];
    }
    
    NSString *deviceId = [self getDeviceUniqueUUID];
    NSString *encodedCode = [code stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSString *encodedDeviceId = [deviceId stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    
    NSString *urlString = [NSString stringWithFormat:@"%@?code=%@&device_id=%@", VERIFY_API_URL, encodedCode, encodedDeviceId];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(0);
        });
        return;
    }
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 10.0;
    
    _verifyTask = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger resultCode = 0;
        if (!error && data) {
            NSError *jsonErr;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
            if (json && !jsonErr) {
                resultCode = [json[@"status"] integerValue];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(resultCode);
        });
    }];
    [_verifyTask resume];
}

// 清除本地全部激活记录
- (void)clearLocalActivateData {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:PREFS_KEY];
    [defaults setBool:NO forKey:PREFS_STATUS];
    [defaults synchronize];
}

// 欢迎提示弹窗，自动消失
- (void)showWelcomeToast {
    UIViewController *topVC = TopMostViewController();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"验证成功" message:@"欢迎使用，正在进入应用" preferredStyle:UIAlertControllerStyleAlert];
    [topVC presentViewController:alert animated:YES completion:nil];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:nil];
    });
}

// 普通提示弹窗
- (void)showTipAlertWithTitle:(NSString *)title message:(NSString *)msg complete:(void(^)(void))complete {
    UIViewController *topVC = TopMostViewController();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        if (complete) complete();
    }];
    [alert addAction:okAction];
    [topVC presentViewController:alert animated:YES completion:nil];
}

// 常驻激活码输入弹窗（无法关闭，必须输入正确激活码）
- (void)showInputCodeAlert {
    if (_isShowingAlert) return;
    _isShowingAlert = YES;
    
    [self dismissVerificationWindow];
    UIViewController *vc = TopMostViewController();
    if (!vc || !vc.view.window) return;

    UIView *overlay = [[UIView alloc] initWithFrame:vc.view.bounds];
    overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    overlay.tag = ALERT_TAG;
    overlay.userInteractionEnabled = YES;
    [vc.view addSubview:overlay];
    
    CGFloat width = 270;
    CGFloat height = 190;
    UIView *alertView = [[UIView alloc] initWithFrame:CGRectMake(
        (vc.view.bounds.size.width - width) / 2,
        (vc.view.bounds.size.height - height) / 2 - 20,
        width, height)];
    alertView.backgroundColor = [UIColor systemBackgroundColor];
    alertView.layer.cornerRadius = 14;
    alertView.clipsToBounds = YES;
    [overlay addSubview:alertView];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, width, 30)];
    titleLabel.text = @"请输入有效激活码";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [alertView addSubview:titleLabel];
    
    UITextField *inputField = [[UITextField alloc] initWithFrame:CGRectMake(15, 60, width - 30, 40)];
    inputField.backgroundColor = [UIColor secondarySystemBackgroundColor];
    inputField.layer.cornerRadius = 8;
    inputField.placeholder = @"激活码";
    inputField.textAlignment = NSTextAlignmentCenter;
    inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    inputField.tag = INPUT_TAG;
    [alertView addSubview:inputField];
    [inputField becomeFirstResponder];
    
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 110, width, 0.5)];
    line.backgroundColor = [UIColor separatorColor];
    [alertView addSubview:line];
    
    UIButton *confirmBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    confirmBtn.frame = CGRectMake(0, 110, width, 80);
    [confirmBtn setTitle:@"提交验证" forState:UIControlStateNormal];
    confirmBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [confirmBtn addTarget:self action:@selector(handleVerifyTap:) forControlEvents:UIControlEventTouchUpInside];
    [alertView addSubview:confirmBtn];
}

- (void)dismissVerificationWindow {
    UIViewController *topVC = TopMostViewController();
    UIView *overlay = [topVC.view viewWithTag:ALERT_TAG];
    if (overlay) {
        [overlay removeFromSuperview];
        _isShowingAlert = NO;
    }
}

- (void)handleVerifyTap:(UIButton *)sender {
    UIView *alertView = sender.superview;
    UITextField *inputField = (UITextField *)[alertView viewWithTag:INPUT_TAG];
    NSString *code = [inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    if (code.length == 0) {
        [sender setTitle:@"激活码不能为空" forState:UIControlStateNormal];
        [sender setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
        return;
    }
    
    sender.enabled = NO;
    [sender setTitle:@"验证中..." forState:UIControlStateNormal];
    [inputField resignFirstResponder];
    
    __weak typeof(self) weakSelf = self;
    [self sendFullVerifyRequestWithCode:code completion:^(NSInteger retCode) {
        sender.enabled = YES;
        switch (retCode) {
            case 1:
            {
                // 验证通过，保存激活码+状态，关闭弹窗
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                [defaults setObject:code forKey:PREFS_KEY];
                [defaults setBool:YES forKey:PREFS_STATUS];
                [defaults synchronize];
                
                [weakSelf dismissVerificationWindow];
                [weakSelf showWelcomeToast];
                break;
            }
            case 2:
            {
                [weakSelf showTipAlertWithTitle:@"绑定异常" message:@"该激活码已被其他设备绑定，无法继续使用" complete:^{
                    // 弹窗关闭后依旧留在输入界面，不能退出
                }];
                [sender setTitle:@"提交验证" forState:UIControlStateNormal];
                inputField.text = @"";
                [inputField becomeFirstResponder];
                break;
            }
            case 0:
            default:
            {
                [sender setTitle:@"激活码无效，重试" forState:UIControlStateNormal];
                [sender setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
                inputField.text = @"";
                [inputField becomeFirstResponder];
                break;
            }
        }
    }];
}

@end

// Hook微信启动，每次启动都执行校验
%hook MicroMessengerAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL origRes = %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[VoneVerifyManager sharedInstance] startGlobalAppVerify];
    });
    return origRes;
}
%end
