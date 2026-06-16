#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// --- 配置区 ---
#define SERVER_URL @"https://vonekeji.cn/verify.php" // 【重要】请替换为你的实际API地址

// --- 全局变量 ---
static BOOL isVerified = NO;
static UIWindow *blockWindow = nil;

// 获取设备唯一标识 (UUID)
NSString* getDeviceUUID() {
    NSString *uuid = [[UIDevice currentDevice] identifierForVendor].UUIDString;
    return uuid;
}

// 发送网络请求验证卡密
BOOL verifyCode(NSString *code) {
    NSString *deviceID = getDeviceUUID();
    NSString *urlString = [NSString stringWithFormat:@"%@?code=%@&uuid=%@", SERVER_URL, code, deviceID];
    NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setTimeoutInterval:10.0]; // 超时时间10秒

    NSHTTPURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];

    if (!data || error) {
        return NO; // 网络错误或超时
    }

    NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    // 假设后台返回 "ok" 代表验证成功，其他均为失败
    if ([result isEqualToString:@"ok"]) {
        return YES;
    }
    return NO;
}

// --- 自定义弹窗视图类 (复刻图片风格) ---
@interface ActivationView : UIView <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *verifyBtn;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation ActivationView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5]; // 半透明背景遮罩

        // 1. 白色圆角卡片容器
        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [UIColor whiteColor];
        card.layer.cornerRadius = 14.0;
        card.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:card];

        // 2. 标题 "温馨提示"
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = @"温馨提示";
        titleLabel.font = [UIFont boldSystemFontOfSize:17];
        titleLabel.textColor = [UIColor blackColor];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:titleLabel];

        // 3. 副标题 "请输入激活码"
        UILabel *subLabel = [[UILabel alloc] init];
        subLabel.text = @"请输入激活码";
        subLabel.font = [UIFont systemFontOfSize:14];
        subLabel.textColor = [UIColor darkGrayColor];
        subLabel.textAlignment = NSTextAlignmentCenter;
        subLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:subLabel];

        // 4. 输入框 (带灰色边框)
        _inputField = [[UITextField alloc] init];
        _inputField.placeholder = @"请输入激活码";
        _inputField.borderStyle = UITextBorderStyleRoundedRect; // 圆角风格
        _inputField.font = [UIFont systemFontOfSize:15];
        _inputField.clearButtonMode = UITextFieldViewModeWhileEditing;
        _inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _inputField.delegate = self;
        _inputField.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:_inputField];

        // 5. 分割线 (模拟iOS Alert风格)
        UIView *line = [[UIView alloc] init];
        line.backgroundColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0];
        line.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:line];

        // 6. 验证按钮 (底部蓝色文字)
        _verifyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [_verifyBtn setTitle:@"验证" forState:UIControlStateNormal];
        _verifyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
        [_verifyBtn addTarget:self action:@selector(handleVerify) forControlEvents:UIControlEventTouchUpInside];
        _verifyBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:_verifyBtn];

        // 7. 状态提示标签 (用于显示"卡密错误"等)
        _statusLabel = [[UILabel alloc] init];
        _statusLabel.font = [UIFont systemFontOfSize:12];
        _statusLabel.textColor = [UIColor redColor];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.alpha = 0; // 默认隐藏
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:_statusLabel];

        // --- 布局约束 (Auto Layout) ---
        [NSLayoutConstraint activateConstraints:@[
            // 卡片居中，宽度固定
            [card centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [card centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [card widthAnchor constraintEqualToConstant:270],

            // 标题位置
            [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
            [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],

            // 副标题
            [subLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
            [subLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [subLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],

            // 输入框
            [_inputField.topAnchor constraintEqualToAnchor:subLabel.bottomAnchor constant:15],
            [_inputField.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:15],
            [_inputField.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-15],
            [_inputField.heightAnchor constraintEqualToConstant:36],

            // 分割线
            [line.topAnchor constraintEqualToAnchor:_inputField.bottomAnchor constant:15],
            [line.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [line.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
            [line.heightAnchor constraintEqualToConstant:0.5],

            // 按钮
            [_verifyBtn.topAnchor constraintEqualToAnchor:line.bottomAnchor],
            [_verifyBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [_verifyBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
            [_verifyBtn.heightAnchor constraintEqualToConstant:44],
            [_verifyBtn.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

            // 错误提示 (位于输入框下方)
            [_statusLabel.topAnchor constraintEqualToAnchor:_inputField.bottomAnchor constant:5],
            [_statusLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:15],
            [_statusLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-15],
        ]];
    }
    return self;
}

- (void)handleVerify {
    [self.inputField resignFirstResponder]; // 收起键盘
    NSString *code = self.inputField.text;

    if (code.length == 0) {
        [self showError:@"请输入激活码"];
        return;
    }

    // 显示加载中...
    self.verifyBtn.enabled = NO;
    self.verifyBtn.alpha = 0.5;
    self.verifyBtn.titleLabel.text = @"验证中...";

    // 异步执行网络请求，防止卡死UI
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL success = verifyCode(code);

        dispatch_async(dispatch_get_main_queue(), ^{
            self.verifyBtn.enabled = YES;
            self.verifyBtn.alpha = 1.0;
            [self.verifyBtn setTitle:@"验证" forState:UIControlStateNormal];

            if (success) {
                // 验证成功：保存状态并移除弹窗
                isVerified = YES;
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Vone_Is_Activated"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                [self removeFromSuperview]; // 移除自己
            } else {
                // 验证失败：显示错误提示
                [self showError:@"激活码无效或已过期"];
                self.inputField.text = @""; // 清空输入框
                [self.inputField becomeFirstResponder]; // 重新唤起键盘
            }
        });
    });
}

- (void)showError:(NSString *)msg {
    self.statusLabel.text = msg;
    self.statusLabel.alpha = 1.0;
    // 2秒后自动消失
    [UIView animateWithDuration:0.3 delay:2.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.statusLabel.alpha = 0;
    } completion:nil];
}

@end

// --- Hook 微信入口 ---
%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL ret = %orig;

    // 检查是否已经激活过 (可选：如果想每次启动都验证，删掉这个if判断)
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"Vone_Is_Activated"]) {

        // 创建全屏覆盖层
        blockWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        blockWindow.windowLevel = UIWindowLevelAlert + 1; // 层级最高，盖住一切
        blockWindow.backgroundColor = [UIColor clearColor];

        ActivationView *alertView = [[ActivationView alloc] initWithFrame:blockWindow.bounds];
        [blockWindow addSubview:alertView];

        [blockWindow makeKeyAndVisible]; // 强制显示
    }

    return ret;
}

%end

// 拦截返回手势，防止用户通过侧滑退出App来绕过验证
%hook UINavigationController
- (BOOL)navigationBar:(UINavigationBar *)navigationBar shouldPopItem:(UINavigationItem *)item {
    if (!isVerified && blockWindow) {
        // 如果没验证且弹窗还在，禁止返回
        return NO;
    }
    return %orig;
}
%end
