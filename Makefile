# 项目名称
TARGET = iphone:clang:latest:7.0
INSTALL_TARGET_PROCESSES = SpringBoard

# 引入 Tweak 模板
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = vone-verify

# 指定源文件
vone-verify_FILES = Tweak.xm

# 引入框架（如果需要用到网络请求，通常需要 Foundation）
vone-verify_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
