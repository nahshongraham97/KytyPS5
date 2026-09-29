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

### Not a regression from b2a80a3

The `... is not a valid runtime value` family predates every published release:

- `af8aecf` (2026-08-31, *shader: remove recompiler error-string propagation*) —
  introduced it
- `98200fe` (2026-09-03) — reworked it
- `b2a80a3` (2026-09-22) — added the GPU-selected wording

`b2a80a3` is not the origin: 09-12 already had the check, at a different call
site (`ResourceTracking.cpp:471/478`, the `ReadConstBuffer` descriptor case).

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

Only raw `BUFFER_LOAD_DWORDX2/3/4` are accepted (`392f39e` added `X3` on
2026-09-24). The disassembly around pc `0x84` shows `BUFFER_LOAD_FORMAT_X` with
`idxen` — a typed, single-dword access — which the guard rejects outright.

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
