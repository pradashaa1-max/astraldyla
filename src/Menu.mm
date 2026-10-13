// language: Objective-C++, file: Menu.mm, target: iOS arm64
// Menu + landscape + hide-rec. hitTest passthrough so game buttons work.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include "State.h"
#include <cmath>

@interface ACH : NSObject
+ (void)start;
@end

@interface ACVC : UIViewController
@end

@interface ACW : UIWindow
@end
@implementation ACW
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    UIView* hit = [super hitTest:point withEvent:event];
    // only FAB and panel (and their subviews) receive touches
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}
@end

std::atomic<bool> g_aimbot{false};
std::atomic<bool> g_silent{false};
std::atomic<bool> g_fovDraw{false};
std::atomic<bool> g_espName{false};
std::atomic<bool> g_espDist{false};
std::atomic<bool> g_espSnap{false};
std::atomic<bool> g_espTeam{false};
std::atomic<bool> g_hideRec{false};
std::atomic<float> g_fov{12.f};
std::atomic<bool> g_menuOpen{true};

static __weak ACW* g_window = nil;
static __weak UIView* g_panel = nil;
static __weak UIView* g_fab = nil;

static void forceLandscape() {
    if (@available(iOS 16.0, *)) {
        for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:UIWindowScene.class]) continue;
            UIWindowSceneGeometryPreferencesIOS* pref =
                [[UIWindowSceneGeometryPreferencesIOS alloc]
                    initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscape];
            [(UIWindowScene*)s requestGeometryUpdateWithPreferences:pref errorHandler:nil];
            break;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [[UIDevice currentDevice] setValue:@(UIInterfaceOrientationLandscapeRight) forKey:@"orientation"];
    [UIViewController attemptRotationToDeviceOrientation];
#pragma clang diagnostic pop
}

