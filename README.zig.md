# Using spglib from Zig

This file documents the Zig packaging of upstream spglib `v2.7.0`. For what
spglib itself does, see the upstream `README.md` and `docs/`. For provenance, see
`UPSTREAM.md`; for what this fork changed, see `CHANGELOG.md`.

## Adding the dependency

This package belongs to a private repository, so an unauthenticated fetch of a
remote URL cannot succeed, and no published URL or content hash has been
confirmed for it. The arrangement that resolves without credentials is a
dependency on a local clone, which is what `zig/consumer/` uses:

```zon
// build.zig.zon
.dependencies = .{
    .spglib = .{ .path = "../spglib" },
},
```

No command produces that line and no digest appears in it: a `.path`
dependency is resolved where it stands. A manifest also needs `.name`,
`.fingerprint` and `.minimum_zig_version`; `zig/consumer/build.zig.zon` is a
complete worked example, and the fingerprint is the value the toolchain
computes for the package name, so it has to be generated rather than copied.

This compiler has no `zig fetch` command. Its build runner documents
`--fetch[=mode]`, with `needed` or `all`, to fetch the dependency tree and
exit, and `--fork=[path]` to override one or more projects from that tree
(`lib/compiler/build_runner.zig:1662-1666`); neither is needed for a `.path`
dependency. If this package is ever published, a credentialed tarball `.url`
plus `.hash` becomes possible, and until the integration owner confirms a URL
and a digest, none is recorded here: a configured `origin` is an intention, not
a receipt.

```zig
// build.zig
const spglib_dep = b.dependency("spglib", .{
    .target = target,
    .optimize = optimize,
});

const exe = b.addExecutable(.{
    .name = "app",
    .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{.{ .name = "spglib", .module = spglib_dep.module("spglib") }},
    }),
});
```

`dep.module("spglib")` already links the compiled library, so nothing else is
needed to call the API. Code that compiles its own C against `spglib.h` also
wants `dep.artifact("spglib")`, which carries the include path of the installed
headers:

```zig
exe.root_module.linkLibrary(spglib_dep.artifact("spglib"));
```

`zig/consumer/` is exactly this arrangement: a separate package with its own
manifest that depends on this one by path. It runs with `zig build run` from
that directory, and `zig build consumer` drives the same build from the root.
It is not a dependency of this package's manifest, because its manifest points
back at this one; the root invokes it as a separate `zig build` instead.

## Identifying a cell

```zig
const spglib = @import("spglib");

const cell = spglib.Cell{
    // `[[a_x, b_x, c_x], [a_y, b_y, c_y], [a_z, b_z, c_z]]`: the basis vectors
    // a, b and c are the columns, as include/spglib.h and spglib itself use.
    // This cubic example is symmetric, so the layout only shows on an
    // oblique cell such as `fixtures.corundum`.
    .lattice = .{
        .{ 3.905, 0, 0 },
        .{ 0, 3.905, 0 },
        .{ 0, 0, 3.905 },
    },
    // Fractional coordinates.
    .positions = &.{
        .{ 0, 0, 0 },
        .{ 0.5, 0.5, 0.5 },
        .{ 0.5, 0.5, 0 },
        .{ 0.5, 0, 0.5 },
        .{ 0, 0.5, 0.5 },
    },
    .types = &.{ 1, 2, 3, 3, 3 },
};

const dataset = try spglib.getDataset(cell, 1e-5);
defer dataset.deinit();

std.debug.print("{d} {s}\n", .{ dataset.spacegroupNumber(), dataset.internationalSymbol() });
const operations = dataset.operations();
```

Symmetry operations use the upstream convention `x_new = rotation * x + translation`.
`dataset.operations().rotations` and `.translations` are borrowed slices; they are
valid until `dataset.deinit()` and must not be stored past it.

## Ownership rules

| Type | Memory source | How to release |
| --- | --- | --- |
| `Dataset` | upstream `malloc` inside `spg_get_dataset` | `deinit`, which calls `spg_free_dataset` |
| `MagneticDataset` | upstream `malloc` inside `spg_get_magnetic_dataset` | `deinit`, which calls `spg_free_magnetic_dataset` |
| `OwnedCell` | the allocator passed to `standardizeCell`, `findPrimitive`, `refineCell` | `deinit`, with the same allocator |
| `Symmetry` | the allocator passed to `getSymmetry`, `getSymmetryFromDatabase` | `deinit`, with the same allocator |
| `SpacegroupType`, `MagneticSpacegroupType`, `PointGroup`, `Version` | copied into the value | nothing to release |
| `Cell` | the caller's slices | nothing to release |

No global allocator hook is installed. Upstream memory is freed by the upstream
free function, never by a Zig allocator, and Zig memory is never freed by an
upstream function.

