# 项目名称
TARGET = iphone:clang:latest:7.0
INSTALL_TARGET_PROCESSES = SpringBoard

# 引入 Tweak 模板
include $(THEOS)/makefiles/common.mk

# --- 添加以下这一行 ---
ARCHS = arm64  # 现代越狱插件基本只需要 arm64，除非你还要兼容 iPhone 4s/5 等老古董
# --------------------

TWEAK_NAME = vone-verify
vone-verify_FILES = Tweak.xm
vone-Verify_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk)
