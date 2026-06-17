THEOS_PACKAGE_NAME = com.vone.verify
# 支持全64位iPhone
ARCHS = arm64 arm64e
# 最低iOS15，匹配SDK16.2
TARGET = iphone:clang:16.2:15.0
ADDITIONAL_CFLAGS = -Wno-deprecated-declarations -fobjc-arc

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VoneVerify
VoneVerify_FILES = Tweak.xm
VoneVerify_FRAMEWORKS = UIKit Foundation

# 仅注入微信进程 WeChat
INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS_MAKE_PATH)/tweak.mk
