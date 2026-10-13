#pragma once
#include <cstdint>
#include <dlfcn.h>
#include <cstring>

// Minimal IL2CPP runtime bindings used by the cheat.
// Prefer dlsym on UnityFramework handle; fall back to hardcoded if filled in Offsets.h

struct Il2CppDomain;
struct Il2CppAssembly;
struct Il2CppImage;
struct Il2CppClass;
struct MethodInfo;
struct FieldInfo;
struct Il2CppObject;
struct Il2CppString;

using il2cpp_domain_get_t                = Il2CppDomain* (*)();
using il2cpp_domain_get_assemblies_t     = const Il2CppAssembly** (*)(Il2CppDomain*, size_t*);
using il2cpp_assembly_get_image_t        = const Il2CppImage* (*)(const Il2CppAssembly*);
using il2cpp_class_from_name_t           = Il2CppClass* (*)(const Il2CppImage*, const char*, const char*);
using il2cpp_class_get_method_from_name_t= const MethodInfo* (*)(Il2CppClass*, const char*, int);
using il2cpp_class_get_field_from_name_t = FieldInfo* (*)(Il2CppClass*, const char*);
using il2cpp_field_get_offset_t          = size_t (*)(FieldInfo*);
using il2cpp_runtime_invoke_t            = Il2CppObject* (*)(const MethodInfo*, void*, void**, void**);
using il2cpp_string_new_t                = Il2CppString* (*)(const char*);
using il2cpp_object_unbox_t              = void* (*)(Il2CppObject*);
using il2cpp_method_get_param_count_t    = uint32_t (*)(const MethodInfo*);

struct Il2CppApi {
    il2cpp_domain_get_t                domain_get = nullptr;
    il2cpp_domain_get_assemblies_t     domain_get_assemblies = nullptr;
    il2cpp_assembly_get_image_t        assembly_get_image = nullptr;
    il2cpp_class_from_name_t           class_from_name = nullptr;
    il2cpp_class_get_method_from_name_t class_get_method_from_name = nullptr;
    il2cpp_class_get_field_from_name_t class_get_field_from_name = nullptr;
    il2cpp_field_get_offset_t          field_get_offset = nullptr;
    il2cpp_runtime_invoke_t            runtime_invoke = nullptr;
    il2cpp_string_new_t                string_new = nullptr;
    il2cpp_object_unbox_t              object_unbox = nullptr;

    bool ready = false;

    bool init() {
        void* handle = dlopen(nullptr, RTLD_NOW); // process image
        if (!handle) handle = dlopen("UnityFramework", RTLD_NOW);
        auto sym = [&](const char* n) -> void* {
            void* p = dlsym(handle, n);
            if (!p) p = dlsym(RTLD_DEFAULT, n);
            return p;
        };
        domain_get                = (il2cpp_domain_get_t)sym("il2cpp_domain_get");
        domain_get_assemblies     = (il2cpp_domain_get_assemblies_t)sym("il2cpp_domain_get_assemblies");
        assembly_get_image        = (il2cpp_assembly_get_image_t)sym("il2cpp_assembly_get_image");
        class_from_name           = (il2cpp_class_from_name_t)sym("il2cpp_class_from_name");
        class_get_method_from_name= (il2cpp_class_get_method_from_name_t)sym("il2cpp_class_get_method_from_name");
        class_get_field_from_name = (il2cpp_class_get_field_from_name_t)sym("il2cpp_class_get_field_from_name");
        field_get_offset          = (il2cpp_field_get_offset_t)sym("il2cpp_field_get_offset");
        runtime_invoke            = (il2cpp_runtime_invoke_t)sym("il2cpp_runtime_invoke");
        string_new                = (il2cpp_string_new_t)sym("il2cpp_string_new");
        object_unbox              = (il2cpp_object_unbox_t)sym("il2cpp_object_unbox");
        ready = domain_get && class_from_name && class_get_method_from_name && runtime_invoke;
        return ready;
    }

    Il2CppClass* find_class(const char* namespaze, const char* name) {
        if (!ready) return nullptr;
        size_t n = 0;
        auto asms = domain_get_assemblies(domain_get(), &n);
        if (!asms) return nullptr;
        for (size_t i = 0; i < n; ++i) {
            auto img = assembly_get_image(asms[i]);
            if (!img) continue;
            auto klass = class_from_name(img, namespaze, name);
            if (klass) return klass;
        }
        return nullptr;
    }

    const MethodInfo* find_method(Il2CppClass* klass, const char* name, int argc = 0) {
        if (!klass || !class_get_method_from_name) return nullptr;
        return class_get_method_from_name(klass, name, argc);
    }

    size_t field_offset(Il2CppClass* klass, const char* name) {
        if (!klass || !class_get_field_from_name || !field_get_offset) return 0;
        auto f = class_get_field_from_name(klass, name);
        return f ? field_get_offset(f) : 0;
    }
};

inline Il2CppApi& IL2CPP() {
    static Il2CppApi api;
    return api;
}
