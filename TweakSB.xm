// ============================================================================
//  上滑返回 —— 系统层（SpringBoard）
//  功能：当触摸从底部触发角落开始上滑时，把系统的主屏手势（Home）吞掉，
//        避免"返回上一级"被误判成"回桌面"。
// ============================================================================

#import <UIKit/UIKit.h>
#import <substrate.h>

static BOOL    gEnabled     = NO;
static int     gArea        = 2;
static CGFloat gSensitivity = 0.5f;

static void sbLoadPrefs(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.doubao.swipeback.plist"];
    if (!d) d = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.doubao.swipeback.plist"];
    if (d) {
        gEnabled     = [[d objectForKey:@"SwipeBackEnabled"] boolValue];
        gArea        = [[d objectForKey:@"SwipeBackArea"] intValue];
        gSensitivity = [[d objectForKey:@"SwipeBackSensitivity"] floatValue];
    }
}

static BOOL sbInTriggerArea(CGPoint p, UIView *v) {
    if (!gEnabled) return NO;
    CGRect b = v.bounds;
    CGFloat zone = 28.0f + 24.0f * gSensitivity;
    if (gArea == 0 || gArea == 2) { if (p.x < zone) return YES; }
    if (gArea == 1 || gArea == 2) { if (p.x > b.size.width - zone) return YES; }
    return NO;
}

// 勾住系统底部主屏手势：若触摸起点在触发角落，则重置该手势（取消），
// 让它不再识别为"返回桌面/后台"，从而把这次上滑留给 App 层去"返回上一级"。
%hook SBHomeGesturePanGestureRecognizer
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    %orig;
    UITouch *t = [touches anyObject];
    CGPoint p = [t locationInView:self.view];
    if (sbInTriggerArea(p, self.view)) {
        BOOL wasEnabled = self.enabled;
        self.enabled = NO;   // 先停用再启用 -> 清空本次手势状态，阻止其识别
        self.enabled = wasEnabled;
    }
}
%end

%ctor {
    sbLoadPrefs();
}
