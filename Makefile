# 项目名称
TARGET = iphone:clang:latest:7.0
INSTALL_TARGET_PROCESSES = SpringBoard

# 引入 Tweak 模板
include $(THEOS)/makefiles/common.mk

# 指定架构为 arm64
ARCHS = arm64

TWEAK_NAME = voneyz

# 指定源文件
vone-verify_FILES = Tweak.xm

# 引入框架
vone-verify_FRAMEWORKS = UIKit Foundation

# 引入 tweak 模板 (注意这里绝对没有多余的括号)
include $(THEOS_MAKE_PATH)/tweak.mk
