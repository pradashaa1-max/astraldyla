#pragma once
// Standoff 2 — UnityFramework dump (Il2CppDumper, metadata v31)
// RVAs relative to UnityFramework base. Pin per game build.

#include <cstdint>

namespace Offsets {

constexpr uint64_t Transform_get_position      = 0x33237F0;
constexpr uint64_t Transform_set_position      = 0x33238A0;
constexpr uint64_t Transform_get_localPosition = 0x3323948;
constexpr uint64_t Transform_set_localPosition = 0x33239F8;
constexpr uint64_t Transform_get_rotation      = 0x3323ACC;
constexpr uint64_t Transform_set_rotation      = 0x3323B60;
constexpr uint64_t Transform_get_forward       = 0x3323DD8;
constexpr uint64_t Transform_LookAt            = 0x3324990;

constexpr uint64_t Camera_get_main             = 0x32F3E08;
constexpr uint64_t Camera_WorldToScreenPoint   = 0x32F3A54;
constexpr uint64_t Camera_get_fieldOfView      = 0x32F29C8;
constexpr uint64_t Camera_set_fieldOfView      = 0x32F2A08;

constexpr uint64_t Component_get_transform     = 0x3319A54;
constexpr uint64_t Component_get_gameObject    = 0x3319A94;
constexpr uint64_t GameObject_get_transform    = 0x331A880;
constexpr uint64_t GameObject_get_activeSelf   = 0x331A9A0;
constexpr uint64_t GameObject_get_activeInHierarchy = 0x331A9E0;

constexpr size_t PC_mainCameraHolder   = 0x20;
constexpr size_t PC_fpsCameraHolder    = 0x28;
constexpr size_t PC_team               = 0x59;
constexpr size_t PC_aimController      = 0x60;
constexpr size_t PC_weaponry           = 0x68;
constexpr size_t PC_movement           = 0x78;
constexpr size_t PC_hitController      = 0x88;
constexpr size_t PC_characterCtrl      = 0xF0;
constexpr size_t PC_photonView         = 0x120;
constexpr size_t PC_photonPlayer       = 0x130;

constexpr size_t PC_static_MaxCtHealth = 0x8;
constexpr size_t PC_static_MaxCtArmor  = 0xC;
constexpr size_t PC_static_MaxTrHealth = 0x10;
constexpr size_t PC_static_MaxTrArmor  = 0x14;

constexpr int TypeIndex_PlayerController = 2782;
constexpr int TypeIndex_AimController    = 2930;
constexpr int TypeIndex_CameraMovementController = 4944;

}
