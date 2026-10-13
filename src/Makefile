THEOS_PACKAGE_SCHEME = roothide
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard assistantd

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SiriGemini

SiriGemini_FILES = Tweak.x GeminiWebClient.m
SiriGemini_CFLAGS = -fobjc-arc
SiriGemini_FRAMEWORKS = Foundation UIKit AVFoundation
# NOTE: AssistantServices 등 private framework는 런타임(objc_getClass/msgSend)으로만
# 접근하므로 링크하지 않는다. SDK에 .tbd가 없어 링크 실패(ld: framework not found) 유발.
# (2026-10-13 VM 실측: iPhoneOS16.5.sdk에 AssistantServices.tbd 없음)

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
