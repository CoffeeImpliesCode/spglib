# Changelog

Fork changes from upstream spglib `v2.7.0`, newest first.

- `-fsys=spglib` links the installed library through pkg-config, translates its target-specific header, retains target and optimization settings, and is incompatible with runtime loading.
- Nested consumer builds forward target, CPU, optimization, linkage, runtime/system mode, executor, caches, install prefix, job settings, and caller arguments.
- The raw C API documents the six standardization calls that write through lattice and type inputs; typed calls copy into `OwnedCell`.
- Added cache, job, summary, and install-prefix settings to the canonical devenv build tasks.
- Runtime mode (`-Druntime`) exposes `load`, `loadedSource`, and `runtime_loaded`; providers are explicit, and missing optional symbols fail when called.
- `-Dlinkage=dynamic` adds shared delivery beside the static default; both install the library, headers, pkg-config metadata, and licence files.
- Added a source-only Nix package, static/shared flake outputs, and a pinned devenv environment.
- Magnetic time-reversal values use upstream's 0/1 convention.
- On Zig 0.16.0 x86-64 Linux, Debug builds keep the C core in Debug and compile Zig callers in ReleaseSafe to avoid a compiler ABI defect.
- Fixed a null dereference in `get_primitive` when pure-translation search fails.
- Reordered `src/overlap.c` buffers so double arrays stay aligned for odd atom counts.
- Exported `allocateCell`; callers choose its capacity, and standardization, primitive-finding, and refinement need four times the input atom count.
- Space-group and magnetic-space-group lookups return Hall/UNI range errors instead of zeroed records.
- The typed facade maps upstream statuses to Zig errors and validates cell sizes, atom/tensor counts, integer bounds, positive tolerances, Hall/UNI identifiers, and tensor ranks.
- Tensor inputs contain one value per atom at rank 0 or three at rank 1; higher ranks are rejected before the C call.
- Grid addresses outside the mesh retain upstream's folding behavior; components above `2^30-1` are rejected before doubled-int overflow.
- `errorMessage` returns null when upstream has no message; recorded errors are thread-local and cleared by successful calls.
- `Dataset` and `MagneticDataset` release upstream allocations with spglib's free functions; `OwnedCell` and `Symmetry` use the caller's allocator.
- The build exports module and artifact `spglib`, plus the complete translated C API and typed Zig facade.
- `build.zig` compiles the 23 upstream C units explicitly without invoking CMake.
- The build generates `version.h` from the manifest version and pinned commit.
- Lattice arrays use upstream's `lattice[column][component]` convention.
