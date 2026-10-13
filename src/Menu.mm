// language: Objective-C++, file: Menu.mm, target: iOS arm64
// Sectioned menu + secure hide-recording for menu/ESP/FOV

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include "State.h"
#include <cmath>

extern void Astral_FeaturesTick();
extern void Astral_EnsureFOVOverlay(UIWindow* win);
// Features will put ESP/FOV into this container when set
extern UIView* Astral_SecureRoot;
UIView* Astral_SecureRoot = nil;

@interface ACH : NSObject
+ (void)start;
+ (void)setSection:(int)s;
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
static __weak UIView* g_content = nil;
static CADisplayLink* g_tick = nil;
static UITextField* g_secureField = nil;
static UIView* g_secureHost = nil; // subview of secure field that holds all cheat UI
static int g_section = 0; // 0 aim, 1 visuals, 2 misc

static UIColor* C(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

// Build / refresh secure host that is invisible to screenshots & screen recording
static UIView* ensureSecureHost(UIView* root) {
    if (g_secureHost && g_secureHost.superview) return g_secureHost;
    if (!root) return nil;

    // Full-screen secure text field — its internal layer is not captured
    if (!g_secureField) {
        g_secureField = [[UITextField alloc] initWithFrame:root.bounds];
        g_secureField.secureTextEntry = YES;
        g_secureField.userInteractionEnabled = YES;
        g_secureField.backgroundColor = UIColor.clearColor;
        g_secureField.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [root addSubview:g_secureField];
    }

    // Find the secure container inside the text field
    UIView* container = nil;
    for (UIView* v in g_secureField.subviews) {
        container = v;
        break;
    }
    if (!container) {
        // fallback: use the field itself
        container = g_secureField;
    }
    container.userInteractionEnabled = YES;

    // Transparent host that holds menu + will hold ESP
    if (!g_secureHost) {
        g_secureHost = [[UIView alloc] initWithFrame:root.bounds];
        g_secureHost.backgroundColor = UIColor.clearColor;
        g_secureHost.userInteractionEnabled = YES;
        g_secureHost.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    if (g_secureHost.superview != container) {
        [container addSubview:g_secureHost];
    }
    Astral_SecureRoot = g_secureHost;
    return g_secureHost;
}

static void applyHideRecording(bool on) {
    dispatch_async(dispatch_get_main_queue(), ^{
        g_hideRec.store(on);
        UIWindow* host = g_window;
        UIView* root = host ? (host.rootViewController.view ?: host) : nil;
        if (!root) return;

        if (on) {
            UIView* sec = ensureSecureHost(root);
            // Move cheat UI into secure host so it won't appear on recordings/screenshots
            if (g_panel && g_panel.superview != sec) [sec addSubview:g_panel];
            if (g_fab && g_fab.superview != sec) [sec addSubview:g_fab];
            [root bringSubviewToFront:g_secureField];
            if (g_panel) [sec bringSubviewToFront:g_panel];
            if (g_fab) [sec bringSubviewToFront:g_fab];
        } else {
            // Move back to normal root (visible on recordings again)
            if (g_panel && root) [root addSubview:g_panel];
            if (g_fab && root) [root addSubview:g_fab];
            if (g_secureField) {
                [g_secureField removeFromSuperview];
                g_secureField = nil;
                g_secureHost = nil;
                Astral_SecureRoot = root;
            }
            if (g_panel) [root bringSubviewToFront:g_panel];
            if (g_fab) [root bringSubviewToFront:g_fab];
        }
    });
}

static UIView* makeSwitch(NSString* title, NSString* sub, bool on, void(^cb)(bool)) {
    UIView* row = [[UIView alloc] initWithFrame:CGRectMake(0,0,250,52)];
    row.backgroundColor = C(0.07,0.09,0.14,0.95);
    row.layer.cornerRadius = 10;
    row.layer.borderWidth = 1;
    row.layer.borderColor = C(0.15,0.4,0.85,0.45).CGColor;

    UILabel* t = [[UILabel alloc] initWithFrame:CGRectMake(12,6,160,20)];
    t.text = title; t.textColor = UIColor.whiteColor;
    t.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [row addSubview:t];

    UILabel* s = [[UILabel alloc] initWithFrame:CGRectMake(12,26,160,16)];
    s.text = sub; s.textColor = C(0.5,0.6,0.75,1);
    s.font = [UIFont systemFontOfSize:10];
    [row addSubview:s];

    UISwitch* sw = [[UISwitch alloc] initWithFrame:CGRectMake(190,10,51,31)];
    sw.transform = CGAffineTransformMakeScale(0.85, 0.85);
    sw.on = on;
    sw.onTintColor = C(0.2,0.5,1,1);
    [sw addAction:[UIAction actionWithHandler:^(__kindof UIAction* a) {
        cb(((UISwitch*)a.sender).on);
    }] forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];
    return row;
}

static UIButton* makeSideBtn(NSString* title, int tag, BOOL selected) {
    UIButton* b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.tag = tag;
    b.frame = CGRectMake(8, 0, 104, 36);
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    b.layer.cornerRadius = 8;
    if (selected) {
        b.backgroundColor = C(0.15,0.4,0.95,0.9);
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    } else {
        b.backgroundColor = C(0.08,0.1,0.15,0.9);
        [b setTitleColor:C(0.55,0.7,0.9,1) forState:UIControlStateNormal];
    }
    [b addTarget:[ACH class] action:@selector(sideTap:) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

static void rebuildContent() {
    UIView* content = g_content;
    if (!content) return;
    for (UIView* v in content.subviews) [v removeFromSuperview];

    CGFloat y = 8;
    auto add = [&](UIView* row) {
        row.frame = CGRectMake(8, y, 250, 52);
        [content addSubview:row];
        y += 58;
    };

    if (g_section == 0) { // Aim
        add(makeSwitch(@"Aim bot", @"Auto aim enemies", g_aimbot.load(), ^(bool v){ g_aimbot.store(v); }));
        add(makeSwitch(@"Silent aim", @"Hidden aim", g_silent.load(), ^(bool v){ g_silent.store(v); }));
        add(makeSwitch(@"FOV Circle", @"Draw FOV ring", g_fovDraw.load(), ^(bool v){ g_fovDraw.store(v); }));

        UILabel* fl = [[UILabel alloc] initWithFrame:CGRectMake(12,y,70,22)];
        fl.text = [NSString stringWithFormat:@"FOV %.0f", g_fov.load()];
        fl.textColor = UIColor.whiteColor;
        fl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        fl.tag = 9001;
        [content addSubview:fl];
        UISlider* sl = [[UISlider alloc] initWithFrame:CGRectMake(80,y,170,28)];
        sl.minimumValue = 1; sl.maximumValue = 30; sl.value = g_fov.load();
        sl.minimumTrackTintColor = C(0.25,0.55,1,1);
        [sl addAction:[UIAction actionWithHandler:^(__kindof UIAction* a) {
            float v = ((UISlider*)a.sender).value;
            g_fov.store(v);
            ((UILabel*)[content viewWithTag:9001]).text = [NSString stringWithFormat:@"FOV %.0f", v];
        }] forControlEvents:UIControlEventValueChanged];
        [content addSubview:sl];
        y += 36;
    } else if (g_section == 1) { // Visuals
        add(makeSwitch(@"ESP Name", @"Enemy tags", g_espName.load(), ^(bool v){ g_espName.store(v); }));
        add(makeSwitch(@"ESP Distance", @"Show meters", g_espDist.load(), ^(bool v){ g_espDist.store(v); }));
        add(makeSwitch(@"Snaplines", @"Lines to enemies", g_espSnap.load(), ^(bool v){ g_espSnap.store(v); }));
        add(makeSwitch(@"Team check", @"Ignore teammates", g_espTeam.load(), ^(bool v){ g_espTeam.store(v); }));
    } else { // Misc
        add(makeSwitch(@"Hide Recording", @"Hide cheat on record/screenshot", g_hideRec.load(), ^(bool v){ applyHideRecording(v); }));
    }
}

static void rebuildPanel() {
    UIView* panel = g_panel;
    if (!panel) return;
    for (UIView* v in panel.subviews) [v removeFromSuperview];

    // Header
    UIView* head = [[UIView alloc] initWithFrame:CGRectMake(0,0,380,44)];
    head.backgroundColor = C(0.05,0.1,0.2,1);
    UILabel* title = [[UILabel alloc] initWithFrame:CGRectMake(0,8,380,28)];
    title.text = @"ASTRAL CHEATS";
    title.textColor = C(0.4,0.75,1,1);
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBlack];
    title.textAlignment = NSTextAlignmentCenter;
    [head addSubview:title];
    [panel addSubview:head];

    // Sidebar
    UIView* side = [[UIView alloc] initWithFrame:CGRectMake(0,44,120,320)];
    side.backgroundColor = C(0.04,0.06,0.1,1);
    NSArray* names = @[@"Aim", @"Visuals", @"Misc"];
    for (int i = 0; i < 3; i++) {
        UIButton* b = makeSideBtn(names[i], i, g_section == i);
        b.frame = CGRectMake(8, 12 + i*44, 104, 36);
        [side addSubview:b];
    }
    [panel addSubview:side];

    // Content
    UIView* content = [[UIView alloc] initWithFrame:CGRectMake(120,44,260,320)];
    content.backgroundColor = C(0.05,0.07,0.11,1);
    [panel addSubview:content];
    g_content = content;
    rebuildContent();

    panel.frame = CGRectMake(panel.frame.origin.x, panel.frame.origin.y, 380, 364);
}

@implementation ACH
+ (void)sideTap:(UIButton*)b {
    g_section = (int)b.tag;
    rebuildPanel();
}
+ (void)setSection:(int)s { g_section = s; rebuildPanel(); }

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
    Astral_SecureRoot = root;

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
    g_fab = fab;
    [fab addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMenu)]];
    [fab addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];

    UIView* panel = [[UIView alloc] initWithFrame:CGRectMake(70, 40, 380, 364)];
    panel.backgroundColor = C(0.04,0.06,0.1,0.98);
    panel.layer.cornerRadius = 14;
    panel.layer.borderWidth = 1.5;
    panel.layer.borderColor = C(0.2,0.45,0.95,0.85).CGColor;
    panel.layer.shadowOpacity = 0.5; panel.layer.shadowRadius = 12;
    panel.clipsToBounds = YES;
    panel.hidden = !g_menuOpen.load();
    [root addSubview:panel];
    g_panel = panel;
    rebuildPanel();
    [panel addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];

    // If hide was already on
    if (g_hideRec.load()) applyHideRecording(YES);

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification* n){
            if (g_hideRec.load()) applyHideRecording(YES);
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
