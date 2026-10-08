// ============================================================================
//  上滑返回 —— 设置界面控制器（Preferences bundle）
// ============================================================================

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface SwipeBackPrefsListController : PSListController
@end

@implementation SwipeBackPrefsListController

- (id)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

@end
