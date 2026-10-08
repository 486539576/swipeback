# ============================================================================
#  SwipeBack (上滑返回) - standalone tweak
#  子项目: AppTweak / SBTweak / PrefsBundle
#  arm64e 新ABI 只能由 macOS/Xcode 编译 -> GitHub Actions 云端构建
# ============================================================================

export TARGET := iphone:clang:latest:14.0
export ARCHS  = arm64e

SUBPROJECTS = AppTweak SBTweak PrefsBundle

include $(THEOS)/makefiles/common.mk
