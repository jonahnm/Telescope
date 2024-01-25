TARGET := iphone:clang:16.5:latest

include $(THEOS)/makefiles/common.mk
   rwildcard = $(foreach d,$(wildcard $1*),$(call rwildcard,$d/,$2) $(filter $2,$d))
TOOL_NAME = Jupiter
Jupiter_FILES = $(call rwildcard,,%.m) $(call rwildcard,,%.c)
Jupiter_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-macro-redefined
Jupiter_INSTALL_PATH = /usr/local/bin
include $(THEOS_MAKE_PATH)/tool.mk
