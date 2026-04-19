TARGET := iphone:clang:latest:13.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless
DEBUG = 0
THEOS_DEVICE_IP = 192.168.1.148
ZIP_ARCHIVE_DEFINES = -DHAVE_INTTYPES_H -DHAVE_PKCRYPT -DHAVE_STDINT_H -DHAVE_WZAES -DHAVE_ZLIB
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Il2CppDumper

HEADER_DIRS = $(shell find . -path ./.theos -prune -o -path ./Il2CppDumperPrefs -prune -o -type f -name "*.h" -exec dirname {} \; | sort -u)

$(TWEAK_NAME)_FILES = $(shell find . -path ./.theos -prune -o -path ./Il2CppDumperPrefs -prune -o -type f \( -iname "*.cpp" -o -iname "*.c" -o -iname "*.cc" -o -iname "*.m" -o -iname "*.mm" \) -print)
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation Security CoreGraphics QuartzCore
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -fno-modules -fvisibility=hidden -O2 $(ZIP_ARCHIVE_DEFINES) $(foreach dir, $(HEADER_DIRS), -I$(dir))
$(TWEAK_NAME)_CCFLAGS = -std=c++20 -fno-rtti -fno-modules -fvisibility=hidden -O2 $(foreach dir, $(HEADER_DIRS), -I$(dir))
$(TWEAK_NAME)_LDFLAGS = -lz -liconv -ldl -Wl,-dead_strip_dylibs -Wl,-x
include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Il2CppDumperPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
