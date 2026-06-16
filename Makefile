# 优化点：移除 arm64e 以兼容老设备，升级 SDK 版本
export ARCHS = arm64
export TARGET = iphone:clang:16.5:16.5

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VoneVerify

VoneVerify_FILES = Tweak.xm
VoneVerify_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
install.exec "killall -9 WeChat"
