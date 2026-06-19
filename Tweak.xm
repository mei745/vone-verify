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

@interface VoneVerifyManager : NSObject
+ (instancetype)sharedInstance;
- (void)startGlobalAppVerify;
- (void)showInputCodeAlert;
- (void)dismissVerificationWindow;
- (NSString *)getDeviceUniqueUUID;
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

- (void)startGlobalAppVerify {
    if (_isShowingAlert) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *localSavedCode = [defaults stringForKey:PREFS_KEY];
    
    if (!localSavedCode || localSavedCode.length == 0) {
        [self showInputCodeAlert];
        return;
    }
    
    [self sendFullVerifyRequestWithCode:localSavedCode completion:^(NSInteger retCode) {
        if (retCode == 1) {
            [self showWelcomeToast];
        } else if (retCode == 2) {
            [self clearLocalActivateData];
            [self showTipAlertWithTitle:@"提示" message:@"该激活码已使用，请重新输入" complete:^{
                [self showInputCodeAlert];
            }];
        } else {
            [self clearLocalActivateData];
            [self showTipAlertWithTitle:@"验证失败" message:@"激活码已停用，请重新输入" complete:^{
                [self showInputCodeAlert];
            }];
        }
    }];
}

- (void)sendFullVerifyRequestWithCode:(NSString *)code completion:(void (^)(NSInteger retCode))completion {
    if (_verifyTask && _verifyTask.state == NSURLSessionTaskStateRunning) {
        [_verifyTask cancel];
    }
    
    NSString *deviceId = [self getDeviceUniqueUUID];
    NSString *encodedCode = [code stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *encodedDeviceId = [deviceId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
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

- (void)clearLocalActivateData {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:PREFS_KEY];
    [defaults setBool:NO forKey:PREFS_STATUS];
    [defaults synchronize];
}

- (void)showWelcomeToast {
    UIViewController *topVC = TopMostViewController();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"验证成功" 
                                                                   message:@"欢迎使用" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [topVC presentViewController:alert animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:nil];
    });
}

- (void)showTipAlertWithTitle:(NSString *)title message:(NSString *)msg complete:(void(^)(void))complete {
    UIViewController *topVC = TopMostViewController();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        if (complete) complete();
    }];
    [alert addAction:okAction];
    [topVC presentViewController:alert animated:YES completion:nil];
}

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
    UIView *alertView = [[UIView alloc] initWithFrame:CGRectMake((vc.view.bounds.size.width - width) / 2, (vc.view.bounds.size.height - height) / 2 - 20, width, height)];
    alertView.backgroundColor = [UIColor systemBackgroundColor];
    alertView.layer.cornerRadius = 14;
    alertView.clipsToBounds = YES;
    [overlay addSubview:alertView];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, width, 30)];
    titleLabel.text = @"授权";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [alertView addSubview:titleLabel];
    
    UITextField *inputField = [[UITextField alloc] initWithFrame:CGRectMake(15, 60, width - 30, 40)];
    inputField.backgroundColor = [UIColor secondarySystemBackgroundColor];
    inputField.layer.cornerRadius = 8;
    inputField.placeholder = @"请输入12位激活码";
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
    [confirmBtn setTitle:@"验证" forState:UIControlStateNormal];
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
        [sender setTitle:@"激活码不能为空，请输入" forState:UIControlStateNormal];
        [sender setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
        return;
    }
    
    sender.enabled = NO;
    [sender setTitle:@"验证中..." forState:UIControlStateNormal];
    [inputField resignFirstResponder];
    
    __weak typeof(self) weakSelf = self;
    [self sendFullVerifyRequestWithCode:code completion:^(NSInteger retCode) {
        sender.enabled = YES;
        if (retCode == 1) {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:code forKey:PREFS_KEY];
            [defaults setBool:YES forKey:PREFS_STATUS];
            [defaults synchronize];
            
            [weakSelf dismissVerificationWindow];
            [weakSelf showWelcomeToast];
        } else if (retCode == 2) {
            [weakSelf showTipAlertWithTitle:@"验证失败" message:@"该激活码已使用，请重新输入" complete:^{
            }];
            [sender setTitle:@"验证" forState:UIControlStateNormal];
            inputField.text = @"";
            [inputField becomeFirstResponder];
        } else {
            [sender setTitle:@"激活码不存在，请检查后重试" forState:UIControlStateNormal];
            [sender setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
            inputField.text = @"";
            [inputField becomeFirstResponder];
        }
    }];
}

@end

%hook MicroMessengerAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL origRes = %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[VoneVerifyManager sharedInstance] startGlobalAppVerify];
    });
    return origRes;
}
%end
