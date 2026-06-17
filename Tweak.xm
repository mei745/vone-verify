#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// --- 配置区 ---
#define SERVER_URL @"https://vonekeji.cn/verify.php" // 你的验证接口
#define PLUGIN_NAME @"VoneVerify"

// 获取设备唯一标识 (UUID)
NSString* getDeviceUUID() {
    return [[UIDevice currentDevice] identifierForVendor].UUIDString;
}

%hook UIApplication

// Hook setDelegate: 这是 App 启动时必然调用的方法，比 didFinishLaunching 更稳
- (void)setDelegate:(id<UIApplicationDelegate>)delegate {
    %orig;

    // 使用 dispatch_once 确保整个 App 生命周期只执行一次弹窗逻辑
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        // 1. 检查是否已经验证过 (利用 NSUserDefaults 持久化)
        BOOL isVerified = [[NSUserDefaults standardUserDefaults] boolForKey:@"Vone_Verify_Status"];
        if (isVerified) return; // 如果已验证，直接跳过，不弹窗

        // 2. 创建强制验证窗口
        UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        window.windowLevel = CGFLOAT_MAX; // 最高层级，覆盖微信主界面
        window.backgroundColor = [UIColor blackColor];
        window.hidden = NO;
        [window makeKeyAndVisible];

        // 3. 构建 UI 界面
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(20, 0, [UIScreen mainScreen].bounds.size.width - 40, 200)];
        container.center = window.center;
        container.backgroundColor = [UIColor whiteColor];
        container.layer.cornerRadius = 12;
        [window addSubview:container];

        // 标题
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, container.bounds.size.width, 30)];
        titleLabel.text = @"激活验证";
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [container addSubview:titleLabel];

        // 输入框
        UITextField *codeField = [[UITextField alloc] initWithFrame:CGRectMake(15, 60, container.bounds.size.width - 30, 40)];
        codeField.borderStyle = UITextBorderStyleRoundedRect;
        codeField.placeholder = @"请输入激活码...";
        codeField.keyboardType = UIKeyboardTypeAlphabet;
        [container addSubview:codeField];

        // 按钮
        UIButton *submitBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        submitBtn.frame = CGRectMake(15, 110, container.bounds.size.width - 30, 40);
        [submitBtn setTitle:@"立即验证" forState:UIControlStateNormal];
        submitBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        submitBtn.backgroundColor = [UIColor systemBlueColor];
        submitBtn.layer.cornerRadius = 8;
        submitBtn.tintColor = [UIColor whiteColor];
        [container addSubview:submitBtn];

        // 4. 处理点击事件 (Block 写法，避免函数未定义报错)
        [submitBtn addTarget:nil action:@selector(handleVerifyClick:) forControlEvents:UIControlEventTouchUpInside];

        // 使用 objc_setAssociatedObject 将输入框和按钮绑定，方便在回调中取值
        // 注意：这里我们需要一个临时的 target 对象来持有 block，或者直接用简单的 C 函数
        // 为了简化且不出错，我们使用最简单的 Target-Action 模式配合 AssociatedObject
        objc_setAssociatedObject(submitBtn, "inputField", codeField, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

%end

// --- 独立的 C 函数处理点击事件 (避免 Block 语法错误和变量作用域问题) ---
// 这个函数必须定义在 %end 之外，或者作为静态函数
static void handleVerifyClick(id sender) {
    // 取出关联的输入框
    UITextField *field = objc_getAssociatedObject(sender, "inputField");
    NSString *code = field.text;

    if (code.length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"请输入激活码" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        // 获取当前最上层 Window 来展示 Alert
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        return;
    }

    // 显示加载状态
    UIButton *btn = (UIButton *)sender;
    [btn setTitle:@"验证中..." forState:UIControlStateNormal];
    btn.enabled = NO;

    // 准备网络请求
    NSString *uuid = getDeviceUUID();
    NSString *postBody = [NSString stringWithFormat:@"code=%@&uuid=%@", code, uuid];
    NSData *postData = [postBody dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:SERVER_URL]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = postData;

    // 发送请求
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            btn.enabled = YES;
            [btn setTitle:@"立即验证" forState:UIControlStateNormal];

            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"网络错误" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:nil]];
                [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
                return;
            }

            // 解析结果 (假设服务器返回 JSON: {"status": 1})
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json[@"status"] integerValue] == 1) {
                // 验证成功
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Vone_Verify_Status"];
                [[NSUserDefaults standardUserDefaults] synchronize];

                // 移除验证窗口
                for (UIWindow *w in [UIApplication sharedApplication].windows) {
                    if (w.windowLevel == CGFLOAT_MAX) {
                        w.hidden = YES;
                        [w removeFromSuperview];
                    }
                }
            } else {
                // 验证失败
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"验证失败" message:@"激活码无效或已过期" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
            }
        });
    }] resume];
}
