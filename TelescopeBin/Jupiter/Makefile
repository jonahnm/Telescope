TARGET := iphone:clang:latest:14.0
include $(THEOS)/makefiles/common.mk
   rwildcard = $(foreach d,$(wildcard $1*),$(call rwildcard,$d/,$2) $(filter $2,$d))
TWEAK_NAME = Jupiter
Jupiter_FILES = $(call rwildcard,,%.m) $(call rwildcard,,%.x) $(call rwildcard,,%.c) $(call rwildcard,,Swift/%.swift)
Jupiter_FILES := $(filter-out $(call rwildcard,,%Package.swift),$(Jupiter_FILES))
Jupiter_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-macro-redefined -Wno-deprecated-declarations -Wno-unused-but-set-variable -Wno-int-conversion -Wno-format -Wno-ambiguous-macro -Wno-unused-function
Jupiter_INSTALL_PATH = /usr/local/bin
Jupiter_FRAMEWORKS = Foundation CoreServices Security IOKit UIKit
include $(THEOS_MAKE_PATH)/tweak.mk