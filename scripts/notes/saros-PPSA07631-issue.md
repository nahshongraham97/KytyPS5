# Saros (PPSA07631) abort — ready-to-file report

Paste this into a new issue at
<https://github.com/KytyPS5/KytyPS5/issues/new>, or as a comment on #260.
Nothing here has been posted upstream.

Suggested title:

```
[GAME STATUS]: Saros (PPSA07631) - abort at language select, and the failure moved shaders between 09-12 and 09-29
```

---

### Game title

Saros

### Game ID / serial

PPSA07631

### KytyPS5 version

KytyPS5-2026-09-29-6799ecb and KytyPS5-2026-09-29-73615c3 (both abort)

### Compatibility status

Intro / video

### Last working build / first broken build

No release works with this dump. The failure is present in every build tested;
only which shader fails has changed.

### Result details

Both intro videos play (ATRAC9 audio and AvPlayer both work). The game then
aborts at the language-selection prompt:

```
--- Error ---
shader resource tracking: hash=0xb9da5e64f4c5b10a stage=compute pc=0x00000084 buffer descriptor is not a valid runtime value; GPU-selected access requires a raw DWORD x2/x3/x4 load in src\graphics\shader\recompiler\ir\passes\ResourceTracking.cpp
```

Notes:

- Run with `--vulkan-validation false`. With validation enabled it aborts
  earlier on a `vkAcquireNextImageKHR` semaphore VUID.
- 43 compute shaders compile before the abort.
- `NpManager_v1`, `AudioPropagation_v1` and `Agc_v1` unresolved import stubs are
  logged but are not fatal.

### The 09-12 build aborts too

The log attached to #260 (KytyPS5-2026-09-12-d3d7bd3) also ends in an abort, on
a different shader, before any video plays:

```
--- Error ---
shader resource tracking: hash=0x4284fbe48eca0a01 stage=compute pc=0x0000026c GetBufferResource dword 0 is not a valid runtime value in src\graphics\shader\recompiler\ir\passes\ResourceTracking.cpp:167
```

So something between 09-12 and 09-29 resolved `0x4284fbe48eca0a01` — real
progress — and `0xb9da5e64f4c5b10a` now blocks the same point.

| Build | Videos | Failing shader | Message |
| --- | --- | --- | --- |
| `KytyPS5-2026-09-12-d3d7bd3` | none | `0x4284fbe48eca0a01` @ pc `0x26c` | `GetBufferResource dword 0 is not a valid runtime value` |
| `KytyPS5-2026-09-29-6799ecb` | 2 | `0xb9da5e64f4c5b10a` @ pc `0x84` | `buffer descriptor is not a valid runtime value; GPU-selected access requires a raw DWORD x2/x3/x4 load` |

### Two separate checks

Both abort the process, and they are unrelated:

1. `"<opcode> dword <n> is not a valid runtime value"` — introduced by `af8aecf`
   (2026-08-31), reworked by `98200fe` (2026-09-03). The 09-12 build dies here,
   at the `ReadConstBuffer` descriptor case (`ResourceTracking.cpp:471/478`).

2. `"buffer descriptor is not a valid runtime value; GPU-selected access requires
   a raw DWORD x2/x4 load"` — introduced by `b2a80a3` (2026-09-22). The guard was
   inline: `memory.kind != Buffer || formatted || typed || (op != LoadBufferU32x2
   && op != LoadBufferU32x4)`. Then `392f39e` (2026-09-24, *shader: support
   indirect BUFFER_LOAD_DWORDX3*) extracted it into
   `MemoryInfo::SupportsIndirectBufferLoad`, added `LoadBufferU32x3`, and changed
   the wording to `x2/x3/x4`. The 09-29 build dies here.

So `b2a80a3` introduced the current blocker but not the abort itself — 09-12
already died on check 1. Between the two builds check 1 stopped firing for
`0x4284fbe48eca0a01`, which is why 09-29 plays the intro videos.

### Current blocker

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

The guard is `memory.kind != Buffer || !SupportsIndirectBufferLoad(op)`, and
`SupportsIndirectBufferLoad` accepts only raw 32-bit untyped x2/x3/x4 loads:

```cpp
[[nodiscard]] bool SupportsIndirectBufferLoad(ValueOpcode opcode) const {
        return !formatted && !typed && data_bits == 32u &&
               (opcode == ValueOpcode::LoadBufferU32x2 || opcode == ValueOpcode::LoadBufferU32x3 ||
                opcode == ValueOpcode::LoadBufferU32x4);
}
```

Either the descriptor did not resolve (`GetHandle` failed, so `memory.kind` is
not `Buffer`), or the access is typed / single-dword. A `_kyty.txt` with the
disassembly around pc `0x84` for hash `0xb9da5e64f4c5b10a` would confirm which.

These are hard `Fail()` calls that run `EXIT()` then `std::abort()`, so no flag
or config avoids them.

### Steps to reproduce

1. Extract a Windows x64 release build
2. `kyty_emulator.exe --game "<PPSA07631 folder containing eboot.bin>" --vulkan-validation false`
3. Watch the intro movies, then reach the language-selection prompt

### Expected behavior

Either resolve the descriptor, or fall back to GPU-selected DMA, instead of
aborting the process.

### OS

Windows 11

### Log file upload

Attach `_kyty.txt` from the 09-29 run (zip it; it can be tens of MB).

### Extra notes

Same error family as #824 (Killzone: Liberation).
