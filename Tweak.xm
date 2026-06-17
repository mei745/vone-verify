#define SERVER_URL @"https://vonekeji.cn/verify.php"

// --- 全局变量 ---
static BOOL isVerified = NO;
static UIWindow *verifyWindow = nil;

// 获取设备唯一标识 (用于作为默认激活码或绑定机器)
NSString* getDeviceUUID() {
    return [[UIDevice currentDevice] identifierForVendor].UUIDString;
}

// ✅ 核心修复：将网络请求封装为 C 函数，避免 Logos 预处理器报错
void PerformVerification() {
    NSLog(@"[VoneVerify] 开始执行网络验证...");

    NSString *uuid = getDeviceUUID();
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?uuid=%@", SERVER_URL, uuid]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[VoneVerify] 网络请求失败: %@", error.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"验证失败" message:@"无法连接服务器" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    PerformVerification(); // 点击重试
                }]];
                [verifyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
            });
            return;
        }

        // 解析返回结果 (假设服务器返回 JSON: {"status": "success"})
