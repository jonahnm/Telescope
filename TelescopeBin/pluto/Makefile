TARGET := iphone:clang:latest:latest
INSTALL_TARGET_PROCESSES = lsd cfprefsd
FINALPACKAGE = 1
THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = pluto

pluto_FILES = main.x installd.x cfprefsd.x
pluto_CFLAGS = -fobjc-arc
pluto_LDFLAGS = -rpath @loader_path/fallback

include $(THEOS_MAKE_PATH)/tweak.mk
