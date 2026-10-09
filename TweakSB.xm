// ============================================================================
//  上滑返回 —— 系统层（SpringBoard）
//  严谨版：接管系统底部手势识别器 SBHomeGesturePanGestureRecognizer
//  - 触摸起点在「触发角落」：取消系统手势（阻止回桌面/后台/带动 App），
//    并通过 Darwin 通知通知前台 App 执行「返回上一级」。
//  - 触摸起点在屏幕中间：不干预，系统原生行为保留
//    （上滑到中间 = 呼出后台，二次上滑 = 回桌面）。
// ============================================================================

#import <UIKit/UIKit.h>
#import <substrate.h>
#import <notify.h>

#define SB_PREFS_DOMAIN @"com.doubao.swipeback"
#define SB_NOTIFY_BACK  "com.doubao.swipeback.back"

// 告知编译器 SBHomeGesturePanGestureRecognizer 是 UIGestureRecognizer 子类
@interface SBHomeGesturePanGestureRecognizer : UIGestureRecognizer
@end

static BOOL    gEnabled     = NO;
static int     gArea        = 2;   // 0=左下角 1=右下角 2=两侧
static CGFloat gSensitivity = 0.5f;

static CGPoint gStart;            // 本次触摸起点
static BOOL    gInCorner = NO;    // 起点是否在触发角落
static BOOL    gHandled  = NO;    // 本次是否已拦截并通知

static void sbLoadPrefs(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.doubao.swipeback.plist"];
    if (!d) d = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.doubao.swipeback.plist"];
    if (d) {
        gEnabled     = [[d objectForKey:@"SwipeBackEnabled"] boolValue];
        gArea        = [[d objectForKey:@"SwipeBackArea"] intValue];
        gSensitivity = [[d objectForKey:@"SwipeBackSensitivity"] floatValue];
    }
}

static BOOL sbInCorner(CGPoint p, UIView *v) {
    if (!gEnabled) return NO;
    CGRect b = v.bounds;
    CGFloat zone = 30.0f + 26.0f * gSensitivity;   // 触发区宽度随灵敏度变化
    if (gArea == 0 || gArea == 2) { if (p.x < zone) return YES; }              // 左下角
    if (gArea == 1 || gArea == 2) { if (p.x > b.size.width - zone) return YES; } // 右下角
    return NO;
}

// 取消系统手势：enabled 先关再开，清空本次手势识别状态，阻止其识别回桌面/后台/带动App
static void sbCancelGesture(SBHomeGesturePanGestureRecognizer *gr) {
    BOOL en = gr.enabled;
    gr.enabled = NO;
    gr.enabled = en;
}

%hook SBHomeGesturePanGestureRecognizer
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    %orig;
    UITouch *t = [touches anyObject];
    if (t) {
        gStart    = [t locationInView:self.view];
        gInCorner = sbInCorner(gStart, self.view);
    }
    gHandled = NO;
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (gEnabled && gInCorner && !gHandled) {
        // 首次移动即拦截：取消系统手势 + 通知前台 App 返回上一级
        gHandled = YES;
        sbCancelGesture(self);
        notify_post(SB_NOTIFY_BACK);
    }
    %orig;
}
%end

%ctor {
    sbLoadPrefs();
}
