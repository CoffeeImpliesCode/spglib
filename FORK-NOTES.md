# Fork notes

This file lists upstream source changes, build graph differences and platform limits. Upstream identity and digests are in `UPSTREAM.md` and `UPSTREAM.sha256`.

## Upstream-tree deviations

The fork patches two upstream C files. Other files under `src/`, `include/` and `database/` match upstream.

| File | Change and reason |
| --- | --- |
| `src/overlap.c` | Moves `offset_perm_temp` after `offset_pos_sorted` to align `double` arrays for odd atom counts. |
| `src/primitive.c` | Guards `mat_free_VecDBL` against a null `pure_trans` after search failure. |

`patches/` records both changes. `.gitignore` keeps upstream entries and adds fork-specific ignore patterns.

## Build-graph deviations

- `build.zig` replaces upstream CMake and compiles an explicit list of 23 C translation units. The build generates `version.h` from the manifest version and pinned commit, not a VCS query.
- C flags are `-std=c11`, `-fvisibility=hidden`, `-DSPGINFO` and `-DSPGWARNING`, plus `-DSPGDEBUG` in Debug. `SPG_BUILD` marks the core library. Static builds also define `SPG_STATIC_LIBRARY` for the core and translated header.
- `spglib` is the native artifact and module name. Upstream CMake names the library `symspg`. `spglib.pc` uses relocatable paths and `-lspglib`. `libm` and `SPG_STATIC_LIBRARY` flags follow target and linkage.
- The install includes public headers and licence records. Database tables live in C sources, so the install has no runtime data.
- `-Dlinkage=static` is the default. `dynamic` builds a shared library. `-Druntime=true` selects explicit provider loading, independent of linkage.
- `-fsys=spglib` uses the installed header and library through pkg-config. It builds no native artifact. `-fno-sys=spglib` forces bundled sources. System mode cannot use runtime loading because installed headers lack provider-version macros.
- The consumer uses a nested build to avoid a manifest cycle. That build gets the same target, CPU, optimization, linkage, runtime and system-mode settings. It also gets executor, cache, prefix and caller arguments. It runs only when an enabled executor can run the target.
- Debug builds use ReleaseSafe for Zig callers and disable C sanitization. The C core keeps its requested optimization and debug flags. This works around an extern-call argument defect that Zig 0.16.0 showed on `x86_64-linux-gnu`.

## Platform boundaries

- `check-targets` compiles but does not run `x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu` and `wasm32-wasi`.
- Execution needs the native host or an enabled QEMU, Wasmtime, Wine or Darling executor. Without one, the consumer step installs the target instead of running it.
- Dynamic delivery needs a dynamic linker. WASI supports static delivery only. Windows uses the MinGW GNU target. This package does not support MSVC.
- macOS builds link CoreFoundation for CCTZ timezone lookup. Flake outputs cover `x86_64-linux`, `aarch64-linux`, `x86_64-darwin` and `aarch64-darwin`.
