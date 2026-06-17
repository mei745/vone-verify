#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// --- 配置区 ---
#define SERVER_URL @"shturl.cc/KrkZmtTjx/verify.php"
#define PLUGIN_NAME @"VoneVerify"

// 安全获取UUID，兜底空字符串
NSString* getDeviceUUID() {
    NSUUID *uuidObj = [UIDevice currentDevice].identifierForVendor;
    if (!uuidObj) return @"unknown_device";
    return uuidObj.UUIDString;
}

%hook UIApplication

- (void)setDelegate:(id<UIApplicationDelegate>)delegate {
    %orig;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        BOOL isVerified = [defaults boolForKey:@"VoneVerify_Status"];

        if (!isVerified) {
            // 顶层弹窗窗口
            UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            window.windowLevel = CGFLOAT_MAX;
            window.backgroundColor = [UIColor blackColor];
            window.hidden = NO;

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

            // 验证按钮
            UIButton *verifyBtn = [[UIButton alloc] initWithFrame:CGRectMake(20, 210, window.bounds.size.width - 40, 45)];
            verifyBtn.backgroundColor = [UIColor systemBlueColor];
            verifyBtn.layer.cornerRadius = 8;
            [verifyBtn setTitle:@"立即验证" forState:UIControlStateNormal];
            [verifyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [container addSubview:verifyBtn];

            // 状态文字
            UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 270, window.bounds.size.width - 40, 30)];
            statusLabel.textColor = [UIColor lightGrayColor];
            statusLabel.font = [UIFont systemFontOfSize:14];
            statusLabel.textAlignment = NSTextAlignmentCenter;
            statusLabel.numberOfLines = 0;
            [container addSubview:statusLabel];

            __block BOOL isLoading = NO;
            // 验证逻辑Block
            void (^verifyLogic)(UIButton *) = ^(UIButton *sender) {
                if (isLoading) return;
                isLoading = YES;
                sender.enabled = NO;
                statusLabel.text = @"正在连接服务器...";

                NSString *uuid = getDeviceUUID();
                NSString *code = codeField.text ?: @"";

                NSString *postString = [NSString stringWithFormat:@"code=%@&uuid=%@", code, uuid];
                NSData *postData = [postString dataUsingEncoding:NSUTF8StringEncoding];

                NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:SERVER_URL]];
                request.HTTPMethod = @"POST";
                request.HTTPBody = postData;
                [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

                [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        isLoading = NO;
                        sender.enabled = YES;

                        if (error) {
                            statusLabel.text = [NSString stringWithFormat:@"网络错误: %@", error.localizedDescription];
                            statusLabel.textColor = UIColor.redColor;
                            return;
                        }

                        NSError *jsonErr;
                        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
                        if (jsonErr || !json) {
                            statusLabel.text = @"服务器返回格式错误";
                            statusLabel.textColor = UIColor.redColor;
                            return;
                        }

                        NSNumber *retCode = json[@"code"];
                        if (retCode.intValue == 200) {
                            statusLabel.text = @"验证成功！即将进入应用...";
                            statusLabel.textColor = UIColor.greenColor;
                            [defaults setBool:YES forKey:@"VoneVerify_Status"];
                            [defaults synchronize];

                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                window.hidden = YES;
                            });
                        } else {
                            statusLabel.text = json[@"msg"] ?: @"激活码错误，请重新输入";
                            statusLabel.textColor = UIColor.redColor;
                        }
                    });
                }] resume];
            };

            // 绑定Block到按钮，修复方法编码 v@:@
            objc_setAssociatedObject(verifyBtn, "verifyBlock", verifyLogic, OBJC_ASSOCIATION_COPY_NONATOMIC);
            IMP btnImp = imp_implementationWithBlock(^(UIButton *self, SEL _cmd, UIButton *sender) {
                void (^block)(UIButton *) = objc_getAssociatedObject(self, "verifyBlock");
                if (block) block(sender);
            });
            // 修复类型编码 v@:@ （void, self, _cmd, sender）
            class_addMethod([verifyBtn class], @selector(handleVerifyAction:), btnImp, "v@:@");
            [verifyBtn addTarget:verifyBtn action:@selector(handleVerifyAction:) forControlEvents:UIControlEventTouchUpInside];
        }
    });
}

%end
