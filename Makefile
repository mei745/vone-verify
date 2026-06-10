# === 基础环境配置 ===
TARGET = iphone:clang:latest:7.0
INSTALL_TARGET_PROCESSES = WeChat  # 注意：如果这是通用插件，建议改为 SpringBoard 或删除此行
ARCHS = arm64 arm64e              # 增加 arm64e 以支持 iPhone XS/11/12/13/14/15 等新设备

include $(THEOS)/makefiles/common.mk

# === 项目定义 ===
TWEAK_NAME = voneyz

# === 源文件 ===
voneyz_FILES = Tweak.xm

# === 依赖框架 (关键修改) ===
# UIKit/Foundation: 界面交互
# CFNetwork: 用于发送 HTTP 请求验证激活码
# Security: 用于处理 HTTPS 证书校验
voneyz_FRAMEWORKS = UIKit Foundation CFNetwork Security

# === 编译标志 (可选，防止警告) ===
voneyz_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

# === 打包后处理 (可选) ===
after-install::
	install.exec "killall -9 WeChat || true"
