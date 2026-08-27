export ARCHS := arm64 arm64e
export TARGET := iphone:clang:16.5:15.0

INSTALL_TARGET_PROCESSES := backboardd druid

SUBPROJECTS += Core
SUBPROJECTS += Helper
SUBPROJECTS += Preferences
SUBPROJECTS += Updater

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
