# spglib

spglib is a C library for finding and handling crystal symmetries.
This package builds upstream spglib v2.7.0 with Zig 0.16.0 and adds a typed Zig facade.

## Source deviations from upstream

The pin is `v2.7.0` (`12355c77fb7c505a55f52cae36341d73b781a065`). Only two upstream C files are patched:

* `src/overlap.c`: reorders two allocation offsets so `double` arrays stay aligned for odd atom counts; no algorithm changes.
* `src/primitive.c`: guards `mat_free_VecDBL` when `pure_trans` is null after pure-translation search fails.

All other bytes under `src/`, `include/` and `database/` match the pin. `.gitignore` retains upstream's contents and appends fork entries. `patches/` records both C changes; `UPSTREAM.sha256` identifies the carried upstream files.

## Build deviations

* Zig's C frontend compiles 23 explicitly listed upstream translation units; it does not use CMake. `src/version.h.in` is configured from the manifest version and pinned commit.
* The native library and Zig module are named `spglib`; upstream CMake names the library `symspg`. The installed `spglib.pc` uses `-lspglib`.
* `-Dlinkage=static` is the default; `dynamic` builds a shared library. `-Druntime=true` dispatches native calls through an explicit runtime loader and is independent of linkage. Runtime loading is refused with system-library mode.
* `-fsys=spglib` uses the installed header and library via pkg-config; it builds no native artifact and does not include this fork's patched C sources.
* The build links `libm` on Linux, the BSDs and illumos. For Zig 0.16.0 Debug builds, Zig callers use `ReleaseSafe` and C sanitization is disabled to work around an extern-call argument defect; the C core retains the requested optimization and `SPGDEBUG`.

## Support matrix

| Target or route | Status |
|---|---|
| `x86_64-linux-gnu` | Earlier recorded runs passed 55/55 tests for linked and loaded routes, static and dynamic, in all four optimization modes. Later source edits make a replay necessary. |
| `aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu`, `wasm32-wasi` | Compile-only checks; not executed. |
| MSVC | Not built or tested; no support claim. |
| System library | Requires an installed `spglib`; no run is recorded. Runtime loading with system mode is rejected. |
| Nix | Flake outputs name `x86_64-linux`, `aarch64-linux`, `x86_64-darwin` and `aarch64-darwin`. Only `x86_64-linux` was built, before the later target change; the other systems are unverified. |

## Consumption

Use a local path dependency; no published URL or content hash is confirmed:

```zon
.dependencies = .{
    .spglib = .{ .path = "../spglib" },
},
```

`dep.module("spglib")` exports the facade and links the in-tree library. In vendored mode, `dep.artifact("spglib")` is the native library artifact and carries the installed header include path for C consumers. The installed C interface is `include/spglib.h`, `include/spglib/version.h` and `lib/pkgconfig/spglib.pc`; library files are `libspglib.a` or `libspglib.so` (with versioned links for the shared build).

| Option | Meaning |
|---|---|
| `-Dtarget=<triple>`, `-Dcpu=<cpu>`, `-Doptimize=<mode>` | Standard Zig target, CPU and optimization selections. |
| `-Dlinkage=static\|dynamic` | Select the delivered library; static is default. |
| `-Druntime=true` | Enable runtime loading; default is linked calls. |
| `-fsys=spglib` / `-fno-sys=spglib` | Select the installed system library or force the in-tree build. |
