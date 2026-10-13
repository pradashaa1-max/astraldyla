// language: Objective-C++, file: Menu.mm, target: iOS arm64
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include "State.h"
#include <cmath>

extern void Astral_FeaturesTick();
extern void Astral_EnsureFOVOverlay(UIWindow* win);

@interface ACH : NSObject
+ (void)start;
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

static __weak UIWindow* g_window = nil;
static __weak UIView* g_panel = nil;
static __weak UIView* g_fab = nil;
static CADisplayLink* g_tick = nil;
static UITextField* g_secureTF = nil;

static UIColor* C(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static void applyHideRecording(bool on) {
    dispatch_async(dispatch_get_main_queue(), ^{
        g_hideRec.store(on);
        for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow* w in ((UIWindowScene*)s).windows) {
                if (on) {
                    if (!objc_getAssociatedObject(w, "astral_sec")) {
                        UITextField* tf = [[UITextField alloc] initWithFrame:w.bounds];
                        tf.secureTextEntry = YES;
                        tf.userInteractionEnabled = NO;
                        tf.backgroundColor = UIColor.clearColor;
                        [w addSubview:tf];
                        [w sendSubviewToBack:tf];
                        objc_setAssociatedObject(w, "astral_sec", tf, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        g_secureTF = tf;
                    }
                    if (g_panel) [g_panel.superview bringSubviewToFront:g_panel];
                    if (g_fab) [g_fab.superview bringSubviewToFront:g_fab];
                } else {
                    UITextField* tf = objc_getAssociatedObject(w, "astral_sec");
                    if (tf) {
                        [tf removeFromSuperview];
                        objc_setAssociatedObject(w, "astral_sec", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    }
                }
            }
        }
        UIWindow* key = nil;
        for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow* w in ((UIWindowScene*)s).windows)
                if (w.isKeyWindow) { key = w; break; }
            if (key) break;
        }
        if (key && on && g_panel) {
            UITextField* tf = objc_getAssociatedObject(key, "astral_sec");
            if (tf) {
                UIView* sec = nil;
                for (UIView* v in tf.subviews) { sec = v; break; }
                if (sec) {
                    [sec addSubview:g_panel];
                    if (g_fab) [sec addSubview:g_fab];
                }
            }
        }
    });
}

static UIView* makeRow(NSString* title, NSString* sub, bool on, void(^cb)(bool)) {
    UIView* row = [[UIView alloc] initWithFrame:CGRectMake(10,0,300,54)];
    row.backgroundColor = C(0.08,0.10,0.16,0.95);
    row.layer.cornerRadius = 10;
    row.layer.borderWidth = 1;
    row.layer.borderColor = C(0.15,0.35,0.7,0.5).CGColor;

    UILabel* t = [[UILabel alloc] initWithFrame:CGRectMake(14,8,200,20)];
    t.text = title; t.textColor = UIColor.whiteColor;
    t.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [row addSubview:t];

    UILabel* s = [[UILabel alloc] initWithFrame:CGRectMake(14,28,200,16)];
    s.text = sub; s.textColor = C(0.55,0.65,0.8,1);
    s.font = [UIFont systemFontOfSize:11];
    [row addSubview:s];

    UISwitch* sw = [[UISwitch alloc] initWithFrame:CGRectMake(240,12,51,31)];
    sw.on = on;
    sw.onTintColor = C(0.2,0.5,1,1);
    [sw addAction:[UIAction actionWithHandler:^(__kindof UIAction* a) {
        cb(((UISwitch*)a.sender).on);
    }] forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];
    return row;
}

