// ============================================================================
//  上滑返回 —— App 层（加载进所有 App 的 UIKit 进程）
//  功能：在底部角落抢走上滑手势（App 不滚动、不触发主屏），触发真正的"返回上一级"
//  通过过滤 UIKit 加载，运行在每一个 App 内部。
// ============================================================================

#import <UIKit/UIKit.h>
#import <substrate.h>

#define SB_PREFS_DOMAIN @"com.doubao.swipeback"

static BOOL      gEnabled     = NO;
static int       gArea        = 2;   // 0=左侧 1=右侧 2=两侧
static CGFloat   gSensitivity = 0.5f;

// ---- 读取设置（与设置项同域）----
static void loadPrefs(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.doubao.swipeback.plist"];
    if (!d) d = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.doubao.swipeback.plist"];
    if (d) {
        gEnabled     = [[d objectForKey:@"SwipeBackEnabled"] boolValue];
        gArea        = [[d objectForKey:@"SwipeBackArea"] intValue];
        gSensitivity = [[d objectForKey:@"SwipeBackSensitivity"] floatValue];
        if (gSensitivity < 0.05f) gSensitivity = 0.5f;
    }
}

// ---- 判定是否处于触发区域（底部角落）----
static BOOL bxInTriggerArea(CGPoint p, UIView *v) {
    if (!gEnabled) return NO;
    CGRect b = v.bounds;
    CGFloat zone = 28.0f + 24.0f * gSensitivity;   // 触发区宽度随灵敏度变化
    if (gArea == 0 || gArea == 2) { if (p.x < zone) return YES; }            // 左下角
    if (gArea == 1 || gArea == 2) { if (p.x > b.size.width - zone) return YES; } // 右下角
    return NO;
}

// ---- 找到当前最上层可返回的控制器 ----
static UIViewController *bxTopViewController(UIViewController *root) {
    UIViewController *t = root;
    while (t.presentedViewController) t = t.presentedViewController;
    if ([t isKindOfClass:[UITabBarController class]]) {
        UIViewController *sel = ((UITabBarController *)t).selectedViewController;
        if (sel) t = sel;
    }
    if ([t isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)t;
        if (nav.viewControllers.count > 0) t = nav.topViewController;
    }
    return t;
}

// ---- 执行返回上一级 ----
static void bxTriggerBack(UIView *view) {
    UIWindow *win = (UIWindow *)view;
    UIViewController *root = win.rootViewController;
    if (!root) return;

    UIViewController *top = bxTopViewController(root);

    // 1) 导航控制器可返回 -> pop
    UINavigationController *nav = top.navigationController;
    if (nav && nav.viewControllers.count > 1) {
        [nav popViewControllerAnimated:YES];
        return;
    }
    // 2) 有被 present 的模态 -> dismiss
    if (top.presentingViewController && ![top isKindOfClass:[UIAlertController class]]) {
        [top dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    // 3) webview 内可返回
    if ([top respondsToSelector:@selector(webView)]) {
        id wv = [top valueForKey:@"webView"];
        if (wv && [wv respondsToSelector:@selector(canGoBack)] && [wv canGoBack]) {
            [wv goBack];
            return;
        }
    }
    // 4) 栈内还有其它页面（tab/其他）时尝试 pop 最外层
    UIViewController *last = root;
    while (last.presentedViewController) last = last.presentedViewController;
    if ([last isKindOfClass:[UINavigationController class]]) {
        UINavigationController *lnav = (UINavigationController *)last;
        if (lnav.viewControllers.count > 1) {
            [lnav popViewControllerAnimated:YES];
        }
    }
}

// ---- 手势代理：决定何时接管触摸 ----
@interface BXSwipePanRecognizer : UIPanGestureRecognizer
@end

@interface BXSwipePanDelegate : NSObject <UIGestureRecognizerDelegate>
@end
@implementation BXSwipePanDelegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldReceiveTouch:(UITouch *)touch {
    CGPoint p = [touch locationInView:gr.view];
    return bxInTriggerArea(p, gr.view);   // 只接角落触摸
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;                            // 不与其他手势同时，抢占后让滚动失效
}
@end

@implementation BXSwipePanRecognizer
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gr {
    // 只在上滑时生效
    UIPanGestureRecognizer *p = (UIPanGestureRecognizer *)gr;
    CGPoint v = [p velocityInView:p.view];
    if (v.y >= -8.0f) return NO;
    return YES;
}
@end

static BXSwipePanDelegate   *gPanDelegate;
static BXSwipePanRecognizer *gPan;

static void bxInstallOnWindow(UIWindow *win) {
    if (!win || gPan) return;
    gPan = [[BXSwipePanRecognizer alloc] initWithTarget:gPanDelegate action:@selector(bxOnPan:)];
    gPan.cancelsTouchesInView = YES;      // 识别后取消视图触摸 -> App 不滚动
    gPan.maximumNumberOfTouches = 1;
    gPan.delegate = gPanDelegate;
    [win addGestureRecognizer:gPan];
}

@implementation BXSwipePanDelegate
- (void)bxOnPan:(UIPanGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateBegan) {
        // 识别即触发返回；cancelsTouchesInView 已让 App 停止滚动
        bxTriggerBack(gr.view);
    }
}
@end

%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    if (!gPanDelegate) gPanDelegate = [BXSwipePanDelegate new];
    bxInstallOnWindow(self);
}
- (void)setRootViewController:(UIViewController *)rootViewController {
    %orig;
    if (!gPanDelegate) gPanDelegate = [BXSwipePanDelegate new];
    bxInstallOnWindow(self);
}
%end

%ctor {
    loadPrefs();
    gPanDelegate = [BXSwipePanDelegate new];
    // 等 UI 起来后给主窗口装手势
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if (w) bxInstallOnWindow(w);
    });
}
