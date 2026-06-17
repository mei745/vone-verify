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

- (void)setDelegate:(id<UIApplicationDelegate>)delegate {
    %orig;

    // 使用 dispatch_once 确保只执行一次，且线程安全
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 检查是否已验证 (利用 NSUserDefaults 持久化)
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        BOOL isVerified = [defaults boolForKey:@"VoneVerify_Status"];

        if (!isVerified) {
            // 创建独立窗口，确保在最顶层
            UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            window.windowLevel = CGFLOAT_MAX;
            window.backgroundColor = [UIColor blackColor];
            window.hidden = NO;

            // 构建 UI
            UIView *container = [[UIView alloc] initWithFrame:window.bounds];
            container.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
            [window addSubview:container];

            // 标题
            UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, window.bounds.size.width - 40, 30)];
            titleLabel.text = @"需要验证";
            titleLabel.textColor = [UIColor whiteColor];
            titleLabel.font = [UIFont boldSystemFontOfSize:20];
            titleLabel.textAlignment = NSTextAlignmentCenter;
            [container addSubview:titleLabel];

            // 输入框
            UITextField *codeField = [[UITextField alloc] initWithFrame:CGRectMake(20, 150, window.bounds.size.width - 40, 40)];
            codeField.placeholder = @"请输入激活码";
            codeField.textColor = [UIColor whiteColor];
            codeField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
            codeField.layer.cornerRadius = 8;
            codeField.textAlignment = NSTextAlignmentCenter;
            codeField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            [container addSubview:codeField];

            // 按钮
            UIButton *verifyBtn = [[UIButton alloc] initWithFrame:CGRectMake(20, 210, window.bounds.size.width - 40, 45)];
            verifyBtn.backgroundColor = [UIColor systemBlueColor];
            verifyBtn.layer.cornerRadius = 8;
            [verifyBtn setTitle:@"立即验证" forState:UIControlStateNormal];
            [verifyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [container addSubview:verifyBtn];

            // 状态标签
            UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 270, window.bounds.size.width - 40, 30)];
            statusLabel.textColor = [UIColor lightGrayColor];
            statusLabel.font = [UIFont systemFontOfSize:14];
            statusLabel.textAlignment = NSTextAlignmentCenter;
            statusLabel.numberOfLines = 0;
            [container addSubview:statusLabel];

            // 按钮点击事件 (Block 写法，避免 unused function 报错)
            __block BOOL isLoading = NO;
            [verifyBtn addTarget:nil action:@selector(handleVerifyAction:) forControlEvents:UIControlEventTouchUpInside];

            // 动态绑定 Block 到按钮，模拟 Target-Action
            objc_setAssociatedObject(verifyBtn, "verifyBlock", ^{
                if (isLoading) return;
                isLoading = YES;
                verifyBtn.enabled = NO;
                statusLabel.text = @"正在连接服务器...";

                NSString *uuid = getDeviceUUID();
                NSString *code = codeField.text ?: @"";
                NSString *urlStr = [NSString stringWithFormat:@"%@?uuid=%@&code=%@", SERVER_URL, uuid, code];
                NSURL *url = [NSURL URLWithString:urlStr];
                NSURLRequest *request = [NSURLRequest requestWithURL:url];

                [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        isLoading = NO;
                        verifyBtn.enabled = YES;

                        if (error) {
                            statusLabel.text = [NSString stringWithFormat:@"网络错误: %@", error.localizedDescription];
                            return;
                        }

                        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                        NSNumber *codeNum = json[@"code"];

                        if ([codeNum intValue] == 200) {
                            statusLabel.text = @"验证成功！即将进入应用...";
                            statusLabel.textColor = [UIColor greenColor];

                            // 保存验证状态
                            [defaults setBool:YES forKey:@"VoneVerify_Status"];
                            [defaults synchronize];

                            // 延迟关闭窗口
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                window.hidden = YES;
                                window = nil;
                            });
                        } else {
                            statusLabel.text = json[@"msg"] ?: @"验证失败，请检查激活码";
                            statusLabel.textColor = [UIColor redColor];
                        }
                    });
                }] resume];
            }, OBJC_ASSOCIATION_COPY_NONATOMIC);

            // 真正的 Target 方法，用于触发 Block
            IMP imp = imp_implementationWithBlock(^void(id _self) {
                void (^block)() = objc_getAssociatedObject(_self, "verifyBlock");
                if (block) block();
            });
            class_addMethod([verifyBtn class], @selector(handleVerifyAction:), imp, "v@:");
        }
    });
}

%end
