#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// --- 统一配置宏 ---
#define SERVER_URL @"shturl.cc/KrkZmtTjx/verify.php"
#define PLUGIN_NAME @"VoneVerify"
#define VERIFY_STATUS_KEY @"VoneVerify_Status"
#define WINDOW_MAX_LEVEL 1000000.0f
#define PLACEHOLDER_TEXT @"请输入激活码"
#define TITLE_TEXT @"软件激活验证"

// 安全获取UUID + URL编码，兜底空字符串
static NSString* getDeviceUUID() {
    if (![NSThread isMainThread]) {
        __block NSString *result = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            NSUUID *uuidObj = [UIDevice currentDevice].identifierForVendor;
            NSString *rawUUID = uuidObj ? uuidObj.UUIDString : @"unknown_device";
            result = [rawUUID stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        });
        return result;
    }
    NSUUID *uuidObj = [UIDevice currentDevice].identifierForVendor;
    NSString *rawUUID = uuidObj ? uuidObj.UUIDString : @"unknown_device";
    return [rawUUID stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
}

// dylib加载即执行，全局所有App生效
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            BOOL isVerified = [defaults boolForKey:VERIFY_STATUS_KEY];
            if (isVerified) return;

            // 顶层全屏窗口，覆盖所有App界面
            UIWindow *__weak weakWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            weakWindow.windowLevel = WINDOW_MAX_LEVEL;
            weakWindow.backgroundColor = [UIColor blackColor];
            weakWindow.hidden = NO;

            UIView *container = [[UIView alloc] initWithFrame:weakWindow.bounds];
            container.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
            [weakWindow addSubview:container];

            // 点击空白收起键盘
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:container action:@selector(endEditing:)];
            [container addGestureRecognizer:tap];

            // 标题
            UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, weakWindow.bounds.size.width - 40, 30)];
            titleLabel.text = TITLE_TEXT;
            titleLabel.textColor = [UIColor whiteColor];
            titleLabel.font = [UIFont boldSystemFontOfSize:20];
            titleLabel.textAlignment = NSTextAlignmentCenter;
            [container addSubview:titleLabel];

            // 输入框
            UITextField *codeField = [[UITextField alloc] initWithFrame:CGRectMake(20, 150, weakWindow.bounds.size.width - 40, 40)];
            codeField.placeholder = PLACEHOLDER_TEXT;
            codeField.textColor = [UIColor whiteColor];
            codeField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
            codeField.layer.cornerRadius = 8;
            codeField.textAlignment = NSTextAlignmentCenter;
            codeField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            [container addSubview:codeField];

            // 验证按钮
            UIButton *verifyBtn = [[UIButton alloc] initWithFrame:CGRectMake(20, 210, weakWindow.bounds.size.width - 40, 45)];
            verifyBtn.backgroundColor = [UIColor systemBlueColor];
            verifyBtn.layer.cornerRadius = 8;
            [verifyBtn setTitle:@"立即验证" forState:UIControlStateNormal];
            [verifyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [container addSubview:verifyBtn];

            // 状态文字
            UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 270, weakWindow.bounds.size.width - 40, 30)];
            statusLabel.textColor = [UIColor lightGrayColor];
            statusLabel.font = [UIFont systemFontOfSize:14];
            statusLabel.textAlignment = NSTextAlignmentCenter;
            statusLabel.numberOfLines = 0;
            [container addSubview:statusLabel];

            __block BOOL isLoading = NO;
            void (^verifyLogic)(UIButton *) = ^(UIButton *sender) {
                if (isLoading) return;
                isLoading = YES;
                sender.enabled = NO;
                statusLabel.text = @"正在连接服务器验证...";

                NSString *uuid = getDeviceUUID();
                NSString *rawCode = codeField.text ?: @"";
                NSString *code = [rawCode stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];

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
                            statusLabel.textColor = [UIColor redColor];
                            return;
                        }

                        NSError *jsonErr;
                        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
                        if (jsonErr || !json) {
                            statusLabel.text = @"服务器返回数据格式异常";
                            statusLabel.textColor = [UIColor redColor];
                            return;
                        }

                        NSNumber *retCode = json[@"code"];
                        if (retCode.intValue == 200) {
                            statusLabel.text = @"验证成功，可正常使用所有软件！";
                            statusLabel.textColor = [UIColor greenColor];
                            [defaults setBool:YES forKey:VERIFY_STATUS_KEY];

                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                weakWindow.hidden = YES;
                                weakWindow = nil;
                            });
                        } else {
                            statusLabel.text = json[@"msg"] ?: @"激活码无效，请重新输入";
                            statusLabel.textColor = [UIColor redColor];
                        }
                    });
                }] resume];
            };

            objc_setAssociatedObject(verifyBtn, "verifyBlock", verifyLogic, OBJC_ASSOCIATION_COPY_NONATOMIC);
            IMP btnImp = imp_implementationWithBlock(^(UIButton *self, SEL _cmd, UIButton *sender) {
                void (^block)(UIButton *) = objc_getAssociatedObject(self, "verifyBlock");
                if (block) block(sender);
            });
            class_addMethod([verifyBtn class], @selector(handleVerifyAction:), btnImp, "v@:@");
            [verifyBtn addTarget:verifyBtn action:@selector(handleVerifyAction:) forControlEvents:UIControlEventTouchUpInside];
        });
    });
}
