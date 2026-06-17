THEOS_PACKAGE_NAME = com.vone.verify
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
ADDITIONAL_CFLAGS = -Wno-deprecated-declarations -fobjc-arc

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VoneVerify
VoneVerify_FILES = Tweak.xm
VoneVerify_FRAMEWORKS = UIKit Foundation

# SpringBoard = 全局注入，所有App启动都会加载你的dylib
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS_MAKE_PATH)/tweak.mk
