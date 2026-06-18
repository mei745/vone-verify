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
                window = [(UIWindowScene *)scene keyWindow];
                break;
            }
        }
    } else {
        window = [UIApplication sharedApplication].keyWindow;
    }
    return window.rootViewController;
}

// --- 核心类：常驻验证窗口 ---
@interface VoneVerifyView : UIView <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, strong) UIButton *verifyBtn;
- (void)show;
- (void)hide;
@end

@implementation VoneVerifyView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.8]; // 半透明黑背景
        self.tag = 99999; // 特殊标记，防止重复添加

        // 1. 主容器（白色圆角框）
        UIView *container = [[UIView alloc] init];
        container.backgroundColor = [UIColor whiteColor];
        container.layer.cornerRadius = 12;
        container.clipsToBounds = YES;
        [self addSubview:container];

        // 2. 标题
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = @"Vone 激活验证";
        titleLabel.font = [UIFont boldSystemFontOfSize:18];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        [container addSubview:titleLabel];

        // 3. 输入框
        self.codeField = [[UITextField alloc] init];
        self.codeField.placeholder = @"请输入激活码";
        self.codeField.borderStyle = UITextBorderStyleRoundedRect;
        self.codeField.keyboardType = UIKeyboardTypeAlphabet; // 字母键盘
        self.codeField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters; // 自动大写
        self.codeField.returnKeyType = UIReturnKeyDone;
        self.codeField.delegate = self;
        [container addSubview:self.codeField];

        // 4. 验证按钮
        self.verifyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.verifyBtn setTitle:@"立即验证" forState:UIControlStateNormal];
        self.verifyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        self.verifyBtn.backgroundColor = [UIColor systemBlueColor];
        [self.verifyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.verifyBtn.layer.cornerRadius = 8;
        // 【关键修改】使用标准的 Target-Action 绑定事件，不再使用 Runtime
        [self.verifyBtn addTarget:self action:@selector(verifyAction:) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:self.verifyBtn];

        // 布局 (手动计算位置，不依赖 AutoLayout 以免冲突)
        CGFloat padding = 20;
        CGFloat width = 280;
        CGFloat height = 160;
        container.frame = CGRectMake((frame.size.width - width) / 2, (frame.size.height - height) / 2, width, height);

        titleLabel.frame = CGRectMake(0, 20, width, 30);

        self.codeField.frame = CGRectMake(padding, 60, width - padding * 2, 35);

        self.verifyBtn.frame = CGRectMake(padding, 105, width - padding * 2, 40);
    }
    return self;
}

// 显示窗口
- (void)show {
    UIWindow *window = [UIApplication sharedApplication].windows.lastObject;
    if (!window) return;

    // 如果已经存在，就不重复添加了
    if ([window viewWithTag:99999]) return;

    self.frame = window.bounds;
    [window addSubview:self];
}

// 隐藏窗口（只有验证成功才调用）
- (void)hide {
    [self removeFromSuperview];
}

// 点击空白处收起键盘
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.codeField resignFirstResponder];
}

// 回车键收起键盘
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self verifyAction:nil]; // 回车也触发验证
    return YES;
}

// 验证逻辑
- (void)verifyAction:(id)sender {
    NSString *code = self.codeField.text;

    // 1. 判空检查
    if (code.length == 0 || [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"激活码不能为空！" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
        [[UIApplication sharedApplication].windows.lastObject.rootViewController presentViewController:alert animated:YES completion:nil];
        return; // 【关键】这里直接 return，窗口不会消失
    }

    // 2. 设置 Loading 状态，防止重复点击
    self.verifyBtn.enabled = NO;
    self.verifyBtn.backgroundColor = [UIColor lightGrayColor];
    [self.verifyBtn setTitle:@"验证中..." forState:UIControlStateNormal];

    // 3. 发起网络请求
    NSString *urlString = [NSString stringWithFormat:@"%@?code=%@", VERIFY_API_URL, code];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET"; // 或者 POST，看你的PHP支持哪种

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // 恢复按钮状态
            self.verifyBtn.enabled = YES;
            self.verifyBtn.backgroundColor = [UIColor systemBlueColor];
            [self.verifyBtn setTitle:@"立即验证" forState:UIControlStateNormal];

            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"网络错误" message:@"无法连接服务器，请检查网络" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:nil]];
                [[UIApplication sharedApplication].windows.lastObject.rootViewController presentViewController:alert animated:YES completion:nil];
                return; // 失败，窗口保留
            }

            NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[VoneVerify] Server Response: %@", result);

            // 简单的判断逻辑：假设返回 "success" 或包含 "success" 就算通过
            // 你可以根据实际 PHP 返回值修改这里的判断条件
            if ([result.lowercaseString containsString:@"success"] || [result isEqualToString:@"1"]) {
                // === 验证成功 ===
                // 保存激活状态
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                [defaults setBool:YES forKey:PREFS_STATUS];
                [defaults setObject:code forKey:PREFS_KEY];
                [defaults synchronize];

                // 关闭窗口
                [self hide];
            } else {
                // === 验证失败 ===
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"验证失败" message:@"激活码错误或已失效，请重新输入" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:nil]];
                [[UIApplication sharedApplication].windows.lastObject.rootViewController presentViewController:alert animated:YES completion:nil];
                // 失败，窗口保留，用户可以继续改
            }
        });
    }];
    [task resume];
}

@end

// --- Hook 微信启动 ---
%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    %orig;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isActivated = [defaults boolForKey:PREFS_STATUS];

    if (!isActivated) {
        // 延迟一点弹出，等微信界面加载完
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            VoneVerifyView *verifyView = [[VoneVerifyView alloc] initWithFrame:[UIScreen mainScreen].bounds];
            [verifyView show];
        });
    }

    return YES;
}

%end
