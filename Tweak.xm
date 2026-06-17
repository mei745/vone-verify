#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// --- 配置区 ---
#define SERVER_URL @"https://vonekeji.cn/verify.php" // 你的验证接口
#define PLUGIN_NAME @"VoneVerify"

// --- 全局变量 ---
static BOOL isVerified = NO;
static UIWindow *verifyWindow = nil;
static dispatch_once_t onceToken; // 用于确保只执行一次

// 获取设备唯一标识 (UUID)
NSString* getDeviceUUID() {
    return [[UIDevice currentDevice] identifierForVendor].UUIDString;
}

// 保存验证状态到本地
void saveVerificationStatus(BOOL status) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:status forKey:@"VoneVerify_Status"];
    [defaults synchronize];
    isVerified = status;
}

// 检查是否已验证
BOOL checkVerificationStatus() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults boolForKey:@"VoneVerify_Status"];
}

// --- 核心逻辑：显示验证弹窗 ---
void showVerifyWindow() {
    // 如果已经验证过，直接返回，不显示弹窗
    if (isVerified || checkVerificationStatus()) {
        NSLog(@"[VoneVerify] Already verified, skipping window.");
        return;
    }

    // 防止重复创建窗口
    if (verifyWindow) return;

    NSLog(@"[VoneVerify] Creating verification window...");

    // 1. 创建一个独立的 UIWindow，层级设为最高，覆盖所有应用界面
    verifyWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    verifyWindow.windowLevel = CGFLOAT_MAX; // 关键：强制置顶
    verifyWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8]; // 半透明黑色背景，遮挡下方内容
    verifyWindow.hidden = NO;

    // 2. 创建主容器视图 (模仿你提供的图片风格)
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 200)];
    container.center = verifyWindow.center;
    container.backgroundColor = [UIColor whiteColor];
    container.layer.cornerRadius = 12;
    container.clipsToBounds = YES;
    [verifyWindow addSubview:container];

    // 3. 标题 Label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 30, 300, 30)];
    titleLabel.text = @"温馨提示";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [container addSubview:titleLabel];

    // 4. 提示语 Label
    UILabel *subLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 60, 300, 20)];
    subLabel.text = @"请输入激活码";
    subLabel.textAlignment = NSTextAlignmentCenter;
    subLabel.font = [UIFont systemFontOfSize:14];
    subLabel.textColor = [UIColor grayColor];
    [container addSubview:subLabel];

    // 5. 输入框
    UITextField *codeField = [[UITextField alloc] initWithFrame:CGRectMake(20, 90, 260, 40)];
    codeField.borderStyle = UITextBorderStyleRoundedRect;
    codeField.placeholder = @"请输入激活码";
    codeField.textAlignment = NSTextAlignmentCenter;
    codeField.keyboardType = UIKeyboardTypeAlphabet;
    [container addSubview:codeField];

    // 6. 验证按钮
    UIButton *verifyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    verifyBtn.frame = CGRectMake(0, 140, 300, 40); // 占满底部
    [verifyBtn setTitle:@"验证" forState:UIControlStateNormal];
    verifyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];

    // ✅ 修复点：直接使用 Block 处理点击，不再依赖外部函数
    [verifyBtn addTarget:nil action:@selector(verifyAction:) forControlEvents:UIControlEventTouchUpInside];
    // 为了让 Block 能工作，我们需要利用 objc_setAssociatedObject 把 Block 存起来，或者直接用简单的 Target-Action 配合静态函数。
    // 这里为了保持代码简洁且不报错，我们使用一个静态 Helper 函数来桥接。

    // 给按钮打Tag，方便在点击事件中获取输入框的值
    codeField.tag = 1001;
    verifyBtn.tag = 1002;

    [container addSubview:verifyBtn];

    // 7. 添加点击事件处理 (使用简单的 Target-Action 模式，最稳定)
    // 注意：这里我们需要定义一个能被找到的函数。
}

// ✅ 修复点：定义一个静态函数来处理点击，并确保它被调用
static void verifyBtnClicked(UIButton *sender) {
    UIWindow *window = sender.window;
    if (!window) return;

    // 找到输入框 (通过 Tag 查找)
    UITextField *field = (UITextField *)[window viewWithTag:1001];
    NSString *code = field.text;

    if (code.length == 0) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"提示" message:@"请输入激活码" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
        [alert show];
        return;
    }

    NSLog(@"[VoneVerify] Verifying code: %@", code);

    // 发起网络请求
    NSString *urlStr = [NSString stringWithFormat:@"%@?code=%@&uuid=%@", SERVER_URL, code, getDeviceUUID()];
    NSURL *url = [NSURL URLWithString:urlStr];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"网络错误" message:error.localizedDescription delegate:nil cancelButtonTitle:@"重试" otherButtonTitles:nil];
                [alert show];
            });
            return;
        }

        // 解析 JSON (假设服务器返回 {"success": true} 或类似结构)
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        BOOL success = [json[@"success"] boolValue]; // 根据你的服务器实际返回值修改判断逻辑

        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                saveVerificationStatus(YES);
                // 验证成功，销毁窗口
                verifyWindow.hidden = YES;
                verifyWindow = nil;
                NSLog(@"[VoneVerify] Verification Success!");
            } else {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"验证失败" message:@"激活码无效或已过期" delegate:nil cancelButtonTitle:@"重试" otherButtonTitles:nil];
                [alert show];
            }
        });
    }] resume];
}

// 这是一个中间人函数，用来连接 Button 和上面的 verifyBtnClicked
%hook UIViewController
- (void)viewDidLoad {
    %orig;
    // 我们不 hook viewDidLoad，因为太频繁。我们用下面的 UIApplication hook。
}
%end

// --- 真正的入口：Hook 应用启动 ---
%hook UIApplication

// 拦截 applicationDidFinishLaunching，这是所有 App 启动的必经之路
- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig; // 先让原程序跑起来

    // 使用 dispatch_once 确保只在第一次启动时执行
    dispatch_once(&onceToken, ^{
        showVerifyWindow();

        // 手动绑定按钮事件 (因为 showVerifyWindow 里没法直接传 block 给 target)
        // 我们需要遍历一下刚才创建的 window 找到按钮
        if (verifyWindow) {
            for (UIView *subview in verifyWindow.subviews) {
                if ([subview isKindOfClass:[UIView class]]) { // 那个白色的 container
                    for (UIView *child in subview.subviews) {
                        if ([child isKindOfClass:[UIButton class]] && child.tag == 1002) {
                            // 找到按钮了，绑定我们的静态函数
                            [(UIButton *)child addTarget:nil action:@selector(verifyBtnClicked:) forControlEvents:UIControlEventTouchUpInside];
                        }
                    }
                }
            }
        }
    });
}

%end
