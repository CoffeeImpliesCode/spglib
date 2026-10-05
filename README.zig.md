# Using spglib from Zig

This file documents the Zig packaging of upstream spglib `v2.7.0`: the
dependency, the API, ownership and errors. For what this fork changed, its
support matrix and how to consume an installed copy, see `README.md`; for what
spglib itself does, see the upstream `README.upstream.md` and `docs/`. For
provenance, see `UPSTREAM.md`, and for the licence, `NOTICE.md` and
`FORK-LICENSE.md`.

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

`zig fetch` does exist in this compiler: its own usage text shows
`zig fetch --save <url>`, which records a resolved dependency, and
`zig fetch <path-or-url>`, which fetches one. Neither is needed for a `.path`
dependency, and neither can succeed for a package with no published URL — an
argument naming a path that is not there is refused, with the argument
diagnosed as neither an existing file path nor a URL. The build runner's own
`--fetch[=mode]`, with `needed` or `all`, fetches the dependency tree and exits,
and `--fork=[path]` overrides one or more projects from that tree
(`lib/compiler/build_runner.zig:1662-1666`); those are a separate pair of
options and neither is needed either. If this package is ever published, a
credentialed tarball `.url` plus `.hash` becomes possible, and until the
integration owner confirms a URL and a digest, none is recorded here: a
configured `origin` is an intention, not a receipt.

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
| `Dataset` | upstream `malloc` inside `spg_get_dataset`, `spg_get_dataset_with_hall_number` and `spgat_get_dataset` | `deinit`, which calls `spg_free_dataset` |
| `MagneticDataset` | upstream `malloc` inside `spgms_get_magnetic_dataset` | `deinit`, which calls `spg_free_magnetic_dataset` |
| `OwnedCell` | the allocator passed to `allocateCell`, `standardizeCell`, `findPrimitive` or `refineCell` | `deinit`, with the same allocator |
| `Symmetry` | the allocator passed to `getSymmetry`, `getSymmetryFromDatabase` | `deinit`, with the same allocator |
| `SpacegroupType`, `MagneticSpacegroupType`, `PointGroup` | characters and numeric fields copied into the value | nothing to release |
| `Version` | numeric fields copied; string slices borrow library static storage | nothing to release |
| `Cell` | the caller's slices | nothing to release |

No global allocator hook is installed. Upstream memory is freed by the upstream
free function, never by a Zig allocator, and Zig memory is never freed by an
upstream function. A Zig leak oracle therefore cannot see the first two rows:
`std.testing.allocator` observes the allocations it handed out and no others.

Every owner in that table is single-owner. Copying one of these values copies
the handle, not the storage, so a copy is not a second owner and must not be
`deinit`'d: a copied `Dataset` or `MagneticDataset` frees the same upstream
allocation twice, and a copied `OwnedCell` or `Symmetry` frees the same two Zig
buffers twice. Nothing in the type system stops either call. The allocator an
`OwnedCell` or a `Symmetry` stores must stay valid until its `deinit`, and that
`deinit` must run before the allocator itself goes away.

`spg_standardize_cell`, `spg_find_primitive` and `spg_refine_cell` write up to
four times the input atom count into buffers they never size-check, and only
`spg_refine_cell` says so (`include/spglib.h:463-471`). Four is the library's
own growth factor rather than a round number: `spa_transform_to_primitive`
sizes the conventional cell from `primitive->size * multi`
(`src/spacegroup.c:609-618`) and `get_centering_shifts`
(`src/spacegroup.c:1879-1931`) returns at most 4, for F centring.
`standardizeCell`, `findPrimitive` and `refineCell` therefore allocate
`4 * atomCount` slots themselves and trim them to the count spglib returns, so a
caller cannot undersize them. `allocateCell` allocates exactly the capacity it
is asked for and adds no headroom: a caller who drives those C entry points
directly has to supply four times the input atom count itself.

`getSymmetry` allocates the capacity the caller bounds the search by and
`getSymmetryFromDatabase` allocates the fixed 192-operation database entry that
`include/spglib.h:404-407` declares; both shrink to the number of operations
spglib reports. If the allocator cannot shrink a buffer, the oversized buffer
stays owned by the same allocator, so `deinit` is correct either way.

