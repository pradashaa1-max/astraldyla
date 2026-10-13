// language: Objective-C++, file: Menu.mm, target: iOS arm64
// Overlay window (doesn't block game) + section menu + secure hide-rec

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include "State.h"
#include <cmath>

extern void Astral_FeaturesTick();
extern void Astral_EnsureFOVOverlay(UIWindow* win);

// ESP/FOV parent — set to secure host when hide-rec on, else overlay root
UIView* Astral_SecureRoot = nil;

@interface ACH : NSObject
+ (void)start;
@end

@interface ACW : UIWindow
@end
@implementation ACW
// Pass touches through empty areas so game keeps working
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    UIView* hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) return nil;
    // also ignore secure field / host empty areas
    NSString* cls = NSStringFromClass(hit.class);
    if ([cls containsString:@"TextField"] || hit.tag == 0xSEC1) {
        // only count if a real subview (fab/panel) is under point
        BOOL real = NO;
        for (UIView* s in hit.subviews) {
            CGPoint p = [hit convertPoint:point toView:s];
            if (!s.hidden && s.userInteractionEnabled && CGRectContainsPoint(s.bounds, p)) {
                UIView* h2 = [s hitTest:p withEvent:event];
                if (h2) return h2;
            }
        }
        return nil;
    }
    return hit;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape | UIInterfaceOrientationMaskPortrait;
}
@end

@interface ACVC : UIViewController
@end
@implementation ACVC
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}
- (BOOL)shouldAutorotate { return YES; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.userInteractionEnabled = YES;
}
@end

std::atomic<bool> g_aimbot{false};
std::atomic<bool> g_silent{false};
std::atomic<bool> g_fovDraw{true};
std::atomic<bool> g_espName{false};
std::atomic<bool> g_espDist{false};
std::atomic<bool> g_espSnap{false};
std::atomic<bool> g_espTeam{true};
std::atomic<bool> g_hideRec{false};
std::atomic<float> g_fov{15.f};
std::atomic<bool> g_menuOpen{true};

static ACW* g_overlay = nil;
static __weak UIView* g_panel = nil;
static __weak UIView* g_fab = nil;
static __weak UIView* g_content = nil;
static CADisplayLink* g_tick = nil;
static UITextField* g_secureField = nil;
static UIView* g_uiRoot = nil; // normal or secure host for cheat UI
static int g_section = 0;

