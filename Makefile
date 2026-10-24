# ─────────────────────────────────────────────────────────────────────────────
# ReStats — Rootless Makefile
# THEOS_PACKAGE_SCHEME must be declared before common.mk is included.
# ─────────────────────────────────────────────────────────────────────────────

THEOS_PACKAGE_SCHEME = rootless
TARGET               := clang:latest:15.0
ARCHS                := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ReStats

ReStats_FILES                 = Tweak.xm
ReStats_CFLAGS                = -fobjc-arc \
                                -Wno-deprecated-declarations \
                                -Wno-unused-variable
ReStats_FRAMEWORKS            = UIKit Foundation
ReStats_PRIVATE_FRAMEWORKS    = Preferences

# Kill and relaunch Preferences on `make install` for rapid iteration.
ReStats_INSTALL_TARGET_PROCESSES = Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
