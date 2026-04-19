TARGET = iphone:clang:latest:14.0
THEOS_PACKAGE_SCHEME ?= rootless
DEBUG = 0
SDK_PATH = $(THEOS)/sdks/iPhoneOS16.5.sdk/
SYSROOT = $(SDK_PATH)

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = Il2CppDumperPrefs

$(BUNDLE_NAME)_FILES = $(wildcard src/*.m) $(wildcard src/*.mm)
$(BUNDLE_NAME)_INSTALL_PATH = /Library/PreferenceBundles
$(BUNDLE_NAME)_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
$(BUNDLE_NAME)_PRIVATE_FRAMEWORKS = Preferences AppSupport
$(BUNDLE_NAME)_CFLAGS = -fobjc-arc -fno-modules -fvisibility=hidden -O2
$(BUNDLE_NAME)_RESOURCES = Resources

include $(THEOS_MAKE_PATH)/bundle.mk
