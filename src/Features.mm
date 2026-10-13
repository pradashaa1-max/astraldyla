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
struct Vec4 { float x,y,z,w; };
static inline float vlen(Vec3 v) { return sqrtf(v.x*v.x + v.y*v.y + v.z*v.z); }
static inline Vec3 vsub(Vec3 a, Vec3 b) { return {a.x-b.x, a.y-b.y, a.z-b.z}; }
static inline Vec3 vnorm(Vec3 v) {
    float l = vlen(v); if (l < 1e-6f) return {0,0,1};
    return {v.x/l, v.y/l, v.z/l};
}
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
    if (!g_unity) {
        for (uint32_t i = 0; i < n; i++) {
            const char* name = _dyld_get_image_name(i);
            if (name && (strstr(name, "Unity") || strstr(name, "il2cpp"))) {
                g_unity = (uintptr_t)_dyld_get_image_header(i);
                break;
            }
        }
    }
    return g_unity;
}

template<typename Fn>
static Fn RVA(uint64_t off) { return (Fn)(unity_base() + off); }

using get_position_t = Vec3 (*)(void*);
using set_position_t = void (*)(void*, Vec3);
using set_rotation_t = void (*)(void*, Vec4);
using cam_main_t = void* (*)();
using world_to_screen_t = Vec3 (*)(void*, Vec3);
using get_transform_t = void* (*)(void*);
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

static Vec4 quat_look(Vec3 from, Vec3 to) {
    Vec3 f = vnorm(vsub(to, from));
    float yaw = atan2f(f.x, f.z);
    float pitch = -asinf(fmodf(f.y, 1.0f));
    float cy = cosf(yaw*0.5f), sy = sinf(yaw*0.5f);
    float cp = cosf(pitch*0.5f), sp = sinf(pitch*0.5f);
    return {sy*cp, cy*sp, sy*sp, cy*cp};
}

using il2cpp_class_get_type_t = const void* (*)(Il2CppClass*);
using il2cpp_type_get_object_t = Il2CppObject* (*)(const void*);
using il2cpp_array_length_t = uint32_t (*)(void*);
using il2cpp_class_from_index_t = Il2CppClass* (*)(int);

static il2cpp_class_get_type_t p_class_get_type = nullptr;
static il2cpp_type_get_object_t p_type_get_object = nullptr;
static il2cpp_array_length_t p_array_length = nullptr;
static il2cpp_class_from_index_t p_class_from_index = nullptr;

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
    p_class_from_index = (il2cpp_class_from_index_t)sym("il2cpp_class_from_il2cpp_type");
    if (!p_class_from_index)
        p_class_from_index = (il2cpp_class_from_index_t)sym("il2cpp_class_from_index");
    return p_class_get_type && p_type_get_object;
}

struct Il2CppArraySimple {
    void* klass;
    void* monitor;
    void* bounds;
    uintptr_t max_length;
    void* vector[1];
};

static std::vector<void*> invoke_find(Il2CppClass* pcKlass, Il2CppApi& api) {
    std::vector<void*> out;
    if (!pcKlass) return out;
    Il2CppClass* objKlass = api.find_class("UnityEngine", "Object");
    if (!objKlass) return out;

    const MethodInfo* findMethod = api.find_method(objKlass, "FindObjectsOfType", 1);
    if (!findMethod) findMethod = api.find_method(objKlass, "FindObjectsOfTypeAll", 1);
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

static std::vector<void*> find_players() {
    std::vector<void*> out;
    auto& api = IL2CPP();
    if (!api.ready && !api.init()) return out;
    if (!ensure_il2cpp_extra()) return out;

    const char* names[][2] = {
        {"", "PlayerController"},
        {"Assembly-CSharp", "PlayerController"},
        {"", "Player"},
        {"", "PlayerRoot"},
        {"", "Character"},
        {"", "FPSController"},
        {"", "NetworkPlayer"},
        {"Photon.Pun", "PhotonView"},
        {"", "AimController"},
    };
    for (auto& ns : names) {
        Il2CppClass* k = api.find_class(ns[0], ns[1]);
        if (!k) continue;
        out = invoke_find(k, api);
        if (!out.empty()) return out;
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
    if (bestD < 5.0f) return best;
    return nullptr;
}

@interface FOVOverlay : UIView
@property (nonatomic, assign) int debugCount;
@end
@implementation FOVOverlay
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    if (g_fovDraw.load()) {
        CGFloat r = g_fov.load() * 8.0;
        CGPoint c = CGPointMake(rect.size.width*0.5, rect.size.height*0.5);
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.3 green:0.7 blue:1 alpha:0.7].CGColor);
        CGContextSetLineWidth(ctx, 1.5);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(c.x-r, c.y-r, r*2, r*2));
    }
}
@end