`spg_standardize_cell`, `spg_find_primitive` and `spg_refine_cell` write up to
four times the input atom count into buffers they never size-check, and only
`spg_refine_cell` says so (`include/spglib.h:463-471`). `standardizeCell`,
`findPrimitive` and `refineCell` therefore allocate `4 * atomCount` slots
themselves and trim them to the count spglib returns, so a caller cannot
undersize them. `allocateCell` allocates exactly the capacity it is asked for
and adds no headroom: a caller who drives those C entry points directly has to
supply four times the input atom count.

`getSymmetry` allocates the capacity the caller bounds the search by and
`getSymmetryFromDatabase` allocates the fixed 192-operation database entry that
`include/spglib.h:404-407` declares; both shrink to the number of operations
spglib reports. If the allocator cannot shrink a buffer, the oversized buffer
stays owned by the same allocator, so `deinit` is correct either way.

Strings and slices handed out by the facade point into these owners. The version
strings and spglib error messages point into library static storage and stay
valid for the life of the process. `SpacegroupType` and
`MagneticSpacegroupType` are the exception that is not a borrow at all: their
character arrays are copied into the returned value, which is why their
accessors take `*const`.

## Errors

spglib reports failure through return values plus a status recorded by
`spg_get_error_code`. The facade turns that status into a Zig error, so failures
cannot be mistaken for success:

```zig
const dataset = spglib.getDataset(cell, 1e-5) catch |failure| switch (failure) {
    error.AtomsTooClose => return report("atoms overlap within symprec"),
    error.SpacegroupSearchFailed => return report("no space group found"),
    else => |other| return other,
};
defer dataset.deinit();
```

The recorded status is a diagnostic, not a second result channel. spglib keeps
it in a `static thread_local` (`src/spglib.c:50`) and every successful entry
point overwrites it with `SPGLIB_SUCCESS`, `getVersion` included, so:

* it is per-thread, not process-wide;
* it is only meaningful immediately after a call that failed;
* any later successful call in the same thread clears it.

Read it before making another call, and treat the error the facade returned as
the reliable answer:

```zig
const dataset = spglib.getDataset(cell, 1e-5) catch |failure| {
    // Read the status here: a later successful call clears it.
    const code = spglib.lastErrorCode();
    // Null for `.none`: spg_get_error_message stops at the SPGERR_NONE
    // sentinel before it compares its argument, so that code has no message.
    std.debug.print("{s}: {?s}\n", .{ @errorName(failure), spglib.errorMessage(code) });
    return failure;
};
defer dataset.deinit();
```

`errorMessage` therefore returns `?[]const u8`. `error.None` means spglib
reported failure without recording a specific code, so the message is null; it
is deliberately not folded into success.

Caller mistakes the C API cannot express are reported as `InputError` before any
C call happens: `EmptyCell`, `AtomCountMismatch`, `AtomCountOutOfRange`,
`TensorCountMismatch`, `OperationCountOutOfRange`, `HallNumberOutOfRange`,
`UniNumberOutOfRange`, `MeshOutOfRange`, `GridAddressOutOfRange`,
`NonPositiveSymprec` and `TensorRankOutOfRange`.

`getSpacegroupType` and `getMagneticSpacegroupType` are fallible for that
reason: `spg_get_spacegroup_type` records a failure and hands back a zeroed
struct for a Hall number outside 1..530, and the magnetic entry point does the
same outside 1..1651, so a plain value would look like a successful lookup with
empty strings.

`getSymmetry` is bounded by the caller. spglib refuses to truncate, so a buffer
that is too small produces `error.ArraySizeShortage` rather than a partial
result:

```zig
const symmetry = try spglib.getSymmetry(allocator, cell, 1e-5, 192);
defer symmetry.deinit();
```

## Magnetic symmetry

Magnetic symmetry is a separate API in upstream and stays separate here:

```zig
const magnetic = try spglib.getMagneticDataset(cell, &spins, 1e-5);
defer magnetic.deinit();

const reversals = magnetic.timeReversals(); // 1 without time reversal, -1 with
```

`getMagneticDataset` is the collinear-spin form: one scalar per atom. For a
vector per atom use
`getMagneticDatasetWithTensors(cell, tensors, .{ .rank = 1, .symprec = 1e-5, .is_axial = true })`,
where `tensors` holds three doubles per atom. Those are upstream's counts, not
a convention this package chose: it allocates `num_atoms` doubles at rank 0 and
`num_atoms * 3` at rank 1 (`src/cell.c:67-79`, `src/spin.c:279-293`) and states
both in the `Cell` contract (`src/cell.h:31-32`). The tensor slice must hold
exactly `atomCount * tensorVolume(rank)` values, so any other length is
`error.TensorCountMismatch` before the C call, and `standardTensors` reports the
same counts for the standardised cell.

`spglib` implements no other rank: `SiteTensorType` stops at `NONCOLLINEAR`
(`src/cell.h:10-14`) and `spn_alloc_site_tensors` returns NULL above it, so a
rank above 1 is rejected with `error.TensorRankOutOfRange` before any C call
rather than reaching tensor storage upstream never allocated.

## Escape hatch

