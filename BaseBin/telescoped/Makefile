TARGET := iphone:clang:latest:16.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = telescoped

telescoped_FILES = main.m
telescoped_CFLAGS = -fobjc-arc
telescoped_CODESIGN_FLAGS = -Sentitlements.plist
telescoped_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/tool.mk
