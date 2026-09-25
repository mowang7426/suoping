TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LockScreenGradientClock
LockScreenGradientClock_FILES = Tweak.xm
LockScreenGradientClock_CFLAGS = -fobjc-arc
LockScreenGradientClock_FRAMEWORKS = UIKit QuartzCore CoreGraphics
LockScreenGradientClock_PRIVATE_FRAMEWORKS = SpringBoardFoundation

SUBPROJECTS += Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
