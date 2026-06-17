#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// --- 配置区 ---
#define SERVER_URL @"https://vonekeji.cn/verify.php"

// --- 全局变量 ---
static BOOL isVerified = NO;
static UIWindow *blockWindow = nil;

// 获取设备唯一标识
NSString* getDeviceUUID() {
    return [[UIDevice currentDevice] identifierForVendor].UUIDString;
}

// --- 自定义弹窗视图类 ---
@interface ActivationView : UIView <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *verifyBtn;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation ActivationView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];

        // 卡片容器
        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [UIColor whiteColor];
        card.layer.cornerRadius = 14.0;
        card.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:card];

        // 标题
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = @"温馨提示";
        titleLabel.font = [UIFont boldSystemFontOfSize:17];
        titleLabel.textColor = [UIColor blackColor];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:titleLabel];

        // 副标题
        UILabel *subLabel = [[UILabel alloc] init];
        subLabel.text = @"请输入激活码";
        subLabel.font = [UIFont systemFontOfSize:14];
        subLabel.textColor = [UIColor darkGrayColor];
        subLabel.textAlignment = NSTextAlignmentCenter;
        subLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:subLabel];

        // 输入框
        _inputField = [[UITextField alloc] init];
        _inputField.placeholder = @"请输入激活码";
        _inputField.borderStyle = UITextBorderStyleRoundedRect;
        _inputField.font = [UIFont systemFontOfSize:15];
        _inputField.clearButtonMode = UITextFieldViewModeWhileEditing;
        _inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _inputField.delegate = self;
        _inputField.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:_inputField];

        // 分割线
        UIView *line = [[UIView alloc] init];
        line.backgroundColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0];
        line.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:line];

        // 按钮
        _verifyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [_verifyBtn setTitle:@"验证" forState:UIControlStateNormal];
        _verifyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
        [_verifyBtn addTarget:self action:@selector(handleVerify) forControlEvents:UIControlEventTouchUpInside];
        _verifyBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:_verifyBtn];

        // 状态提示
        _statusLabel = [[UILabel alloc] init];
        _statusLabel.font = [UIFont systemFontOfSize:12];
        _statusLabel.textColor = [UIColor redColor];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.alpha = 0;
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:_statusLabel];

        // 布局约束 (已修复 Theos 兼容性问题)
        [NSLayoutConstraint activateConstraints:@[
            [card centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [card centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [card widthAnchor constraintEqualToConstant:270],

            [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
            [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],

            [subLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
            [subLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [subLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],

            [_inputField.topAnchor constraintEqualToAnchor:subLabel.bottomAnchor constant:15],
            [_inputField.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:15],
            [_inputField.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-15],
            [_inputField.heightAnchor constraintEqualToConstant:36],

            [line.topAnchor constraintEqualToAnchor:_inputField.bottomAnchor constant:15],
            [line.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [line.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
            [line.heightAnchor constraintEqualToConstant:0.5],

            [_verifyBtn.topAnchor constraintEqualToAnchor:line.bottomAnchor],
            [_verifyBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [_verifyBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
            [_verifyBtn.heightAnchor constraintEqualToConstant:44],
            [_verifyBtn.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

            [_statusLabel.topAnchor constraintEqualToAnchor:_inputField.bottomAnchor constant:5],
            [_statusLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:15],
            [_statusLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-15],
        ]];
    }
    return self;
}

- (void)handleVerify {
    [self.inputField resignFirstResponder];
    NSString *code = self.inputField.text;

    if (code.length == 0) {
        [self showError:@"请输入激活码"];
        return;
    }

    // UI 状态更新
    self.verifyBtn.enabled = NO;
    self.verifyBtn.alpha = 0.5;
    [self.verifyBtn setTitle:@"验证中..." forState:UIControlStateNormal];

    // 【关键修改】使用 NSURLSession + 信号量 实现伪同步请求
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *deviceID = getDeviceUUID();
        NSString *urlString = [NSString stringWithFormat:@"%@?code=%@&uuid=%@", SERVER_URL, code, deviceID];
        NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        [request setTimeoutInterval:15.0];
        [request setValue:@"VoneVerify/1.0" forHTTPHeaderField:@"User-Agent"];

        // 定义信号量
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        // 必须加 __block 才能在这个 block 内部修改它们
        __block NSData *responseData = nil;
        __block NSError *taskError = nil;

        [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            responseData = data;
            taskError = error;
            // 任务完成，释放信号量，让下面的 wait 继续执行
            dispatch_semaphore_signal(semaphore);
        }] resume];

        // 等待网络请求完成 (最多等 20 秒)
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20.0 * NSEC_PER_SEC)));

        // 回到主线程处理结果
        dispatch_async(dispatch_get_main_queue(), ^{
            // 恢复 UI
            self.verifyBtn.enabled = YES;
            self.verifyBtn.alpha = 1.0;
            [self.verifyBtn setTitle:@"验证" forState:UIControlStateNormal];

            if (taskError) {
                NSLog(@"[VoneVerify] 网络请求失败: %@", taskError.localizedDescription);
                [self showError:@"网络连接超时或失败"];
                return;
            }

            if (!responseData) {
                [self showError:@"服务器无响应"];
                return;
            }

            NSString *result = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
            NSLog(@"[VoneVerify] 服务器返回: %@", result);

            NSString *cleanResult = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

            if ([cleanResult isEqualToString:@"ok"]) {
                isVerified = YES;
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Vone_Is_Activated"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                [self removeFromSuperview];
            } else {
                [self showError:@"激活码无效或已过期"];
                self.inputField.text = @"";
                [self.inputField becomeFirstResponder];
            }
        });
    });
}

- (void)showError:(NSString *)msg {
    self.statusLabel.text = msg;
    self.statusLabel.alpha = 1.0;
    [UIView animateWithDuration:0.3 delay:2.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.statusLabel.alpha = 0;
    } completion:nil];
}

@end

// --- Hook 入口 ---
%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL ret = %orig;

    // 检查是否已激活
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"Vone_Is_Activated"]) {
        blockWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        blockWindow.windowLevel = UIWindowLevelAlert + 1;
        blockWindow.backgroundColor = [UIColor clearColor];

        ActivationView *alertView = [[ActivationView alloc] initWithFrame:blockWindow.bounds];
        [blockWindow addSubview:alertView];
        [blockWindow makeKeyAndVisible];
    }
    return ret;
}
%end

// 拦截侧滑返回
%hook UINavigationController
- (BOOL)navigationBar:(UINavigationBar *)navigationBar shouldPopItem:(UINavigationItem *)item {
    if (!isVerified && blockWindow) {
        return NO;
    }
    return %orig;
}
%end
