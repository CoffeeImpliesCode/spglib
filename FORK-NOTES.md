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
- The consumer uses a nested build to avoid a manifest cycle. It receives target, CPU, optimization, linkage and runtime/system settings, plus lazy local-cache and prefix paths and caller arguments. Global-cache and library-directory settings use the inherited `ZIG_GLOBAL_CACHE_DIR` and `ZIG_LIB_DIR` environment variables.
- Zig 0.17 run arguments use `addPassthruArgs`; formatter paths use `b.pathList`.
- The runtime generator uses Zig 0.17 AST parse options and run-step path arguments.
- Error-code conversion uses Zig 0.17's `@Int` builtin for the translated C type's unsigned width.
- The pinned Nixpkgs revision lacks Zig 0.17.0; the flake and devenv extend its Zig recipe with the upstream source hash and 0.17 langref command.
- Debug builds use Zig's safe optimization mode for Zig callers and disable C sanitization. The C core keeps its requested optimization and debug flags. This workaround follows an extern-call argument defect observed with Zig 0.16.0 on `x86_64-linux-gnu`.

## Platform boundaries

- `check-targets` compiles but does not run `x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu` and `wasm32-wasi`.
- Zig 0.17 keeps executor selection in the make phase, outside the build script. The nested consumer therefore runs only direct native targets and installs other targets under the outer prefix.
- Dynamic delivery needs a dynamic linker. WASI supports static delivery only. Windows uses the MinGW GNU target. This package does not support MSVC.
- macOS builds link CoreFoundation for CCTZ timezone lookup. Flake outputs cover `x86_64-linux`, `aarch64-linux`, `x86_64-darwin` and `aarch64-darwin`.