Every slice the facade hands out is a borrow, and `deinit` is what invalidates
it. `Dataset.operations`, `Dataset.wyckoffs`, `MagneticDataset.timeReversals`
and the rest read spglib's own arrays and dangle the moment the owning dataset
is released; `OwnedCell.asCell` borrows that cell's buffers until it is
released; `Symmetry.operations` borrows the symmetry's own buffers. The version
strings and spglib error messages are the exception that is not a borrow at
all: they point into library static storage and stay valid for the life of the
process. `SpacegroupType` and `MagneticSpacegroupType` are the other exception:
their character arrays are copied into the returned value, which is why their
accessors take `*const` and why a copy of either needs no release.

`Dataset.raw` and `MagneticDataset.raw` are reachable fields, so a caller may
replace the upstream pointer every accessor reads. Nothing checks it: a value
that did not come from a successful dataset call breaks every accessor, and
`deinit` frees whatever it points at.

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

The two grid errors are about arithmetic, not about membership.
`gridPointFromAddress` bounds nothing by the mesh: `src/kgrid.c` folds an address
outside the mesh onto the point it names — in a 2×2×2 mesh, `{3,0,0}`, `{1,0,0}`
and `{5,0,0}` are all index 1 — and only a component above `2^30-1` is refused,
because `address[i] * 2` cannot hold it (`src/kgrid.c:39`).
`MeshOutOfRange` covers a mesh entry that is not positive, which
`modulo_i3` divides by (`src/kgrid.c:100`), and one above `2^30-1`, which
`2 * mesh[i]` cannot hold (`src/kgrid.c:125`).

`getSpacegroupType` and `getMagneticSpacegroupType` are fallible for that
reason: `spg_get_spacegroup_type` records a failure and hands back a zeroed
struct for a Hall number outside 1..530, and the magnetic entry point does the
same outside 1..1651, so a plain value would look like a successful lookup with
empty strings.

`getSymmetry` is bounded by the caller. spglib refuses to truncate, so a buffer
that is too small produces `error.ArraySizeShortage` rather than a partial
result. Upstream deprecates the C entry point it wraps, `spgat_get_symmetry`,
with "Use the variables from SpglibDataset (rotations, translations)"
(`include/spglib.h:247-258`); the replacement the message names is
`getDataset(cell, symprec).operations()`, which carries the same operations in
the same convention with no bound to choose and is released by
`Dataset.deinit`. The facade keeps both because they own their memory
differently: this one allocates from the caller's allocator, the dataset
allocates through spglib.

```zig
const symmetry = try spglib.getSymmetry(allocator, cell, 1e-5, 192);
defer symmetry.deinit();
```

## Magnetic symmetry

Magnetic symmetry is a separate API in upstream and stays separate here:

