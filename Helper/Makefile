TWEAK_NAME := KayokoHelper

KayokoHelper_USE_MODULES := 0

KayokoHelper_FILES += KayokoHelper.m
KayokoHelper_FILES += KayokoHelperConfiguration.m
KayokoHelper_FILES += KayokoHelperProcessContext.m
KayokoHelper_FILES += KayokoHelperLocalization.m
KayokoHelper_FILES += KayokoHelperRuntime.m

KayokoHelper_CFLAGS += -fobjc-arc
KayokoHelper_CFLAGS += -I../Preferences

KayokoHelper_FRAMEWORKS += CoreGraphics
KayokoHelper_FRAMEWORKS += QuartzCore
KayokoHelper_FRAMEWORKS += UIKit
KayokoHelper_FRAMEWORKS += AudioToolbox

KayokoHelper_LIBRARIES += substrate
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
KayokoHelper_LIBRARIES += roothide
endif

ifneq ($(filter rootless roothide,$(THEOS_PACKAGE_SCHEME)),)
KayokoHelper_INSTALL_PATH := /usr/lib/TweakInject
endif

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
include $(THEOS_MAKE_PATH)/tweak.mk
