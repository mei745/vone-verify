TARGET = iphone:clang:latest:7.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

ARCHS = arm64

# 1. 定义项目名称
TWEAK_NAME = voneyz

# 2. 指定源文件 (前缀必须和 TWEAK_NAME 一样)
voneyz_FILES = Tweak.xm

# 3. 引入框架 (前缀必须和 TWEAK_NAME 一样)
voneyz_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
