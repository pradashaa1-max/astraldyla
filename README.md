# AstralCheat — Standoff 2 (iOS)

IL2CPP dylib with real RVAs from UnityFramework dump.

## Build

```bash
export THEOS=~theos
cd AstralCheat
make clean && make
# .theos/obj/AstralCheat.dylib
```

## Offsets (this UnityFramework)

| Symbol | RVA |
|--------|-----|
| Transform.get_position | 0x33237F0 |
| Transform.set_position | 0x33238A0 |
| Camera.get_main | 0x32F3E08 |
| Camera.WorldToScreenPoint | 0x32F3A54 |
| Component.get_transform | 0x3319A54 |
| PC.team | field 0x59 |
| PC.aimController | field 0x60 |
| PC.photonView | field 0x120 |

Full list: `include/Offsets.h`

## Fixes

- **Game buttons work**: `ACW hitTest:` returns nil outside FAB/panel; window is not key.
- Landscape forced, hide-recording via secure UITextField.
- RVAs resolved via `_dyld_get_image_header("UnityFramework") + offset`.

## Inject

```bash
insert_dylib --inplace --all-yes @rpath/AstralCheat.dylib <binary>
```