static void applyHideRecording(bool on) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow* key = nil;
        for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow* w in ((UIWindowScene*)s).windows) {
                if (w.isKeyWindow) { key = w; break; }
            }
            if (key) break;
        }
        if (!key) key = UIApplication.sharedApplication.windows.firstObject;
        if (on) {
            if (!objc_getAssociatedObject(key, "astral_secure_tf")) {
                UITextField* tf = [[UITextField alloc] initWithFrame:CGRectMake(0,0,1,1)];
                tf.secureTextEntry = YES;
                tf.userInteractionEnabled = NO;
                tf.alpha = 0.01f;
                [key addSubview:tf];
                objc_setAssociatedObject(key, "astral_secure_tf", tf, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (g_window) g_window.windowLevel = UIWindowLevelAlert + 1;
        } else {
            id tf = objc_getAssociatedObject(key, "astral_secure_tf");
            if ([tf isKindOfClass:UITextField.class]) {
                [(UIView*)tf removeFromSuperview];
                objc_setAssociatedObject(key, "astral_secure_tf", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        g_hideRec.store(on);
    });
}

static UIColor* ACColor(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static UIView* makeSwitchRow(NSString* title, bool initial, void(^onChange)(bool)) {
    UIView* row = [[UIView alloc] initWithFrame:CGRectMake(0,0,280,40)];
    UILabel* lab = [[UILabel alloc] initWithFrame:CGRectMake(12,0,180,40)];
    lab.text = title;
    lab.textColor = UIColor.whiteColor;
    lab.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [row addSubview:lab];
    UISwitch* sw = [[UISwitch alloc] initWithFrame:CGRectMake(210,5,51,31)];
    sw.on = initial;
    sw.onTintColor = ACColor(0.35,0.55,1.0,1);
    [sw addAction:[UIAction actionWithHandler:^(__kindof UIAction* a) {
        onChange(((UISwitch*)a.sender).on);
    }] forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];
    return row;
}

static void rebuildPanel() {
    UIView* panel = g_panel;
    if (!panel) return;
    for (UIView* v in panel.subviews) [v removeFromSuperview];
    CGFloat y = 12;
    UILabel* header = [[UILabel alloc] initWithFrame:CGRectMake(12,y,256,28)];
    header.text = @"ASTRAL";
    header.textColor = ACColor(0.55,0.75,1.0,1);
    header.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    header.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:header];
    y += 36;
    auto add = [&](UIView* row) {
        row.frame = CGRectMake(0, y, 280, 40);
        [panel addSubview:row];
        y += 42;
    };
    add(makeSwitchRow(@"Aim bot", g_aimbot.load(), ^(bool v){ g_aimbot.store(v); }));
    add(makeSwitchRow(@"Silent aim", g_silent.load(), ^(bool v){ g_silent.store(v); }));
    add(makeSwitchRow(@"FOV Circle", g_fovDraw.load(), ^(bool v){ g_fovDraw.store(v); }));
    add(makeSwitchRow(@"ESP Name", g_espName.load(), ^(bool v){ g_espName.store(v); }));
    add(makeSwitchRow(@"ESP Distance", g_espDist.load(), ^(bool v){ g_espDist.store(v); }));
    add(makeSwitchRow(@"Snaplines", g_espSnap.load(), ^(bool v){ g_espSnap.store(v); }));
    add(makeSwitchRow(@"Team check", g_espTeam.load(), ^(bool v){ g_espTeam.store(v); }));
    add(makeSwitchRow(@"Hide Recording", g_hideRec.load(), ^(bool v){ applyHideRecording(v); }));
    UILabel* fl = [[UILabel alloc] initWithFrame:CGRectMake(12,y,100,24)];
    fl.text = [NSString stringWithFormat:@"FOV %.0f", g_fov.load()];
    fl.textColor = UIColor.whiteColor;
    fl.font = [UIFont systemFontOfSize:13];
    fl.tag = 9001;
    [panel addSubview:fl];
    UISlider* sl = [[UISlider alloc] initWithFrame:CGRectMake(100,y,160,30)];
    sl.minimumValue = 1; sl.maximumValue = 30; sl.value = g_fov.load();
    sl.minimumTrackTintColor = ACColor(0.35,0.55,1.0,1);
    [sl addAction:[UIAction actionWithHandler:^(__kindof UIAction* a) {
        float v = ((UISlider*)a.sender).value;
        g_fov.store(v);
        ((UILabel*)[panel viewWithTag:9001]).text = [NSString stringWithFormat:@"FOV %.0f", v];
    }] forControlEvents:UIControlEventValueChanged];
    [panel addSubview:sl];
    y += 40;
    panel.frame = CGRectMake(panel.frame.origin.x, panel.frame.origin.y, 280, y + 12);
}

@implementation ACVC
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (BOOL)shouldAutorotate { return YES; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
}
@end

@implementation ACH
+ (void)start {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{ [ACH bootstrap]; });
        // retry a few times — scene may not be ready immediately after inject
        for (int i = 1; i <= 6; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [ACH bootstrap]; });
        }
    });
}
+ (void)bootstrap {
    if (g_window) return;

    // iOS 13+: window must be attached to a UIWindowScene or it never appears
    UIWindowScene* scene = nil;
    for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene*)s;
            break;
        }
    }
    if (!scene) {
        for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class]) {
                scene = (UIWindowScene*)s;
                break;
            }
        }
    }
    if (!scene) return; // will retry on the delayed call

    CGRect screen = scene.coordinateSpace.bounds;
    if (screen.size.width < 10 || screen.size.height < 10)
        screen = UIScreen.mainScreen.bounds;

    ACW* win = [[ACW alloc] initWithWindowScene:scene];
    win.frame = screen;
    win.windowLevel = UIWindowLevelAlert + 1;
    win.backgroundColor = UIColor.clearColor;
    win.rootViewController = [ACVC new];
    // do NOT makeKeyAndVisible — keep game as key window so controls work
    win.hidden = NO;
    g_window = win;

    UIView* fab = [[UIView alloc] initWithFrame:CGRectMake(20, 80, 48, 48)];
    fab.backgroundColor = ACColor(0.12,0.14,0.20,0.92);
    fab.layer.cornerRadius = 24;
    fab.layer.borderWidth = 1.5;
    fab.layer.borderColor = ACColor(0.35,0.55,1.0,0.9).CGColor;
    UILabel* fabLab = [[UILabel alloc] initWithFrame:fab.bounds];
    fabLab.text = @"A";
    fabLab.textColor = ACColor(0.55,0.75,1.0,1);
    fabLab.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    fabLab.textAlignment = NSTextAlignmentCenter;
    fabLab.userInteractionEnabled = NO;
    [fab addSubview:fabLab];
    [win addSubview:fab];
    g_fab = fab;
    [fab addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMenu)]];
    [fab addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFab:)]];

    UIView* panel = [[UIView alloc] initWithFrame:CGRectMake(80, 60, 280, 400)];
    panel.backgroundColor = ACColor(0.08,0.09,0.12,0.94);
    panel.layer.cornerRadius = 14;
    panel.layer.borderWidth = 1;
    panel.layer.borderColor = ACColor(0.25,0.30,0.40,0.8).CGColor;
    [win addSubview:panel];
    g_panel = panel;
    rebuildPanel();

    [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification* n){ forceLandscape(); }];
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    forceLandscape();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification* n){
            forceLandscape();
            if (g_hideRec.load()) applyHideRecording(YES);
        }];
}
+ (void)toggleMenu {
    bool open = !g_menuOpen.load();
    g_menuOpen.store(open);
    g_panel.hidden = !open;
}
+ (void)dragFab:(UIPanGestureRecognizer*)g {
    UIView* v = g.view;
    CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [g setTranslation:CGPointZero inView:v.superview];
}
@end

__attribute__((constructor))
static void astral_init() { [ACH start]; }
