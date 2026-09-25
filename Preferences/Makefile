THEOS ?= $(CURDIR)/../theos
ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:15.0
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LockScreenGradientClockPrefs
LockScreenGradientClockPrefs_FILES = LSGCRootListController.m
LockScreenGradientClockPrefs_FRAMEWORKS = UIKit
LockScreenGradientClockPrefs_PRIVATE_FRAMEWORKS = Preferences
LockScreenGradientClockPrefs_INSTALL_PATH = /Library/PreferenceBundles
LockScreenGradientClockPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