static UIColor* C(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static UIView* overlayRoot() {
    return g_overlay.rootViewController.view ?: g_overlay;
}

static void placeUI(UIView* parent) {
    if (!parent) return;
    g_uiRoot = parent;
    Astral_SecureRoot = parent;
    if (g_panel && g_panel.superview != parent) [parent addSubview:g_panel];
    if (g_fab && g_fab.superview != parent) [parent addSubview:g_fab];
    [parent bringSubviewToFront:g_panel];
    [parent bringSubviewToFront:g_fab];
}

static void applyHideRecording(bool on) {
    dispatch_async(dispatch_get_main_queue(), ^{
        g_hideRec.store(on);
        if (!g_overlay) return;
        UIView* root = overlayRoot();
        if (!root) return;

        if (on) {
            if (!g_secureField) {
                g_secureField = [[UITextField alloc] initWithFrame:root.bounds];
                g_secureField.secureTextEntry = YES;
                g_secureField.userInteractionEnabled = YES;
                g_secureField.backgroundColor = UIColor.clearColor;
                g_secureField.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
                g_secureField.tag = 0xSEC0;
                [root addSubview:g_secureField];
            }
            UIView* container = g_secureField.subviews.firstObject ?: g_secureField;
            container.userInteractionEnabled = YES;
            container.tag = 0xSEC1;
            // host inside secure container
            UIView* host = [container viewWithTag:0xSEC2];
            if (!host) {
                host = [[UIView alloc] initWithFrame:root.bounds];
                host.tag = 0xSEC2;
                host.backgroundColor = UIColor.clearColor;
                host.userInteractionEnabled = YES;
                host.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
                [container addSubview:host];
            }
            placeUI(host);
            [root bringSubviewToFront:g_secureField];
        } else {
            placeUI(root);
            if (g_secureField) {
                [g_secureField removeFromSuperview];
                g_secureField = nil;
            }
        }
    });
}

static UIView* makeSwitch(NSString* title, NSString* sub, bool on, void(^cb)(bool)) {
    UIView* row = [[UIView alloc] initWithFrame:CGRectMake(0,0,248,50)];
    row.backgroundColor = C(0.08,0.10,0.16,1);
    row.layer.cornerRadius = 10;
    row.layer.borderWidth = 1;
    row.layer.borderColor = C(0.18,0.42,0.9,0.4).CGColor;

    UILabel* t = [[UILabel alloc] initWithFrame:CGRectMake(12,6,155,18)];
    t.text = title; t.textColor = UIColor.whiteColor;
    t.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [row addSubview:t];

    UILabel* s = [[UILabel alloc] initWithFrame:CGRectMake(12,26,155,14)];
    s.text = sub; s.textColor = C(0.5,0.6,0.75,1);
    s.font = [UIFont systemFontOfSize:10];
    [row addSubview:s];

    UISwitch* sw = [[UISwitch alloc] initWithFrame:CGRectMake(188,9,51,31)];
    sw.transform = CGAffineTransformMakeScale(0.8, 0.8);
    sw.on = on;
    sw.onTintColor = C(0.22,0.5,1,1);
    [sw addAction:[UIAction actionWithHandler:^(__kindof UIAction* a) {
        cb(((UISwitch*)a.sender).on);
    }] forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];
    return row;
}

static void rebuildContent() {
    UIView* content = g_content;
    if (!content) return;
    for (UIView* v in content.subviews) [v removeFromSuperview];
    CGFloat y = 8;
    auto add = [&](UIView* row) {
        row.frame = CGRectMake(8, y, 248, 50);
        [content addSubview:row];
        y += 56;
    };
    if (g_section == 0) {
        add(makeSwitch(@"Aim bot", @"Auto aim", g_aimbot.load(), ^(bool v){ g_aimbot.store(v); }));
        add(makeSwitch(@"Silent", @"Hidden aim", g_silent.load(), ^(bool v){ g_silent.store(v); }));
        add(makeSwitch(@"FOV Circle", @"Draw ring", g_fovDraw.load(), ^(bool v){ g_fovDraw.store(v); }));
        UILabel* fl = [[UILabel alloc] initWithFrame:CGRectMake(12,y,60,20)];
        fl.text = [NSString stringWithFormat:@"FOV %.0f", g_fov.load()];
        fl.textColor = UIColor.whiteColor;
        fl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        fl.tag = 9001;
        [content addSubview:fl];
        UISlider* sl = [[UISlider alloc] initWithFrame:CGRectMake(72,y,176,28)];
        sl.minimumValue = 1; sl.maximumValue = 30; sl.value = g_fov.load();
        sl.minimumTrackTintColor = C(0.25,0.55,1,1);
        [sl addAction:[UIAction actionWithHandler:^(__kindof UIAction* a) {
            float v = ((UISlider*)a.sender).value;
            g_fov.store(v);
            ((UILabel*)[content viewWithTag:9001]).text = [NSString stringWithFormat:@"FOV %.0f", v];
        }] forControlEvents:UIControlEventValueChanged];
        [content addSubview:sl];
    } else if (g_section == 1) {
        add(makeSwitch(@"ESP Name", @"Enemy tags", g_espName.load(), ^(bool v){ g_espName.store(v); }));
        add(makeSwitch(@"ESP Distance", @"Meters", g_espDist.load(), ^(bool v){ g_espDist.store(v); }));
        add(makeSwitch(@"Snaplines", @"Lines", g_espSnap.load(), ^(bool v){ g_espSnap.store(v); }));
        add(makeSwitch(@"Team check", @"Skip team", g_espTeam.load(), ^(bool v){ g_espTeam.store(v); }));
    } else {
        add(makeSwitch(@"Hide Recording", @"Hide UI on record/screenshot", g_hideRec.load(), ^(bool v){ applyHideRecording(v); }));
    }
}

static void rebuildPanel() {
    UIView* panel = g_panel;
    if (!panel) return;
    for (UIView* v in panel.subviews) [v removeFromSuperview];

    UIView* head = [[UIView alloc] initWithFrame:CGRectMake(0,0,370,42)];
    head.backgroundColor = C(0.06,0.12,0.22,1);
    UILabel* title = [[UILabel alloc] initWithFrame:CGRectMake(0,8,370,26)];
    title.text = @"ASTRAL";
    title.textColor = C(0.4,0.75,1,1);
    title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBlack];
    title.textAlignment = NSTextAlignmentCenter;
    [head addSubview:title];
    [panel addSubview:head];

    UIView* side = [[UIView alloc] initWithFrame:CGRectMake(0,42,110,280)];
    side.backgroundColor = C(0.05,0.07,0.11,1);
    NSArray* names = @[@"Aim", @"Visuals", @"Misc"];
    for (int i = 0; i < 3; i++) {
        UIButton* b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.tag = i;
        b.frame = CGRectMake(8, 12+i*44, 94, 36);
        [b setTitle:names[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        b.layer.cornerRadius = 8;
        if (g_section == i) {
            b.backgroundColor = C(0.15,0.4,0.95,0.95);
            [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        } else {
            b.backgroundColor = C(0.09,0.11,0.16,1);
            [b setTitleColor:C(0.55,0.7,0.9,1) forState:UIControlStateNormal];
        }
        [b addTarget:[ACH class] action:@selector(sideTap:) forControlEvents:UIControlEventTouchUpInside];
        [side addSubview:b];
    }
    [panel addSubview:side];

    UIView* content = [[UIView alloc] initWithFrame:CGRectMake(110,42,260,280)];
    content.backgroundColor = C(0.05,0.07,0.11,1);
    [panel addSubview:content];
    g_content = content;
    rebuildContent();
    panel.frame = CGRectMake(panel.frame.origin.x, panel.frame.origin.y, 370, 322);
}

@implementation ACH
+ (void)sideTap:(UIButton*)b {
    g_section = (int)b.tag;
    rebuildPanel();
}

+ (void)start {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (int i = 0; i <= 20; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [ACH bootstrap]; });
        }
    });
}

