THEOS ?= $(CURDIR)/theos
ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LockScreenGradientClock
LockScreenGradientClock_FILES = Tweak.xm
LockScreenGradientClock_CFLAGS = -fobjc-arc
LockScreenGradientClock_FRAMEWORKS = UIKit QuartzCore CoreGraphics CoreFoundation
LockScreenGradientClock_LIBRARIES = substrate

SUBPROJECTS += Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