```zig
const magnetic = try spglib.getMagneticDataset(cell, &spins, 1e-5);
defer magnetic.deinit();

// 0 is an ordinary operation, 1 carries time reversal. Never -1: that
// convention belongs to the separate `spin_flips` output of
// `spg_get_symmetry_with_site_tensors` (include/spglib.h:286-288).
const reversals = magnetic.timeReversals();
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

The 0/1 convention is upstream's own: `spin.c:493` sets
`timerev = (1 - spin_flip) / 2` with `spin_flip` in {+1,-1}, `spglib.c:508`
inverts it as `spin_flip = 1 - 2 * timerev`, and the stored flag is therefore
0 or 1. `docs/magnetic_dataset.md:82-85` and `python/spglib/msg.py:481` state
the same contract. Reading a `-1` out of this array means the caller looked at
`spin_flips`, which is a different output with a different ±1 meaning
(`include/spglib.h:286-288`).

`spglib` implements no other rank: `SiteTensorType` stops at `NONCOLLINEAR`
(`src/cell.h:10-14`) and `spn_alloc_site_tensors` returns NULL above it, so a
rank above 1 is rejected with `error.TensorRankOutOfRange` before any C call
rather than reaching tensor storage upstream never allocated.

## Escape hatch

`pub const c` is the complete translated `include/spglib.h`: the k-point mesh
routines (`spg_get_ir_reciprocal_mesh` and friends), the deprecated
compatibility entry points, the magnetic database lookups and every other
entry point the header declares. Nothing is filtered, and the module doc in
`zig/root.zig` lists each declaration the typed facade leaves behind:

```zig
var rotations: [192][3][3]c_int = undefined;
var translations: [192][3]f64 = undefined;
const size = spglib.c.spg_get_symmetry_from_database(&rotations, &translations, 460);
```

Most of that surface only reads through the pointers it is given. **Six
declarations do not, and the obligation stays with the caller who uses them
raw.** `spg_standardize_cell` and its `spgat_` spelling
(`include/spglib.h:437,442`), `spg_find_primitive` and its `spgat_` spelling
(`:454,458`), and `spg_refine_cell` and its `spgat_` spelling
(`include/spglib.h:469,473`) drop `const` from the lattice and the types where
every other declaration in the header keeps it, and the writing is in the C:
`set_cell` copies the lattice at `src/spglib.c:2070` and assigns
`types[i] = cell->types[i]` at `:2072`, and `standardize_cell` writes at
`:1926-1928`, with the header's own warning at `:450`. A caller reaching for
`spglib.c.spgat_standardize_cell` — or any other of the six — must hand in
writable storage. `Cell.types` is caller storage that may sit in read-only
data, which is why a caller that must standardise copies into an `OwnedCell`
first; that is what the typed surface does for you and what the raw route does
not. The typed surface's own `mutableTypePtr` and `latticePtr` document the
same six, and `FORK-NOTES.md` entry 37 records how the list was established.

That was checked against the library, not only against the header. A direct
probe answered **8 of 8 steps on the linked static route and 8 of 8 on the
loaded route** against an **own dynamically loaded provider** — this SDK's own
`libspglib.so`, built at
`…/native-final-prefixes/contract-final-after-20261004/spglib-dynamic-Debug/lib/libspglib.so`
and not downloaded — and every run gave space group
**225 Fm-3m**, Hall **523**, **192** operations and a **2-atom** primitive
cell, with the borrowed arrays' bytes unchanged afterwards. Read that last part
as **unchanged bytes** and nothing stronger: equal bytes cannot distinguish an
array that was never written from one written back with the same values, and
the six declarations do write. The scope is a direct smoke over the typed
surface plus an FFI fixture that reads a dataset through `getDataset`'s `const`
lattice and then standardises a copy through an `OwnedCell`; it is **not** a
whole-SDK source-identity claim, and no API type, macro, native source or C
cast changed. Receipt: `FORK-NOTES.md` entry 37 carries it in full.

Upstream marks these C entry points `SPG_DEPRECATED`, and each message names
the replacement to move to:

| Deprecated C entry point | Use instead |
| --- | --- |
| `spg_get_symmetry`, `spgat_get_symmetry` | `getDataset(...).operations()` |
| `spg_get_multiplicity`, `spgat_get_multiplicity` | `Dataset.operationCount()` |
| `spg_get_international`, `spgat_get_international` | `Dataset.spacegroupNumber()` and `Dataset.internationalSymbol()` |
| `spg_get_schoenflies`, `spgat_get_schoenflies` | `getSpacegroupType(dataset.hallNumber()).schoenflies()` |
| `spg_get_hall_number_from_symmetry` | `Dataset.hallNumber()` or `SpacegroupType.hallNumber` |
| `spg_get_layer_dataset` | nothing here; upstream marks the layer-group interface experimental and subject to removal in the next major release |

One sentinel in that group is easy to misread: a Hall number of `0` passed to
`c.spg_get_magnetic_symmetry_from_database` is valid and selects the smallest
Hall number for that UNI number (`include/spglib.h:409-424`). The same call's
`time_reversals` output holds the same 0/1 flags a magnetic dataset carries.
`0` is not a valid Hall number for `getSpacegroupType` or
`getMagneticSpacegroupType`, which is where `error.HallNumberOutOfRange` and
`error.UniNumberOutOfRange` come from; only `getDatasetWithHallNumber` accepts
it, because only there `0` means "the same search `getDataset` runs"
(`include/spglib.h:232-236`).

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
| `-Druntime=true` | Reach the native entry points through the loader instead of linking them; boolean, default false, orthogonal to `-Dlinkage`. Refused with `-fsys=spglib`, because the installed header carries no version macros for the dispatch to validate a provider against |
| `-fsys=spglib` | Link an installed spglib instead of the one in this tree |
| `-fno-sys=spglib` | Force the in-tree build, including under `--system` |

`zig build consumer` runs a second `zig build` in `zig/consumer`, so the two
graphs have to agree about what was asked for. `runConsumer` in `build.zig`
forwards `-Dtarget=`, `-Dcpu=`, `-Doptimize=`, `-Druntime=` and `-Dlinkage=`
as one `-Dkey=value` argument each. The two booleans, the linkage and the
system selection are written out in both directions, `-fsys=spglib` or
`-fno-sys=spglib`, so the nested build's own defaults are never in charge.

The executor switches this build resolved follow: `-fdarling`, `-fqemu`,
`-frosetta`, `-fwasmtime`, `-fwine`, each one only when it is on, plus
`--libc-runtimes` with its directory. Then `-j8` and `--summary all`, the same
two flags `devenv.nix` writes. A local cache subdirectory follows when the
outer build was given one, as `--cache-dir` and `<outer>/consumer`. The
caller's `--global-cache-dir` follows unchanged, because that cache holds the
fetched packages every graph in this workspace shares. The caller's install
prefix follows when it named one, as `--prefix` with an absolute path, because
without it the nested build installs into `zig/consumer/zig-out` inside this
checkout rather than into the prefix that was asked for. The caller's own
trailing arguments come last, behind `--`, and the nested build hands them
again to the consumer program, so a provider name passed after that `--`
reaches it.

The step is `run` when `hostCanExecute` says this build can execute the
resolved target, and `install` when it cannot. That predicate is
`std.zig.system.getExternalExecutor`, the one `std.Build.Step.Run` asks about
the artifact it is about to spawn. An external executor counts only when the
build runner was told it may use one. So a foreign target runs under QEMU,
Wasmtime, Wine or Darling when that switch is on, and it builds and installs
when no executor is enabled for it.

That forwarding is observed rather than asserted. Nine `zig build consumer`
cases on this host's `x86_64-linux-gnu` recorded the nested command line the
outer build produced, across both linkages, both runtime selections, the default
and the explicit target, both cache directories and the install prefix. The
provider reached the program as a flag after the `--`, and no provider variable
was in the child environment, so no loaded case passed on an inherited one. Every
case is this host's own target, so the external-executor arms above and the
`-fsys=spglib` route are still unobserved. `README.md` carries the receipt.

`devenv shell` is the canonical development environment; each step above has a
namespaced task (`devenv tasks run sdk:test -- -Doptimize=Debug`), and the
packaged variants are `nix build .#static` / `.#shared` or `devenv build
outputs.static` / `.shared`. Each task changes to this package's own directory
first, because devenv runs a task with the caller's working directory rather
than this package's, and `sdk:build` — the only task whose command installs —
installs into `$SPGLIB_INSTALL`, else `$ZIG_LOCAL_CACHE_DIR/spglib/zig-out`,
else `$TMPDIR/spglib/zig-out`, with no `/tmp` default and a named error when the
caller exported none of those three, so no `zig build` through devenv writes a
`zig-out/` into the checkout. `README.md` has the installed layout and the
support matrix.

`.github/workflows/zig-fork-ci.yaml` is the only CI workflow in this
repository, with five jobs: the provenance gate, the native build with tests in
both optimization modes and the smoke example, the six-target compile check,
the downstream consumer package, and a delivery job that installs the static and
the shared delivery into separate prefixes, installs the runtime route under
both linkages too, checks the installed layout, link metadata and licence
records, compiles and runs upstream's own `example/c_api/example.c` against each
installed prefix through that pkg-config file, and compile-checks the public
surface under `-Druntime=true` for the host and for all six targets. The upstream
workflows that arrived with the import were removed, because two of them publish
to the upstream PyPI project and Codecov account; `CHANGELOG.md` entry 7 names
them and gives the reasons. No job exercises `-fsys=spglib`, because the runner
has no installed spglib to link. A green workflow is a statement about this
repository only and says nothing about what has been published anywhere.

Cross-target analysis compiles but never runs; it proves the code builds for
those targets, not that it behaves there.

`FORK-NOTES.md` records each entry as PENDING-VERIFICATION from the author's
side, because no author runs a gate. What the integration owner observed with
Zig 0.16.0 is written down where it happened: the matrix in `README.md` is the
current record, `CHANGELOG.md` entries 12 and 13 carry the magnetic and
optimization findings, and entry 30 of `FORK-NOTES.md` carries the compiler
defect that had to be worked around before any of it could pass. Where an entry
and a gate disagree, the gate is the newer fact and the entry says so.

## One thing to know before reading a Debug failure

`FORK-NOTES.md` entry 30 records wrong floating-point arguments in Zig 0.16.0
Debug on x86_64-linux-gnu for calls with at least seven integer-class arguments
and a `double`. Pure-integer calls and `spg_get_dataset` did not show that
failure. The register-level cause was not established. The reproducer used five
fixed-arity C functions, independent of spglib.

The build selects `ReleaseSafe` for its Zig callers when `Debug` is requested
and disables C sanitization so the halves link. The C core still uses the
requested mode and `-DSPGDEBUG`. An external caller using `spglib.c` directly
must account for the same compiler limit at its own call site.

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
  to the library it links. That library is named `spglib` and it is reached
  through pkg-config with `.force`, not written out by hand as `-lsymspg`:
  `symspg` is what upstream's CMake install names the file
  (`CMakeLists.txt:108-113`, `cmake/spglib.pc.in:4`) and is not a stem this
  package installs or links. The bare header name is the one upstream installs:
  its `FILE_SET HEADERS` has no `BASE_DIRS`, so `spglib.h` lands directly in the
  include directory. No artifact is produced in that mode, so `dep.artifact`
  has nothing to resolve.
  That mode also drops this fork's own C corrections.
  `patches/0001-align-overlap-buffers.patch` and
  `patches/0002-guard-null-pure-translation.patch` are differences between this
  tree's `src/` and the pinned upstream tag, applied to the sources compiled
  here; a system library is built from whatever is installed, and carries those
  two fixes only if that installation was built from a tree that has them. The
  header, the library and the behaviour of a `-fsys=spglib` build are therefore
  the installed ones, not the pinned 2.7.0 this package names. That mode is
  refused with `-Druntime=true`, and the build stops with one message saying so.

  `.force` is what keeps the route honest in both directions: the package has no
  published URL and no content hash, so only a `.path` dependency resolves, and
  the query itself stops the build when pkg-config fails rather than falling
  back to a `-l` stem that no installation produces
  (`lib/std/Build/Step/TranslateC.zig:257-268` is where `.yes` would have made
  that fallback).

  `zig build consumer` forwards `-fsys=spglib` into the nested build when the
  outer build selected it and `-fno-sys=spglib` when it did not, and
  `zig/consumer/` reads it with `b.systemIntegrationOption`. It then does not
  resolve `dep.artifact("spglib")`, because the dependency builds no artifact in
  that mode and asking for one panics.
  No exit 0 is expected from a host with no installed spglib, and none
  is claimed here: the translation step asks pkg-config for `spglib` with
  `.force`, so the build stops there rather than silently translating without a
  header, and the `spglib` link behind it has nothing to resolve either. That is
  the recorded boundary of this route, not a defect in it.
* Windows is analysed through `x86_64-windows-gnu`, which is MinGW and not
  MSVC; it is the only Windows target `zig build check-targets` compiles.
  Upstream's `SPG_API` has an `_MSC_VER` branch
  (`include/spglib.h:12-27`), and an in-tree `build.zig` defines
  `SPG_STATIC_LIBRARY` for the core and for the translation step whenever the
  linkage is static, so a static archive is never declared `dllimport`. That
  arrangement is source-confirmed against the header at this pin: no MSVC
  configuration is built, checked or gated by this package, so nothing here
  claims MSVC support, and nothing here reports an MSVC failure either.
* The same facade serves both delivery modes. When the build routes the native
  entry points through a run-time table, `@import("spglib")` keeps its shape and
  only the callee changes; `runtime/graph.zig` owns that generated dispatch and
  `build.zig`'s single `translate.createModule()` call is the seam. `README.md`
  has the loading contract and what a provider must satisfy.
* The upstream Fortran, Python and Ruby bindings are not part of this package.