static void rebuildPanel() {
    UIView* panel = g_panel;
    if (!panel) return;
    for (UIView* v in panel.subviews) [v removeFromSuperview];

    UIView* head = [[UIView alloc] initWithFrame:CGRectMake(0,0,320,48)];
    head.backgroundColor = C(0.06,0.12,0.22,1);
    UILabel* title = [[UILabel alloc] initWithFrame:CGRectMake(0,10,320,28)];
    title.text = @"ASTRAL CHEATS";
    title.textColor = C(0.4,0.75,1,1);
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBlack];
    title.textAlignment = NSTextAlignmentCenter;
    [head addSubview:title];
    [panel addSubview:head];

    CGFloat y = 56;
    auto add = [&](UIView* row) {
        row.frame = CGRectMake(10, y, 300, 54);
        [panel addSubview:row];
        y += 60;
    };
    add(makeRow(@"Aim bot", @"Auto aim at enemies", g_aimbot.load(), ^(bool v){ g_aimbot.store(v); }));
    add(makeRow(@"Silent aim", @"Hidden aim assist", g_silent.load(), ^(bool v){ g_silent.store(v); }));
    add(makeRow(@"FOV Circle", @"Show aim FOV", g_fovDraw.load(), ^(bool v){ g_fovDraw.store(v); }));
    add(makeRow(@"ESP Name", @"Show enemy tags", g_espName.load(), ^(bool v){ g_espName.store(v); }));
    add(makeRow(@"ESP Distance", @"Show distance", g_espDist.load(), ^(bool v){ g_espDist.store(v); }));
    add(makeRow(@"Team check", @"Skip teammates", g_espTeam.load(), ^(bool v){ g_espTeam.store(v); }));
    add(makeRow(@"Hide Recording", @"Hide menu from screen record", g_hideRec.load(), ^(bool v){ applyHideRecording(v); }));

    UILabel* fl = [[UILabel alloc] initWithFrame:CGRectMake(20,y,80,24)];
    fl.text = [NSString stringWithFormat:@"FOV %.0f", g_fov.load()];
    fl.textColor = UIColor.whiteColor;
    fl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    fl.tag = 9001;
    [panel addSubview:fl];
    UISlider* sl = [[UISlider alloc] initWithFrame:CGRectMake(100,y,200,30)];
    sl.minimumValue = 1; sl.maximumValue = 30; sl.value = g_fov.load();
    sl.minimumTrackTintColor = C(0.25,0.55,1,1);
    [sl addAction:[UIAction actionWithHandler:^(__kindof UIAction* a) {
        float v = ((UISlider*)a.sender).value;
        g_fov.store(v);
        ((UILabel*)[panel viewWithTag:9001]).text = [NSString stringWithFormat:@"FOV %.0f", v];
    }] forControlEvents:UIControlEventValueChanged];
    [panel addSubview:sl];
    y += 40;

    UILabel* tip = [[UILabel alloc] initWithFrame:CGRectMake(10,y,300,20)];
    tip.text = @"Drag header to move · A button toggles";
    tip.textColor = C(0.4,0.5,0.6,1);
    tip.font = [UIFont systemFontOfSize:10];
    tip.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:tip];
    y += 28;

    panel.frame = CGRectMake(panel.frame.origin.x, panel.frame.origin.y, 320, y + 8);
}

@implementation ACH
+ (void)start {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (int i = 0; i <= 20; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [ACH bootstrap]; });
        }
    });
}

+ (UIWindow*)findHostWindow {
    for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene* ws = (UIWindowScene*)s;
        for (UIWindow* w in ws.windows)
            if (w.isKeyWindow && !w.hidden) return w;
        if (ws.windows.count) return ws.windows.firstObject;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (UIApplication.sharedApplication.keyWindow)
        return UIApplication.sharedApplication.keyWindow;
    for (UIWindow* w in UIApplication.sharedApplication.windows)
        if (!w.hidden) return w;
#pragma clang diagnostic pop
    return nil;
}

+ (void)onTick { Astral_FeaturesTick(); }

+ (void)bootstrap {
    if (g_fab) return;
    UIWindow* host = [ACH findHostWindow];
    if (!host) return;
    UIView* root = host.rootViewController.view ?: host;
    if (!root) return;
    g_window = host;

    Astral_EnsureFOVOverlay(host);
    if (!g_tick) {
        g_tick = [CADisplayLink displayLinkWithTarget:self selector:@selector(onTick)];
        g_tick.preferredFramesPerSecond = 60;
        [g_tick addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }

    UIView* fab = [[UIView alloc] initWithFrame:CGRectMake(18, 110, 54, 54)];
    fab.backgroundColor = C(0.12,0.42,0.98,0.95);
    fab.layer.cornerRadius = 27;
    fab.layer.borderWidth = 2;
    fab.layer.borderColor = UIColor.whiteColor.CGColor;
    fab.layer.shadowOpacity = 0.6; fab.layer.shadowRadius = 6;
    UILabel* fl = [[UILabel alloc] initWithFrame:fab.bounds];
    fl.text = @"A"; fl.textColor = UIColor.whiteColor;
    fl.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBlack];
    fl.textAlignment = NSTextAlignmentCenter;
    fl.userInteractionEnabled = NO;
    [fab addSubview:fl];
    [root addSubview:fab];
    [root bringSubviewToFront:fab];
    g_fab = fab;
    [fab addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMenu)]];
    [fab addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];

    UIView* panel = [[UIView alloc] initWithFrame:CGRectMake(80, 50, 320, 520)];
    panel.backgroundColor = C(0.04,0.06,0.10,0.97);
    panel.layer.cornerRadius = 16;
    panel.layer.borderWidth = 1.5;
    panel.layer.borderColor = C(0.2,0.45,0.95,0.8).CGColor;
    panel.layer.shadowOpacity = 0.5; panel.layer.shadowRadius = 12;
    panel.hidden = !g_menuOpen.load();
    [root addSubview:panel];
    [root bringSubviewToFront:panel];
    g_panel = panel;
    rebuildPanel();
    [panel addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification* n){
            if (g_hideRec.load()) applyHideRecording(YES);
            if (g_fab) [g_fab.superview bringSubviewToFront:g_fab];
            if (g_panel) [g_panel.superview bringSubviewToFront:g_panel];
        }];
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
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
        object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(__unused NSNotification* n){ [ACH start]; }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(__unused NSNotification* n){ [ACH start]; }];
}
