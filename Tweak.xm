#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// --- 配置区 ---
#define SERVER_URL @"https://vonekeji.cn/verify.php" // 你的验证接口
#define PLUGIN_NAME @"VoneVerify"

// --- 全局变量 ---
static BOOL isVerified = NO;
static UIWindow *verifyWindow = nil;
static dispatch_once_t onceToken;

// 获取设备唯一标识 (UUID)
NSString* getDeviceUUID() {
    return [[UIDevice currentDevice] identifierForVendor].UUIDString;
}

// 显示验证窗口
void showVerifyWindow() {
    if (verifyWindow) return;

    verifyWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    verifyWindow.windowLevel = CGFLOAT_MAX; // 强制置顶
    verifyWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8]; // 半透明遮罩

    UIViewController *rootVC = [[UIViewController alloc] init];
    verifyWindow.rootViewController = rootVC;

    // 创建验证框容器
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 200)];
    container.center = CGPointMake([UIScreen mainScreen].bounds.size.width / 2, [UIScreen mainScreen].bounds.size.height / 2);
    container.backgroundColor = [UIColor whiteColor];
    container.layer.cornerRadius = 12;
    container.clipsToBounds = YES;

    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, 300, 30)];
    titleLabel.text = @"温馨提示";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [container addSubview:titleLabel];

    // 副标题
    UILabel *subTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 50, 300, 20)];
    subTitleLabel.text = @"请输入激活码";
    subTitleLabel.textAlignment = NSTextAlignmentCenter;
    subTitleLabel.font = [UIFont systemFontOfSize:14];
    [container addSubview:subTitleLabel];

    // 输入框
    UITextField *inputField = [[UITextField alloc] initWithFrame:CGRectMake(20, 80, 260, 40)];
    inputField.borderStyle = UITextBorderStyleRoundedRect;
    inputField.placeholder = @"请输入激活码";
    inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [container addSubview:inputField];

    // 验证按钮
    UIButton *verifyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    verifyBtn.frame = CGRectMake(20, 130, 260, 40);
    [verifyBtn setTitle:@"验证" forState:UIControlStateNormal];
    verifyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];

    // 点击事件处理
    __block UIButton *btnRef = verifyBtn;
    __block UITextField *fieldRef = inputField;
    [verifyBtn addTarget:nil action:@selector(verifyButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    // 将引用存入按钮 tag 或关联对象（简化起见，这里用静态变量或全局变量更稳妥）
    // 为避免复杂，我们直接在 block 里捕获
    [verifyBtn addTarget:nil action:@selector(verifyButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    // 由于 target-action 无法直接捕获局部变量，我们改用 Block 方式绑定
    // 但 UIButton 不支持直接加 Block，所以这里用一个 trick：用 objc_setAssociatedObject
    objc_setAssociatedObject(verifyBtn, @selector(verifyButtonTapped:), inputField, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [container addSubview:verifyBtn];

    [rootVC.view addSubview:container];
    [verifyWindow makeKeyAndVisible];
}

// 验证按钮点击处理
%hook UIApplication
- (void)setDelegate:(id<UIApplicationDelegate>)delegate {
    %orig;

    dispatch_once(&onceToken, ^{
        // 检查是否已验证
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults boolForKey:@"VoneVerify_Passed"]) {
            isVerified = YES;
            return;
        }

        // 未验证，显示弹窗
        showVerifyWindow();
    });
}
%end

// 验证逻辑
void performVerification(NSString *code) {
    NSURL *url = [NSURL URLWithString:SERVER_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSString stringWithFormat:@"code=%@&uuid=%@", code, getDeviceUUID()].dataUsingEncoding:NSUTF8StringEncoding;

    [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"网络错误" message:@"请检查网络连接" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
                [alert show];
                return;
            }

            NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if ([result isEqualToString:@"success"]) {
                isVerified = YES;
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"VoneVerify_Passed"];
                [[NSUserDefaults standardUserDefaults] synchronize];

                // 隐藏验证窗口
                [verifyWindow removeFromSuperview];
                verifyWindow = nil;
            } else {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"验证失败" message:@"激活码无效或已过期" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
                [alert show];
            }
        });
    }] resume];
}

// 按钮点击回调（通过关联对象获取输入框）
static void verifyButtonTapped(UIButton *sender) {
    UITextField *inputField = objc_getAssociatedObject(sender, @selector(verifyButtonTapped:));
    if (inputField && inputField.text.length > 0) {
        performVerification(inputField.text);
    } else {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"提示" message:@"请输入激活码" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
        [alert show];
    }
}
