TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ReStats

ReStats_FILES = Tweak.xm
ReStats_FRAMEWORKS = UIKit Foundation UserNotifications
ReStats_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
