# App 层 tweak 的独立构建文件：SwipeBackApp.dylib
ARCHS = arm64e
TARGET := iphone:clang:latest:14.0

TWEAK_NAME = SwipeBackApp
SwipeBackApp_FILES = TweakApp.xm
SwipeBackApp_CFLAGS = -fobjc-arc
SwipeBackApp_FRAMEWORKS = UIKit Foundation CoreGraphics
SwipeBackApp_LIBRARIES = substrate
SwipeBackApp_LDFLAGS = -Wl,-install_name,@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/SwipeBackApp.dylib

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
