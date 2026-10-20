THEOS ?= $(CURDIR)/theos
ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LockScreenGradientClock
LockScreenGradientClock_FILES = Tweak.xm LSGCChargingETAPill.xm LSGCJikanETAAdapter.m LSGCHideSystemPrompts.xm
LockScreenGradientClock_CFLAGS = -fobjc-arc
Tweak.xm_CFLAGS = -std=c++17
LSGCChargingETAPill.xm_CFLAGS = -std=c++17
LSGCHideSystemPrompts.xm_CFLAGS = -std=c++17
LockScreenGradientClock_FRAMEWORKS = UIKit QuartzCore CoreGraphics CoreFoundation CoreText
LockScreenGradientClock_LIBRARIES = substrate

SUBPROJECTS += Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
