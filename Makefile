# Makefile

# 你的包名
THEOS_PACKAGE_NAME = com.vone.verify

# 必须指定最低版本，否则默认 latest 可能会出错
TARGET = iphone:clang:latest:15.0

# --- 关键修复：添加这行来忽略弃用警告 ---
ADDITIONAL_CFLAGS = -Wno-deprecated-declarations

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VoneVerify
VoneVerify_FILES = Tweak.xm
VoneVerify_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