`pub const c` is the complete translated `include/spglib.h`, including the
k-point mesh routines (`spg_get_ir_reciprocal_mesh` and friends), the deprecated
compatibility entry points and the magnetic database lookups. Nothing is
filtered:

```zig
var rotations: [192][3][3]c_int = undefined;
var translations: [192][3]f64 = undefined;
const size = spglib.c.spg_get_symmetry_from_database(&rotations, &translations, 460);
```

The escape hatch and the facade come from the same module and the same link,
which is what `zig/consumer/` checks: it identifies a cubic perovskite through
the facade and then calls `spglib.c.spg_get_spacegroup_type` directly for an
answer fixed by the database upstream ships.

## Build steps

| Step | What it does |
| --- | --- |
| `zig build` | Builds and installs the library, module and headers |
| `zig build test` | Runs the three native test binaries |
| `zig build smoke` | Runs `zig/examples/smoke.zig`, which prints deterministic results and checks them |
| `zig build check` | Compiles the library, the public facade, the tests and the example without running anything |
| `zig build check-targets` | The same compile-only analysis for `x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu` and `wasm32-wasi` |
| `zig build consumer` | Runs the consumer package in `zig/consumer`, in its own build, against the exported module and artifact |
| `zig build fmt-check` / `zig build fmt` | Zig formatting of `build.zig`, `build.zig.zon` and `zig/` |

The options those steps read:

| Option | What it does |
| --- | --- |
| `-Dtarget=<triple>` | Target triple, parsed the same way the cross matrix parses it |
| `-Dcpu=<cpu>` | Target CPU features |
| `-Doptimize=Debug\|ReleaseSafe\|ReleaseFast\|ReleaseSmall` | Optimization mode |
| `-Dlinkage=static\|dynamic` | Static by default; `dynamic` is what the export macros follow |
| `-fsys=spglib` | Link an installed spglib instead of the one in this tree |
| `-fno-sys=spglib` | Force the in-tree build, including under `--system` |

`zig build consumer` forwards `-Dtarget=`, `-Dcpu=` and `-Doptimize=` to the
consumer's own build, and gives it a subdirectory of the outer cache directory
when the outer build was given one. A target this host can run is run; a
foreign one is only built and installed, because a cross-compiled binary cannot
execute here.

`.github/workflows/zig-fork-ci.yaml` is the only CI workflow in this
repository: it runs the provenance gate and the native, cross and consumer
jobs above. The upstream workflows that arrived with the import were removed,
because two of them publish to the upstream PyPI project and Codecov account;
`CHANGELOG.md` entry 7 names them and gives the reasons. The workflow does not
exercise `-fsys=spglib`, because the runner has no installed spglib to link.

Cross-target analysis compiles but never runs; it proves the code builds for
those targets, not that it behaves there.

`FORK-NOTES.md` records each entry as PENDING-VERIFICATION from the author's
side, because no author runs a gate. What the integration owner observed with
Zig 0.16.0 is written down where it happened: `CHANGELOG.md` entries 12 and 13,
and entry 30 of `FORK-NOTES.md` for the compiler defect that had to be worked
around before any of it could pass. Where an entry and a gate disagree, the gate
is the newer fact and the entry says so.

## One thing to know before reading a Debug failure

Zig 0.16.0 at `-O Debug` mis-assigns the floating-point arguments of an
`extern "C"` call that has seven or more integer-class arguments: they land in
xmm6 and xmm7 while the callee reads xmm0 and xmm1. Every spglib entry point
that takes more than six integer arguments also takes a `double`, so every one
of them received a garbage tolerance. `build.zig` therefore compiles the Zig
caller at `ReleaseSafe` when the requested mode is `Debug`, and turns C
sanitization off on the core so the two halves link. The C library still builds
at the requested optimisation with `-DSPGDEBUG`, so the Debug gate still
exercises the debug build of the C. `FORK-NOTES.md` entry 30 has the
reproducer, which is five fixed-arity C functions and no spglib at all.

## Platform notes

* The core needs libc, and `libm` on glibc and BSD targets; `libm` is folded into
  libc on macOS, Windows and wasi.
* System-library mode is selected with `-fsys=spglib`, not with a `-D` option.
  `b.systemIntegrationOption` records the library name in the build graph's
  system-integration map, and the build runner is what turns `-fsys=spglib` or
  `-fno-sys=spglib` into that entry; a name the build script never declared is
  an error rather than a silent no-op. In that mode the aggregate header
  includes the bare `<spglib.h>` from the system include path and no include
  path of this tree is added, so the translation sees the header installed next
  to the library it links, and the link name is `symspg`, the name upstream's
  build and `spglib.pc` use. The bare header name is the one upstream installs:
  its `FILE_SET HEADERS` has no `BASE_DIRS`, so `spglib.h` lands directly in the
  include directory. No artifact is produced in that mode, so `dep.artifact`
  has nothing to resolve.
* The upstream Fortran, Python and Ruby bindings are not part of this package.