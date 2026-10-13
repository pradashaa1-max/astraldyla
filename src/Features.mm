// language: Objective-C++, file: Features.mm, target: iOS arm64
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#include "Offsets.h"
#include "State.h"
#include "Il2Cpp.h"
#include <cmath>
#include <vector>

struct Vec3 { float x,y,z; };
static inline float vlen(Vec3 v) { return sqrtf(v.x*v.x + v.y*v.y + v.z*v.z); }
static inline Vec3 vsub(Vec3 a, Vec3 b) { return {a.x-b.x, a.y-b.y, a.z-b.z}; }
static inline float vdist(Vec3 a, Vec3 b) { return vlen(vsub(a,b)); }

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
using get_forward_t = Vec3 (*)(void*);
using look_at_t = void (*)(void*, Vec3);

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
__attribute__((unused))
static Vec3 get_forward(void* tr) {
    if (!tr || !unity_base()) return {};
    return RVA<get_forward_t>(Offsets::Transform_get_forward)(tr);
}

using il2cpp_class_get_type_t = const void* (*)(Il2CppClass*);
using il2cpp_type_get_object_t = Il2CppObject* (*)(const void*);
using il2cpp_array_length_t = uint32_t (*)(void*);

static il2cpp_class_get_type_t p_class_get_type = nullptr;
static il2cpp_type_get_object_t p_type_get_object = nullptr;
static il2cpp_array_length_t p_array_length = nullptr;

static bool ensure_il2cpp_extra() {
    if (p_class_get_type && p_type_get_object) return true;
    void* h = dlopen(nullptr, RTLD_NOW);
    auto sym = [&](const char* n) -> void* {
        void* p = dlsym(h, n);
        if (!p) p = dlsym(RTLD_DEFAULT, n);
        return p;
    };
    p_class_get_type = (il2cpp_class_get_type_t)sym("il2cpp_class_get_type");
    p_type_get_object = (il2cpp_type_get_object_t)sym("il2cpp_type_get_object");
    p_array_length = (il2cpp_array_length_t)sym("il2cpp_array_length");
    return p_class_get_type && p_type_get_object;
}

struct Il2CppArraySimple {
    void* klass;
    void* monitor;
    void* bounds;
    uintptr_t max_length;
    void* vector[1];
};

static std::vector<void*> find_players() {
    std::vector<void*> out;
    auto& api = IL2CPP();
    if (!api.ready && !api.init()) return out;
    if (!ensure_il2cpp_extra()) return out;

    Il2CppClass* pcKlass = api.find_class("", "PlayerController");
    if (!pcKlass) pcKlass = api.find_class("Assembly-CSharp", "PlayerController");
    if (!pcKlass) pcKlass = api.find_class("Game", "PlayerController");
    if (!pcKlass) pcKlass = api.find_class("Gameplay", "PlayerController");
    if (!pcKlass) return out;

    Il2CppClass* objKlass = api.find_class("UnityEngine", "Object");
    if (!objKlass) return out;

    const MethodInfo* findMethod = api.find_method(objKlass, "FindObjectsOfType", 1);
    if (!findMethod) findMethod = api.find_method(objKlass, "FindObjectsOfType", 2);
    if (!findMethod || !api.runtime_invoke) return out;

    const void* type = p_class_get_type(pcKlass);
    if (!type) return out;
    Il2CppObject* typeObj = p_type_get_object(type);
    if (!typeObj) return out;

    void* args[2] = { typeObj, nullptr };
    void* exc = nullptr;
    Il2CppObject* arrObj = api.runtime_invoke(findMethod, nullptr, args, &exc);
    if (exc || !arrObj) return out;

    auto* arr = (Il2CppArraySimple*)arrObj;
    uintptr_t len = arr->max_length;
    if (p_array_length) len = p_array_length(arrObj);
    if (len > 128) len = 128;

    for (uintptr_t i = 0; i < len; i++) {
        void* obj = arr->vector[i];
        if (obj) out.push_back(obj);
    }
    return out;
}

static int get_team(void* pc) {
    if (!pc) return -1;
    return (int)*((uint8_t*)pc + Offsets::PC_team);
}

