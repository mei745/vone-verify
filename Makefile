export ARCHS = arm64 arm64e
# 将 14.0 改为 16.2，与下载的 SDK 保持一致
export TARGET = iphone:clang:latest:16.2

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VoneVerify

VoneVerify_FILES = Tweak.xm
VoneVerify_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 WeChat"
# 在 Makefile 中添加这一行
ADDITIONAL_CFLAGS += -Wno-deprecated-declarations
