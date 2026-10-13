// language: Objective-C++, file: Features.mm, target: iOS arm64
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#include "Offsets.h"
#include "State.h"
#include <cmath>

struct Vec3 { float x,y,z; };

static uintptr_t g_unity = 0;
static uintptr_t unity_base() {
    if (g_unity) return g_unity;
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) {
            g_unity = (uintptr_t)_dyld_get_image_header(i);
            break;
        }
    }
    return g_unity;
}

template<typename Fn>
static Fn RVA(uint64_t off) { return (Fn)(unity_base() + off); }

using get_position_t = Vec3 (*)(void*);
using set_position_t = void (*)(void*, Vec3);
using cam_main_t = void* (*)();
using world_to_screen_t = Vec3 (*)(void*, Vec3);
using get_transform_t = void* (*)(void*);

static Vec3 get_pos(void* tr) {
    if (!tr || !unity_base()) return {};
    return RVA<get_position_t>(Offsets::Transform_get_position)(tr);
}
static void* main_camera() {
    if (!unity_base()) return nullptr;
    return RVA<cam_main_t>(Offsets::Camera_get_main)();
}
static void* component_transform(void* c) {
    if (!c || !unity_base()) return nullptr;
    return RVA<get_transform_t>(Offsets::Component_get_transform)(c);
}
static Vec3 w2s(void* cam, Vec3 w) {
    if (!cam || !unity_base()) return {};
    return RVA<world_to_screen_t>(Offsets::Camera_WorldToScreenPoint)(cam, w);
}

@interface FOVOverlay : UIView
@end
@implementation FOVOverlay
- (void)drawRect:(CGRect)rect {
    if (!g_fovDraw.load()) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    CGFloat r = g_fov.load() * 8.0;
    CGPoint c = CGPointMake(rect.size.width*0.5, rect.size.height*0.5);
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.35 green:0.7 blue:1 alpha:0.65].CGColor);
    CGContextSetLineWidth(ctx, 1.5);
    CGContextStrokeEllipseInRect(ctx, CGRectMake(c.x-r, c.y-r, r*2, r*2));
}
@end

static FOVOverlay* g_fovView = nil;
void Astral_EnsureFOVOverlay(UIWindow* win) {
    if (g_fovView || !win) return;
    g_fovView = [[FOVOverlay alloc] initWithFrame:win.bounds];
    g_fovView.userInteractionEnabled = NO;
    g_fovView.backgroundColor = UIColor.clearColor;
    g_fovView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [win addSubview:g_fovView];
    CADisplayLink* link = [CADisplayLink displayLinkWithTarget:g_fovView selector:@selector(setNeedsDisplay)];
    link.preferredFramesPerSecond = 30;
    [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

void Astral_FeaturesTick() {
    if (!unity_base()) return;
    if (!g_aimbot.load() && !g_silent.load() && !g_espName.load()) return;
    void* cam = main_camera();
    if (!cam) return;
    void* camTr = component_transform(cam);
    if (!camTr) return;
    Vec3 camPos = get_pos(camTr);
    (void)camPos;
    // Player list: hook Photon / FindObjectsOfType(PlayerController).
    // Fields ready: PC_team 0x59, PC_aimController 0x60, PC_photonView 0x120.
}