static void* local_player_from_list(const std::vector<void*>& list, void* camTr) {
    if (!camTr || list.empty()) return nullptr;
    Vec3 camPos = get_pos(camTr);
    void* best = nullptr;
    float bestD = 1e9f;
    for (void* pc : list) {
        void* tr = component_transform(pc);
        if (!tr) continue;
        float d = vdist(get_pos(tr), camPos);
        if (d < bestD) { bestD = d; best = pc; }
    }
    if (bestD < 3.0f) return best;
    return nullptr;
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

static NSMutableArray<UILabel*>* g_espLabels = nil;

static void ensure_esp_pool(UIView* root) {
    if (g_espLabels) return;
    g_espLabels = [NSMutableArray new];
    for (int i = 0; i < 24; i++) {
        UILabel* lab = [[UILabel alloc] initWithFrame:CGRectZero];
        lab.textColor = [UIColor colorWithRed:0.4 green:0.9 blue:1 alpha:0.95];
        lab.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.hidden = YES;
        lab.layer.shadowColor = [UIColor blackColor].CGColor;
        lab.layer.shadowOpacity = 0.8;
        lab.layer.shadowRadius = 2;
        [root addSubview:lab];
        [g_espLabels addObject:lab];
    }
}

void Astral_FeaturesTick() {
    if (!unity_base()) return;
    bool need = g_aimbot.load() || g_silent.load() || g_espName.load()
             || g_espDist.load() || g_espSnap.load();
    if (!need) {
        if (g_espLabels) for (UILabel* l in g_espLabels) l.hidden = YES;
        return;
    }

    void* cam = main_camera();
    if (!cam) return;
    void* camTr = component_transform(cam);
    if (!camTr) return;
    Vec3 camPos = get_pos(camTr);

    auto players = find_players();
    if (players.empty()) return;

    void* local = local_player_from_list(players, camTr);
    int localTeam = local ? get_team(local) : -1;

    UIWindow* host = nil;
    for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow* w in ((UIWindowScene*)s).windows) {
            if (w.isKeyWindow) { host = w; break; }
        }
        if (host) break;
    }
    UIView* root = host.rootViewController.view ?: host;
    if (root) ensure_esp_pool(root);

    CGSize scr = UIScreen.mainScreen.bounds.size;
    if (scr.width < scr.height) { CGFloat t = scr.width; scr.width = scr.height; scr.height = t; }

    void* bestTarget = nullptr;
    float bestScore = 1e9f;
    int espIdx = 0;

    for (void* pc : players) {
        if (pc == local) continue;
        if (g_espTeam.load() && localTeam >= 0) {
            int t = get_team(pc);
            if (t == localTeam) continue;
        }
        void* tr = component_transform(pc);
        if (!tr) continue;
        Vec3 pos = get_pos(tr);
        float dist = vdist(pos, camPos);
        if (dist < 0.5f || dist > 400.f) continue;

        Vec3 screen = w2s(cam, pos);
        bool onScreen = screen.z > 0.1f
            && screen.x > 0 && screen.x < scr.width
            && screen.y > 0 && screen.y < scr.height;

        if ((g_espName.load() || g_espDist.load()) && g_espLabels && espIdx < (int)g_espLabels.count) {
            UILabel* lab = g_espLabels[espIdx++];
            if (onScreen) {
                NSMutableString* txt = [NSMutableString string];
                if (g_espName.load()) [txt appendString:@"Enemy"];
                if (g_espDist.load()) {
                    if (txt.length) [txt appendString:@" "];
                    [txt appendFormat:@"%.0fm", dist];
                }
                lab.text = txt;
                [lab sizeToFit];
                CGFloat lx = screen.x - lab.bounds.size.width * 0.5f;
                CGFloat ly = (scr.height - screen.y) - 20;
                lab.frame = CGRectMake(lx, ly, lab.bounds.size.width + 4, lab.bounds.size.height);
                lab.hidden = NO;
            } else {
                lab.hidden = YES;
            }
        }

        if ((g_aimbot.load() || g_silent.load()) && onScreen) {
            float cx = scr.width * 0.5f;
            float cy = scr.height * 0.5f;
            float sx = screen.x;
            float sy = scr.height - screen.y;
            float dx = sx - cx;
            float dy = sy - cy;
            float crossDist = sqrtf(dx*dx + dy*dy);
            float fovPx = g_fov.load() * 8.0f;
            if (crossDist < fovPx && crossDist < bestScore) {
                bestScore = crossDist;
                bestTarget = tr;
            }
        }
    }
    if (g_espLabels) {
        for (int i = espIdx; i < (int)g_espLabels.count; i++)
            g_espLabels[i].hidden = YES;
    }

    if (bestTarget && (g_aimbot.load() || g_silent.load())) {
        Vec3 targetPos = get_pos(bestTarget);
        targetPos.y += 1.0f;
        void* aimTr = camTr;
        if (aimTr && unity_base()) {
            RVA<look_at_t>(Offsets::Transform_LookAt)(aimTr, targetPos);
        }
    }
}
