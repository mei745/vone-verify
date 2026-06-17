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

// 检查是否已验证 (利用 NSUserDefaults 持久化)
BOOL checkVerificationStatus() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"vone_verified_status"];
}

void saveVerificationStatus(BOOL status) {
    [[NSUserDefaults standardUserDefaults] setBool:status forKey:@"vone_verified_status"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// --- 核心 UI 构建与验证逻辑 ---
%hook UIApplication

- (void)setDelegate:(id<UIApplicationDelegate>)delegate {
    %orig;

    // 如果已经验证过，直接跳过，不再弹窗
    if (checkVerificationStatus()) {
        return;
    }

    dispatch_once(&onceToken, ^{
        // 创建一个独立的 Window，层级设为最高，确保覆盖所有界面
        verifyWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        verifyWindow.windowLevel = CGFLOAT_MAX;
        verifyWindow.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.85]; // 半透明黑色背景
        verifyWindow.hidden = NO;

        // 创建主容器视图
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(20, 0, [UIScreen mainScreen].bounds.size.width - 40, 200)];
        container.center = CGPointMake([UIScreen mainScreen].bounds.size.width / 2, [UIScreen mainScreen].bounds.size.height / 2);
        container.backgroundColor = [UIColor whiteColor];
        container.layer.cornerRadius = 12;
        container.clipsToBounds = YES;
        [verifyWindow addSubview:container];

        // 标题
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, container.bounds.size.width, 30)];
        titleLabel.text = @"温馨提示";
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [container addSubview:titleLabel];

        // 提示语
        UILabel *msgLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 55, container.bounds.size.width, 20)];
        msgLabel.text = @"请输入激活码";
        msgLabel.textAlignment = NSTextAlignmentCenter;
        msgLabel.font = [UIFont systemFontOfSize:14];
        msgLabel.textColor = [UIColor grayColor];
        [container addSubview:msgLabel];

        // 输入框
        UITextField *codeField = [[UITextField alloc] initWithFrame:CGRectMake(20, 90, container.bounds.size.width - 40, 40)];
        codeField.borderStyle = UITextBorderStyleRoundedRect;
        codeField.placeholder = @"请输入激活码";
        codeField.clearButtonMode = UITextFieldViewModeWhileEditing;
        [container addSubview:codeField];

        // 验证按钮
        UIButton *verifyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        verifyBtn.frame = CGRectMake(20, 145, container.bounds.size.width - 40, 40);
        [verifyBtn setTitle:@"验证" forState:UIControlStateNormal];
        verifyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [verifyBtn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
        [container addSubview:verifyBtn];

        // --- 按钮点击事件 ---
        [verifyBtn addTarget:self action:@selector(handleVerifyAction:) forControlEvents:UIControlEventTouchUpInside];

        // 将输入框和按钮存入关联对象，以便在点击事件中获取
        objc_setAssociatedObject(self, "verifyCodeField", codeField, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, "verifyBtn", verifyBtn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

// 处理验证点击
%new
- (void)handleVerifyAction:(UIButton *)sender {
    UITextField *codeField = objc_getAssociatedObject(self, "verifyCodeField");
    UIButton *verifyBtn = objc_getAssociatedObject(self, "verifyBtn");

    NSString *code = codeField.text;
    if (code.length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"请输入激活码" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [verifyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        return;
    }

    // 锁定按钮，防止重复点击
    verifyBtn.enabled = NO;
    [verifyBtn setTitle:@"验证中..." forState:UIControlStateDisabled];

    // 发起网络请求
    NSURL *url = [NSURL URLWithString:SERVER_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    // 构造参数
    NSString *params = [NSString stringWithFormat:@"code=%@&uuid=%@", code, getDeviceUUID()];
    request.HTTPBody = [params dataUsingEncoding:NSUTF8StringEncoding];
    request.timeoutInterval = 10.0;

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // 恢复按钮状态
            verifyBtn.enabled = YES;
            [verifyBtn setTitle:@"验证" forState:UIControlStateNormal];

            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"网络错误" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:nil]];
                [verifyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
                return;
            }

            // 解析服务器返回
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *status = json[@"status"]; // 假设服务器返回 {"status": "success"}

            if ([status isEqualToString:@"success"]) {
                // 验证成功
                saveVerificationStatus(YES);
                [UIView animateWithDuration:0.3 animations:^{
                    verifyWindow.alpha = 0;
                } completion:^(BOOL finished) {
                    [verifyWindow setHidden:YES];
                    verifyWindow = nil;
                }];
            } else {
                // 验证失败
                NSString *msg = json[@"msg"] ? json[@"msg"] : @"激活码无效";
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"验证失败" message:msg preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [verifyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
            }
        });
    }] resume];
}

%end
