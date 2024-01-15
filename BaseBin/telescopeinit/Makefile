TARGET := iphone:clang:latest:16.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = telescopeinit

telescopeinit_FILES = main.m
telescopeinit_CFLAGS = -fobjc-arc
telescopeinit_CODESIGN_FLAGS = -Sentitlements.plist
telescopeinit_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/tool.mk
