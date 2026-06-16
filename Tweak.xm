#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// --- 配置区 ---
#define SERVER_URL @"https://vonekeji.cn/verify.php" 

// --- 全局变量 ---
static BOOL isVerified = NO;
static UIWindow *blockWindow = nil;

// 获取设备唯一标识 (UUID)
NSString* getDeviceUUID() {
    NSString *uuid = [[UIDevice currentDevice] identifierForVendor].UUIDString;
    return uuid;
}

// 辅助函数：清理字符串（去除HTML标签、空格、换行）
NSString* cleanString(NSString *str) {
    if (!str) return @"";
    // 1. 去除首尾空白字符和换行符
    str = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // 2. 简单去除 HTML 标签 (处理 <br>, <p> 等)
    // 注意：这只是一个简单的正则，能处理大部分 PHP echo 输出的情况
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>" options:0 error:&error];
    if (error) return str;
    str = [regex stringByReplacingMatchesInString:str options:0 range:NSMakeRange(0, [str length]) withTemplate:@""];
    return [str lowercaseString]; // 转为小写，防止 "OK" 和 "ok" 不匹配
}

// 发送网络请求验证卡密 (增强版)
BOOL verifyCode(NSString *code) {
    NSString *deviceID = getDeviceUUID();
    NSString *urlString = [NSString stringWithFormat:@"%@?code=%@&uuid=%@", SERVER_URL, code, deviceID];
    
    // 确保 URL 编码正确
    NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    if (!url) {
        NSLog(@"[VoneVerify] Invalid URL: %@", urlString);
        return NO;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setTimeoutInterval:15.0];
    [request setHTTPMethod:@"GET"];
    
    // 重要：添加 User-Agent，防止服务器防火墙拦截
    [request setValue:@"VoneVerify/1.0" forHTTPHeaderField:@"User-Agent"];

    NSHTTPURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];

    // --- 调试日志 ---
    if (error) {
        NSLog(@"[VoneVerify] Request Failed: %@", [error localizedDescription]);
        return NO;
    }
    
    if (!data || [data length] == 0) {
        NSLog(@"[VoneVerify] No data received from server");
        return NO;
    }
    // --- 调试日志 ---

    // 将数据转为字符串
    NSString *rawResult = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!rawResult) {
        NSLog(@"[VoneVerify] Failed to parse response data");
        return NO;
    }

    // 关键优化：清理字符串
    NSString *cleanedResult = cleanString(rawResult);
    
    // 打印清理后的结果，方便你在 syslog 中查看到底返回了什么
    NSLog(@"[VoneVerify] Raw Response: '%@'", rawResult);
    NSLog(@"[VoneVerify] Cleaned Response: '%@'", cleanedResult);

    // 判断是否包含 "ok" (不区分大小写，且允许前后有空格或HTML)
    if ([cleanedResult rangeOfString:@"ok"].location != NSNotFound) {
        return YES;
    }
    
    // 如果后端返回的是 JSON 格式，例如 {"msg": "ok"}，上面的判断也能捕获到
    // 如果需要严格的 JSON 解析，可以取消下面的注释

    /*
    // 尝试解析 JSON
    @try {
        id json = [NSJSONSerialization JSONObjectWithData:data options:0];
        if ([json isKindOfClass:[NSDictionary class]]) {
            NSString *status = json[@"status"];
            NSString *msg = json[@"msg"];
            if ([status isEqualToString:@"success"] || [msg isEqualToString:@"ok"]) {
                return YES;
            }
        }
    } @catch (NSException * e) {
        NSLog(@"[VoneVerify] JSON Parse Error: %@", e.reason);
    }
    */

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
        _inputField.borderStyle = UITextBorderStyleRoundedRect;
        _inputField.font = [UIFont systemFontOfSize:15];
        _inputField.clearButtonMode = UITextFieldViewModeWhileEditing;
        _inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _inputField.delegate = self;
        _inputField.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:_inputField];

        // 5. 分割线
        UIView *line = [[UIView alloc] init];
        line.backgroundColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0];
        line.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:line];

        // 6. 验证按钮
        _verifyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [_verifyBtn setTitle:@"验证" forState:UIControlStateNormal];
        _verifyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
        [_verifyBtn addTarget:self action:@selector(handleVerify) forControlEvents:UIControlEventTouchUpInside];
        _verifyBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:_verifyBtn];

        // 7. 状态提示标签
        _statusLabel = [[UILabel alloc] init];
        _statusLabel.font = [UIFont systemFontOfSize:12];
        _statusLabel.textColor = [UIColor redColor];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.alpha = 0;
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:_statusLabel];

        // --- 布局约束 (优化版) ---
        // 使用 UILayoutGuide 来适配 iOS 11+ 的 Safe Area
        id topAnchor = card.topAnchor;
        id bottomAnchor = card.bottomAnchor;

        [NSLayoutConstraint activateConstraints:@[
            // 卡片居中
            [card centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [card widthAnchor constraintEqualToConstant:270],

            // 标题
            [titleLabel.topAnchor constraintEqualToAnchor:topAnchor constant:20],
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
            [_inputField heightAnchor constraintEqualToConstant:36],

            // 分割线
            [line.topAnchor constraintEqualToAnchor:_inputField.bottomAnchor constant:15],
            [line.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [line.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
            [line heightAnchor constraintEqualToConstant:0.5],

            // 按钮
            [_verifyBtn.topAnchor constraintEqualToAnchor:line.bottomAnchor],
            [_verifyBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [_verifyBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
            [_verifyBtn heightAnchor constraintEqualToConstant:44],

            // 状态提示
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

    // 显示加载状态
    self.verifyBtn.enabled = NO;
    self.verifyBtn.alpha = 0.5;
    [self.verifyBtn setTitle:@"验证中..." forState:UIControlStateNormal];

    // 异步验证
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        BOOL success = verifyCode(code);

        dispatch_async(dispatch_get_main_queue(), ^{
            self.verifyBtn.enabled = YES;
            self.verifyBtn.alpha = 1.0;
            [self.verifyBtn setTitle:@"验证" forState:UIControlStateNormal];

            if (success) {
                isVerified = YES;
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Vone_Is_Activated"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                [self removeFromSuperview];
                // 可选：给用户一个成功提示
                // UIAlertController *alert = [UIAlertController...];
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

// --- Hook 微信入口 ---
%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL ret = %orig;

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

// 拦截返回手势
%hook UINavigationController
- (BOOL)navigationBar:(UINavigationBar *)navigationBar shouldPopItem:(UINavigationItem *)item {
    // 优化点：只有在验证窗口存在且可见时才拦截
    if (blockWindow && blockWindow.visible && !isVerified) {
        return NO;
    }
    return %orig;
}
%end
