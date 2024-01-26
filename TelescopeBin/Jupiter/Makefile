TARGET := iphone:clang:latest:14.0
THEOS_PLATFORM_SDK_ROOT := ~/theos/sdks
include $(THEOS)/makefiles/common.mk
   rwildcard = $(foreach d,$(wildcard $1*),$(call rwildcard,$d/,$2) $(filter $2,$d))
TOOL_NAME = Jupiter
Jupiter_FILES = $(call rwildcard,,%.m)
Jupiter_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-macro-redefined -Wno-deprecated-declarations -Wno-unused-but-set-variable -Wno-int-conversion -Wno-format
Jupiter_INSTALL_PATH = /usr/local/bin
Jupiter_FRAMEWORKS = Foundation CoreServices Security IOKit UIKit
include $(THEOS_MAKE_PATH)/tool.mk