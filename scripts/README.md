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

`--game` must be the directory that **directly** contains `eboot.bin`; Kyty
mounts that directory as `/app0`. Dumps often nest it (for example
`<game>\PPSA07631-app0\eboot.bin`), so `run-kyty.ps1` descends up to three
levels and uses the folder it finds.

Kyty aborts the process on *any* Vulkan validation error, so the scripts pass
`--vulkan-validation false` unless `-VulkanValidation` is given. With validation
enabled, Saros dies earlier on a `vkAcquireNextImageKHR` semaphore VUID.

Kyty writes its logs relative to the working directory:

- `_kyty.txt` — emulator log (the useful one; it can reach tens of MB)
- `_Shaders\` — shader dumps
- `_PipelineCache\` — Kyty-only Vulkan pipeline cache (`_PipelineCache\<titleid>.bin`).
  Not consumable by AnyPS5.

## Saros (PPSA07631): aborts at the language-select step

Intro videos play, then the game aborts once it asks for a language. Every
available release fails; the failure moved between builds but never went away.

| Build | Videos | Failing shader | Message |
| --- | --- | --- | --- |
| `KytyPS5-2026-09-12-d3d7bd3` | none | `0x4284fbe48eca0a01` @ pc `0x26c` | `GetBufferResource dword 0 is not a valid runtime value` |
| `KytyPS5-2026-09-29-6799ecb` | 2 | `0xb9da5e64f4c5b10a` @ pc `0x84` | `buffer descriptor is not a valid runtime value; GPU-selected access requires a raw DWORD x2/x3/x4 load` |

Both are hard `Fail()` calls in
`src/graphics/shader/recompiler/ir/passes/ResourceTracking.cpp` — they call
`EXIT()` then `std::abort()`, so they are not configurable and no flag avoids
them.

### Which came first

There are two separate checks, both of which abort the process:

1. `"<opcode> dword <n> is not a valid runtime value"` — introduced by `af8aecf`
   (2026-08-31, *shader: remove recompiler error-string propagation*), reworked
   by `98200fe` (2026-09-03). This is what fails on 09-12, on shader
   `0x4284fbe48eca0a01`.

2. `"buffer descriptor is not a valid runtime value; GPU-selected access requires
   a raw DWORD x2/x4 load"` — introduced by `b2a80a3` (2026-09-22, *Resolve
   GPU-selected raw buffer descriptors through shared RDNA2 addressing*), with
   the guard written inline as `memory.kind != Buffer || formatted || typed ||
   (op != LoadBufferU32x2 && op != LoadBufferU32x4)`. `392f39e` (2026-09-24,
   *shader: support indirect BUFFER_LOAD_DWORDX3*) pulled that guard out into
   `MemoryInfo::SupportsIndirectBufferLoad`, added `LoadBufferU32x3`, and changed
   the message to `x2/x3/x4`. This is what fails on 09-29, on shader
   `0xb9da5e64f4c5b10a`.

So `b2a80a3` did introduce the *current* blocker, but not the abort itself: the
09-12 build already died on check 1. Between 09-12 and 09-29 check 1 stopped
firing for `0x4284fbe48eca0a01` (the later build gets past it and plays video),
leaving `0xb9da5e64f4c5b10a` as the sole remaining blocker.

### The current blocker

The 09-29 message comes from the `SupportsIndirectBufferLoad` guard:

```cpp
// src/graphics/shader/recompiler/ir/ShaderIR.h
[[nodiscard]] bool SupportsIndirectBufferLoad(ValueOpcode opcode) const {
        return !formatted && !typed && data_bits == 32u && ...
```

```cpp
// src/graphics/shader/recompiler/ir/passes/ResourceTracking.cpp
if (memory.kind != ResourceKind::Buffer || !memory.SupportsIndirectBufferLoad(op)) {
        Fail(flags.pc,
             "buffer descriptor is not a valid runtime value; GPU-selected access "
             "requires a raw DWORD x2/x3/x4 load");
}
```

Only raw `BUFFER_LOAD_DWORDX2/3/4` are accepted. `392f39e` (2026-09-24) added
`X3`; x1 and typed (`BUFFER_LOAD_FORMAT_*`) accesses are still rejected.

The older 09-12 failure came from a different call site that rejects a
`ReadConstBuffer` dword in a descriptor:

```cpp
if (value != nullptr && value->GetOpcode() == ValueOpcode::ReadConstBuffer) {
        Fail(pc, fmt::format("{} dword {} is not a valid runtime value",
                             ValueOpcodeName(expected), bad_dword));
}
```

### Related upstream reports

- #260 (Saros, main menu) — same title; its attached 09-12 log is what produced
  the table above
- #824 (Killzone: Liberation) — same error family

### Bisect

`kyty-bisect.ps1` sweeps releases and reports per-build pass/fail. Note that no
release currently passes, so use it to compare *how far* each build gets rather
than to find a working one.
