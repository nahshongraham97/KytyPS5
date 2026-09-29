# KytyPS5 fork notes

Personal tooling for `nahshongraham97/KytyPS5`. Kept on the `tools` branch so
`main` stays a clean, fast-forwardable mirror of upstream `KytyPS5/KytyPS5`.

## Branches

| Branch | Purpose |
| --- | --- |
| `main` | mirror of `KytyPS5/KytyPS5` main. Never commit here; only fast-forward. |
| `tools` | these helper scripts, based on upstream main. |

Sync `main` with upstream:

```powershell
.\scripts\sync-fork.ps1 -Push
```

## Scripts

| Script | Purpose |
| --- | --- |
| `run-kyty.ps1` | Run a game on a release build (auto-detects `kyty_emulator.exe`) or build this checkout and run it. |
| `kyty-bisect.ps1` | Sweep several releases, capture each run's log. |
| `sync-fork.ps1` | Fast-forward `main` to upstream. |

## Build (Windows)

KytyPS5 is **not** a MinGW project. It requires `clang-cl`; `cl.exe` and MinGW
`g++` are rejected at configure time.

Requirements: Git, CMake 3.22.1+, Ninja, Visual Studio 2022 (or Build Tools)
with *Desktop development with C++* and *C++ Clang tools for Windows*, and
`glslangValidator` on `PATH`. Qt 6 is needed only for the launcher.

Run from an **x64 Native Tools Command Prompt for VS 2022** (or Developer
PowerShell):

```powershell
git submodule update --init --recursive

# Emulator only; KYTY_BUILD_LAUNCHER=OFF means Qt is not required.
cmake -S . -B _Build/windows -G Ninja -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl `
    -DKYTY_BUILD_LAUNCHER=OFF
cmake --build _Build/windows --target kyty_emulator --parallel
```

`run-kyty.ps1 -Build` does exactly this.

## Running

```powershell
.\scripts\run-kyty.ps1 -Game 'D:\Games\SAROS-PPSA07631'
```

Kyty aborts the process on *any* Vulkan validation error, so the scripts pass
`--vulkan-validation false` unless `-VulkanValidation` is given.

Kyty writes its logs relative to the working directory:

- `_kyty.txt` — emulator log
- `_Shaders\` — shader dumps
- `_PipelineCache\` — Kyty-only Vulkan pipeline cache (`_PipelineCache\<titleid>.bin`).
  Not consumable by AnyPS5.

## Known issue: abort at the language-select step

Titles such as SAROS (`PPSA07631`) abort once the intro movies finish:

```
shader resource tracking: hash=0xb9da5e64f4c5b10a stage=compute pc=0x00000084
buffer descriptor is not a valid runtime value; GPU-selected access requires a raw DWORD x2/x3/x4 load
```

This is a hard `Fail()` in
`src/graphics/shader/recompiler/ir/passes/ResourceTracking.cpp`, not a config
toggle.

History:

- The fatal check was introduced by `b2a80a3` (2026-09-21, *"Resolve
  GPU-selected raw buffer descriptors through shared RDNA2 addressing"*). Builds
  from 2026-09-20 and earlier do not contain it, which is why the 09-12 build
  referenced in upstream issue #260 reached the main menu.
- The check only accepts raw x2/x3/x4 DWORD loads. Shaders that select a buffer
  descriptor by another path still abort.
- The 2026-09-29 *"UFC 5 in-game"* rework (`0791f92`) changed this file heavily
  but the check survives (upstream `main`, `ResourceTracking.cpp`), so newer
  builds abort on the same shader at a different line number.

Related upstream reports: #260 (Saros, main menu), #824 (Killzone: Liberation,
same error class).

`kyty-bisect.ps1` exists to confirm the regression boundary across releases.