+ (UIWindowScene*)activeScene {
    for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] &&
            s.activationState == UISceneActivationStateForegroundActive)
            return (UIWindowScene*)s;
    }
    for (UIScene* s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class]) return (UIWindowScene*)s;
    return nil;
}

+ (void)onTick { Astral_FeaturesTick(); }

+ (void)bootstrap {
    if (g_overlay) return;
    UIWindowScene* scene = [ACH activeScene];
    if (!scene) return;

    CGRect bounds = scene.coordinateSpace.bounds;
    if (bounds.size.width < 10) bounds = UIScreen.mainScreen.bounds;

    ACW* win = [[ACW alloc] initWithWindowScene:scene];
    win.frame = bounds;
    win.windowLevel = UIWindowLevelAlert + 50;
    win.backgroundColor = UIColor.clearColor;
    win.rootViewController = [ACVC new];
    win.hidden = NO;
    g_overlay = win;

    UIView* root = win.rootViewController.view;
    root.frame = bounds;
    Astral_SecureRoot = root;
    g_uiRoot = root;

    Astral_EnsureFOVOverlay(win);

    if (!g_tick) {
        g_tick = [CADisplayLink displayLinkWithTarget:self selector:@selector(onTick)];
        g_tick.preferredFramesPerSecond = 60;
        [g_tick addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }

    // FAB
    UIView* fab = [[UIView alloc] initWithFrame:CGRectMake(16, 100, 52, 52)];
    fab.backgroundColor = C(0.12,0.42,0.98,0.95);
    fab.layer.cornerRadius = 26;
    fab.layer.borderWidth = 2;
    fab.layer.borderColor = UIColor.whiteColor.CGColor;
    fab.layer.shadowOpacity = 0.55; fab.layer.shadowRadius = 6;
    UILabel* fl = [[UILabel alloc] initWithFrame:fab.bounds];
    fl.text = @"A"; fl.textColor = UIColor.whiteColor;
    fl.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBlack];
    fl.textAlignment = NSTextAlignmentCenter;
    fl.userInteractionEnabled = NO;
    [fab addSubview:fl];
    [root addSubview:fab];
    g_fab = fab;
    [fab addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMenu)]];
    [fab addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];

    // Panel
    UIView* panel = [[UIView alloc] initWithFrame:CGRectMake(70, 48, 370, 322)];
    panel.backgroundColor = C(0.04,0.06,0.1,0.97);
    panel.layer.cornerRadius = 14;
    panel.layer.borderWidth = 1.5;
    panel.layer.borderColor = C(0.2,0.45,0.95,0.85).CGColor;
    panel.layer.shadowOpacity = 0.45; panel.layer.shadowRadius = 10;
    panel.clipsToBounds = YES;
    panel.hidden = !g_menuOpen.load();
    [root addSubview:panel];
    g_panel = panel;
    rebuildPanel();
    [panel addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];

    if (g_hideRec.load()) applyHideRecording(YES);
}

+ (void)toggleMenu {
    bool open = !g_menuOpen.load();
    g_menuOpen.store(open);
    if (g_panel) g_panel.hidden = !open;
}
+ (void)drag:(UIPanGestureRecognizer*)g {
    UIView* v = g.view;
    if (!v.superview) return;
    CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [g setTranslation:CGPointZero inView:v.superview];
}
@end

__attribute__((constructor))
static void astral_init() {
    dispatch_async(dispatch_get_main_queue(), ^{ [ACH start]; });
    [ACH start];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(__unused NSNotification* n){ [ACH start]; }];
}