static FOVOverlay* g_fovView = nil;
static UILabel* g_debugLab = nil;

void Astral_EnsureFOVOverlay(UIWindow* win) {
    if (!win) return;
    UIView* root = win.rootViewController.view ?: win;
    if (!g_fovView) {
        g_fovView = [[FOVOverlay alloc] initWithFrame:root.bounds];
        g_fovView.userInteractionEnabled = NO;
        g_fovView.backgroundColor = UIColor.clearColor;
        g_fovView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [root addSubview:g_fovView];
        CADisplayLink* link = [CADisplayLink displayLinkWithTarget:g_fovView selector:@selector(setNeedsDisplay)];
        link.preferredFramesPerSecond = 30;
        [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    if (!g_debugLab) {
        g_debugLab = [[UILabel alloc] initWithFrame:CGRectMake(8, 40, 220, 18)];
        g_debugLab.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
        g_debugLab.textColor = [UIColor colorWithWhite:1 alpha:0.55];
        g_debugLab.text = @"ASTRAL: init";
        [root addSubview:g_debugLab];
    }
}

static NSMutableArray<UILabel*>* g_espLabels = nil;
static void ensure_esp_pool(UIView* root) {
    if (g_espLabels || !root) return;
    g_espLabels = [NSMutableArray new];
    for (int i = 0; i < 32; i++) {
        UILabel* lab = [[UILabel alloc] initWithFrame:CGRectZero];
        lab.textColor = [UIColor colorWithRed:0.35 green:0.9 blue:1 alpha:1];
        lab.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.hidden = YES;
        lab.layer.shadowColor = [UIColor blackColor].CGColor;
        lab.layer.shadowOpacity = 1;
        lab.layer.shadowRadius = 2;
        [root addSubview:lab];
        [g_espLabels addObject:lab];
    }
}

void Astral_FeaturesTick() {
    if (!unity_base()) {
        if (g_debugLab) g_debugLab.text = @"ASTRAL: no UnityFramework";
        return;
    }

    void* cam = main_camera();
    if (!cam) {
        if (g_debugLab) g_debugLab.text = @"ASTRAL: no camera";
        return;
    }
    void* camTr = component_transform(cam);
    if (!camTr) return;
    Vec3 camPos = get_pos(camTr);

    auto players = find_players();
    if (g_debugLab) {
        g_debugLab.text = [NSString stringWithFormat:@"ASTRAL: players=%lu cam=ok", (unsigned long)players.size()];
    }

    bool need = g_aimbot.load() || g_silent.load() || g_espName.load()
             || g_espDist.load() || g_espSnap.load() || g_fovDraw.load();
    if (!need) {
        if (g_espLabels) for (UILabel* l in g_espLabels) l.hidden = YES;
        return;
    }
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
    UIView* root = host ? (host.rootViewController.view ?: host) : nil;
    if (root) ensure_esp_pool(root);

    CGSize scr = host ? host.bounds.size : UIScreen.mainScreen.bounds.size;
    if (scr.width < 1) scr = UIScreen.mainScreen.bounds.size;

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
        if (dist < 0.3f || dist > 500.f) continue;

        Vec3 screen = w2s(cam, pos);
        bool inFront = screen.z > 0.05f;
        float sx = screen.x;
        float sy = scr.height - screen.y;
        bool onScreen = inFront && sx > -50 && sx < scr.width+50 && sy > -50 && sy < scr.height+50;

        if ((g_espName.load() || g_espDist.load()) && g_espLabels && espIdx < (int)g_espLabels.count) {
            UILabel* lab = g_espLabels[espIdx++];
            if (onScreen) {
                NSMutableString* txt = [NSMutableString stringWithString:@"●"];
                if (g_espName.load()) [txt appendString:@" Enemy"];
                if (g_espDist.load()) [txt appendFormat:@" %.0fm", dist];
                lab.text = txt;
                [lab sizeToFit];
                lab.center = CGPointMake(sx, sy - 18);
                lab.hidden = NO;
                [lab.superview bringSubviewToFront:lab];
            } else {
                lab.hidden = YES;
            }
        }

        if ((g_aimbot.load() || g_silent.load()) && inFront) {
            float cx = scr.width * 0.5f;
            float cy = scr.height * 0.5f;
            float dx = sx - cx;
            float dy = sy - cy;
            float crossDist = sqrtf(dx*dx + dy*dy);
            float fovPx = g_fov.load() * 10.0f;
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
        targetPos.y += 1.15f;
        RVA<look_at_t>(Offsets::Transform_LookAt)(camTr, targetPos);
        Vec4 q = quat_look(camPos, targetPos);
        RVA<set_rotation_t>(Offsets::Transform_set_rotation)(camTr, q);
    }
}
