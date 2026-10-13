# Theos Makefile — build arm64 dylib for iOS
# Requires Theos: https://theos.dev
#   export THEOS=~theos
#   make package

TARGET := iphone:clang:latest:14.0
ARCHS = arm64
DEBUG = 0

LIBRARY_NAME = AstralCheat

AstralCheat_FILES = src/Menu.mm src/Features.mm
AstralCheat_CFLAGS = -fobjc-arc -O2 -Iinclude
AstralCheat_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics
AstralCheat_INSTALL_PATH = /usr/lib

include $(THEOS)/makefiles/common.mk
include $(THEOS)/makefiles/library.mk

# After build: .theos/obj/AstralCheat.dylib
# Inject with insert_dylib / ElleKit / your preferred loader.
