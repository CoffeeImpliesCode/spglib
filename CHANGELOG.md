# Changelog

Numbered entries for this fork only. Upstream release notes live in
`ChangeLog.md`, which is upstream content and is not edited here.

Each entry states what the fork changed relative to upstream `v2.7.0`
(`12355c77fb7c505a55f52cae36341d73b781a065`), why, and what a consumer can
observe.

## 1. Zig 0.16 build replaces CMake for the C core

`build.zig` compiles all 23 upstream core translation units from `src/` with
Zig's C frontend. No CMake, autotools, Make or downloaded upstream copy is
invoked, and no system-installed spglib is used by default. The source list is
written out explicitly rather than globbed, so a new upstream translation unit
cannot enter the archive without a deliberate edit.

Language level and visibility match upstream's own settings: `-std=c11`,
`-fvisibility=hidden`, `SPGINFO` and `SPGWARNING` defined, `SPGDEBUG` in Debug
builds. The library links libc and, on glibc and BSD targets, `libm`.

## 2. Generated version header without CMake

`src/version.h.in` is configured into `version.h` by `build.zig` from
`build.zig.zon`'s `.version` and the pinned upstream commit, producing
`SPGLIB_MAJOR_VERSION`, `SPGLIB_MINOR_VERSION`, `SPGLIB_MICRO_VERSION`,
`SPGLIB_VERSION`, `SPGLIB_VERSION_FULL` and `SPGLIB_COMMIT` with the same macro
names the template declares. `build.zig` panics at configure time when the
manifest version stops matching the pinned release, so the header cannot claim a
release the repository does not contain.

## 3. Exported Zig module and C artifact

The package exports module `spglib` (root `zig/root.zig`) and a compiled
artifact named `spglib`, built with `b.addLibrary` and installed with
`b.installArtifact`, so `dep.module("spglib")` is enough for a consumer and
`dep.artifact("spglib")` is available for code that compiles its own C against
the public header. Installed headers are `spglib.h` and `spglib/version.h`;
marking them with `installHeader` also puts them on the include path of every
compilation that links the artifact.

## 4. Complete translated C API plus a typed facade

`pub const c` is `addTranslateC` over an aggregate header that includes
`include/spglib.h` and the generated `version.h`, so every upstream declaration
is translated, including the k-point mesh routines the facade does not wrap.

The facade adds only what a caller needs for cell symmetry work: `getDataset`
(plus the Hall-number and angle-tolerance variants), `getMagneticDataset` and
`getMagneticDatasetWithTensors`, `getSymmetry`, `getSymmetryFromDatabase`,
`getPointGroup`, `getSpacegroupType`, `getMagneticSpacegroupType`,
`standardizeCell`, `findPrimitive`, `refineCell`, `niggliReduce`,
`gridPointFromAddress`, `getVersion`, `lastErrorCode`, `lastError`,
`errorMessage` and `toError`. It reimplements no upstream algorithm.

Observable consequences for a consumer:

* `Dataset` and `MagneticDataset` own memory that upstream allocated with
  `malloc`; `deinit` calls `spg_free_dataset` or `spg_free_magnetic_dataset`.
  No process-global allocator hook is installed.
* `OwnedCell` and `Symmetry` own Zig allocations and free them with the
  allocator passed in. Borrowed slices never outlive their owner.
* spglib's status codes become Zig errors with the same meaning; a call that
  fails without recording a specific code becomes `error.None` rather than a
  silent success.
* Caller mistakes the C API cannot express become explicit `InputError` values:
  empty cells, mismatched atom or tensor counts, counts outside the `int`
  parameters, non-positive `symprec`, out-of-range grid addresses, out-of-range
  Hall and UNI numbers, and tensor ranks above 1.
* The lattice layout is the upstream one, `lattice[column][component]`, so a, b
  and c are its columns; it is documented rather than silently transposed.

## 5. System-library mode translates the installed header

`b.systemIntegrationOption("spglib", .{})` links an installed spglib instead of
building the vendored one; the flag that selects it is `-fsys=spglib`, which
the build runner parses, not a `-D` option. In that mode the aggregate header
includes `<spglib.h>` and no include path is added, so the translation sees the
header that sits next to the library being linked; linking this repository's
2.7.0 declarations against an older installed library would silently bind the
wrong ABI. The bare name is the one upstream installs: `include/CMakeLists.txt`
attaches `spglib.h` to a `FILE_SET HEADERS` whose `INSTALL_INTERFACE` is
`${CMAKE_INSTALL_INCLUDEDIR}` with no `BASE_DIRS` override, `cmake/spglib.pc.in`
declares `Cflags: -I@CMAKE_INSTALL_FULL_INCLUDEDIR@`, `.distro/spglib.spec`
packages `%{_includedir}/spglib.h`, and `ruby/extconf.rb` probes for the bare
`spglib.h`. The link name is `symspg`, the name upstream's own build and
`spglib.pc` use. In this mode no artifact is produced, so `dep.artifact`
resolves to nothing.

## 6. Tests, example and consumer

`zig build test` runs three native test binaries: behaviour tests over the
facade, tests over the raw C surface (k-point meshes, deprecated compatibility
entry points, the magnetic database) and a file that touches the remaining
public accessors so the cross-target check compiles all of them. Fixtures are
either International Tables answers or upstream `test/functional/c` inputs
(see `zig/tests/fixtures.zig`).

`zig build smoke` runs `zig/examples/smoke.zig`, which prints deterministic
semantic output and fails loudly if a number changes. `zig/consumer/` is a
separate package that depends on this one by path and runs with
`zig build run`. It exercises both halves of the export: the typed facade on a
cubic perovskite, and one direct call into the translated C API
(`spg_get_spacegroup_type` for Hall number 460, space group 167) whose answer is
fixed by the database upstream ships. Neither answer is compared against the
other, so the check says something about the library rather than about two
wrappers of one struct.

## 7. Fork CI, and removal of the upstream workflow set

`.github/workflows/zig-fork-ci.yaml` runs the licence and provenance gate, the
native build with tests in Debug and ReleaseSafe, the smoke example, the
compile-only analysis, the six-target compile check and the downstream consumer
package. It is self-contained: it calls no reusable workflow in this directory.

The seven upstream workflows that shipped in this repository are removed:
`ci.yaml`, `release.yaml`, `step_build-wheel.yaml`, `step_coverage.yaml`,
`step_pre-commit.yaml`, `step_test-docs.yaml` and `step_test.yaml`. They are
copied upstream CI for the upstream project's own infrastructure and are not a
verification entry point for this fork, and two of them publish this fork's
builds to a service this fork does not own: `release.yaml` triggers on
upstream-shaped release tags, builds Python wheels, publishes them to
`https://pypi.org/project/spglib/` with `id-token: write`, and cuts a GitHub
release, while `step_coverage.yaml` uploads coverage to the upstream Codecov
project. `ci.yaml` calls the reusable steps, so the set only makes sense as a
whole. Keeping them would mean carrying another maintainer's publication
pipeline unchanged, which is exactly what this fork must not do.

Upstream history and upstream source are untouched by this: the removed files
remain in the upstream repository and in the imported history, and no C source,
table, test or build input changed with them.

## 8. Ignore rules and the provenance gate

`.gitignore` keeps every upstream entry and appends `.zig-cache/`, `zig-cache/`
and `zig-out/`, so an ordinary `zig build` in a consumer checkout cannot leak
build output into the source tree. Neither directory appears in
`build.zig.zon`'s `.paths`, so a fetched package never carries them either.

`tools/check_provenance.sh` is the licence and provenance gate the fork CI runs:
it checks that `COPYING` still carries the BSD 3-Clause text, that every
upstream C file still carries its SPDX identifier (`src/base.h` is the single
recorded exception, which upstream omits), that `src/`, `include/` and
`database/` are byte-identical to the pinned commit, and that `UPSTREAM.md`,
`build.zig` and `build.zig.zon` name the same release and commit.

## 9. Corrections after source review

The first implementation gate was red before anything was compiled, so this
entry records what source review changed. Every item below is
SOURCE-CONFIRMED against the pinned upstream sources and is
PENDING-VERIFICATION: the correction is in the source and no gate has observed
it yet.

* **Manifest fingerprint.** `build.zig.zon` carried a fingerprint the toolchain
  rejects; it is now the value the compiler reported,
  `0x35191367c8f3aeca` for the package name `spglib`.
* **`errorMessage` returns an optional.** `spg_get_error_message`
  (`src/spglib.c:214-228`) breaks on the `{SPGERR_NONE, ""}` sentinel at index 9
  before it compares its argument, so it returns NULL for `SPGERR_NONE` and for
  any code outside the table. `SPGERR_NONE` is a recorded code: a magnetic
  dataset that cannot be assembled sets it (`src/spglib.c:1247-1252`). The
  facade now returns `?[]const u8` instead of dereferencing that pointer.
* **Site-tensor cardinality is 1 or 3 per atom, not `(rank + 1)^3`.** Upstream
  allocates `num_atoms` doubles at rank 0 and `num_atoms * 3` at rank 1
  (`src/cell.c:67-79`, `src/spin.c:279-293`, `src/cell.h:31-32`) and copies
  them as `tensors[i * 3 + s]` (`src/spglib.c:1635-1641`). The old formula
  returned 8 at rank 1, which both rejected a search upstream accepts and, for
  a caller who followed the documentation, handed C an 8-per-atom slice over a
  3-per-atom allocation.
* **Tensor ranks above 1 are rejected before the C call.** `SiteTensorType` has
  only `NOSPIN`, `COLLINEAR` and `NONCOLLINEAR` (`src/cell.h:10-14`),
  `cel_alloc_cell` allocates tensor storage for nothing else, and
  `spn_alloc_site_tensors` returns NULL above rank 1. Such a search could only
  reach an uninitialised `cell->tensors`, so it is now
  `error.TensorRankOutOfRange`.
* **The lattice is a column basis.** `include/spglib.h:56-60` documents
  `[[a_x, b_x, c_x], [a_y, b_y, c_y], [a_z, b_z, c_z]]`, `spg_get_spacegroup_type_from_symmetry`
  calls it "Basis vectors given as column vectors", and
  `rot_cart = lattice @ rot @ lattice^-1` (`src/spin.c:322-325`) is only a
  Cartesian rotation when the columns are a, b and c. `Cell.length`,
  `Cell.toCartesian` and the two test helpers read the transposed matrix, which
  a diagonal fixture cannot detect; all four now read columns, and
  `Cell.column` and `Cell.angle` make the reading explicit.
* **The system-mode aggregate includes `<spglib.h>`.** See entry 5: upstream
  installs the header flat.
* **`getSpacegroupType` and `getMagneticSpacegroupType` are fallible.** Both C
  entry points record `SPGERR_SPACEGROUP_SEARCH_FAILED` and return a zeroed
  struct for a number outside 1..530 and 1..1651
  (`src/spglib.c:751-792`, `2287-2326`). They now return
  `error.HallNumberOutOfRange` and `error.UniNumberOutOfRange` instead of a
  struct that looked like a successful answer with empty strings. Every caller,
  including the consumer package, was migrated to `try`.
* **The recorded status is documented as thread-local and cleared by success.**
  `spglib_error_code` is `static thread_local` (`src/spglib.c:50`) and every
  successful entry point overwrites it, the six behind `getVersion` included
  (`src/spglib.c:176-204`).
* **`allocateCell` no longer promises headroom it does not allocate.** The
  caller chooses the capacity; the standardisation, primitive and refinement
  paths all need four times the input atom count, and only `spg_refine_cell`
  says so in the header (`include/spglib.h:463-471`).
* **Fixtures that can fail.** Every lattice in the suite was diagonal or, for
  the two Niggli cells, only checked through a determinant, which is
  transpose-invariant; the whole suite therefore passed with a transposed
  basis. The upstream 30-atom hexagonal corundum cell
  (`test/functional/c/test_standardization.cpp:29-64`) is now a fixture: it
  gives a = b = 4.8076344022756095 with gamma = 120 and c = 13.1172699198127543
  under the column reading, space group 167 (R-3c) and 10 primitive atoms,
  which upstream pins in `test_find_primitive_cell.cpp:74`. The upstream
  non-collinear magnetic cell (`test_magnetic_dataset.cpp:214-231`) joins it as
  the rank-1 fixture.
* **Ten accessors that `check` never instantiated** are now exercised with
  independent oracles: the Hall 419 space-group type against upstream's own
  Fortran functional test, the Hall 529 arithmetic class against
  `src/arithmetic.c`, the OG and Litvin numbers against
  `database/msg/msg_numbers.csv`, and the magnetic standard cell against the
  input cell's geometry.
* **Test expectations that the library cannot produce.** `international` is the
  32-character spaced form, not the short symbol, and `schoenflies` carries its
  superscript, so `"P4_2/mnm"`, `"Im-3m"` and `"Oh"` were wrong reads of
  `international` and `schoenflies` for Hall 419 and Hall 529. The smoke
  example and the facade test also disagreed about the primitive atom count of
  the distorted bcc cell, which reduces from 2 atoms to 1 in both
  `FORK-NOTES.md` and upstream. All of these are corrected. A wording table
  that copied the upstream message strings was deleted rather than repinned.
* **The facade unwrapped pointers the translation does not make optional.**
  `addTranslateC` on this toolchain emits `[*c]T` for every non-opaque C
  pointer, so `c.spg_get_dataset(...) orelse ...` and `dataset.raw.rotations.?`
  are not valid expressions. `zig/ffi.zig` now owns that one shape assumption:
  `isNull`, `borrow`, `single` and `spanOrNull`, each accepting either the
  `[*c]` or the optional spelling, exactly as `error.zig` already does for the
  translated `SpglibError` enum.
* **The cross matrix named a field that does not exist, and the root manifest
  depended on its own consumer.** `build.zig` resolved each target triple with
  `Target.Query{ .cpu_arch_os_abi = triple }`. A triple string is not a `Query`
  value: `Query` holds `cpu_arch`, `os_tag`, `abi` and friends
  (`lib/std/Target/Query.zig:15-54`), and the string is an input to
  `Query.ParseOptions`, whose `arch_os_abi` field is at Query.zig:165. Each
  triple now goes through `std.Build.parseTargetQuery` (Build.zig:1423), the
  entry point `standardTargetOptionsQueryOnly` itself uses, so the matrix and
  `-Dtarget=` agree. `build.zig.zon` listed `zig/consumer` as a dependency while
  that package's own manifest depends on this one by path, which is a cycle and
  would also have constrained every other step. The dependency is gone;
  `zig build consumer` runs `zig build run` (native) or `zig build install`
  (foreign) in `zig/consumer` through the pinned compiler, forwarding
  `-Dtarget=`, `-Dcpu=` and `-Doptimize=` as single arguments and, when the
  outer build has an explicit cache directory, `--cache-dir` followed by
  `<outer>/consumer` as two arguments.
* **The shared pointer helper had no return type.** The integration owner
  reported the gate stopping at `zig/ffi.zig:32`: `anytype` is a parameter
  placeholder, not a result type, so a helper that returns either the pointer or
  its optional's child has to name both. `unwrap` now spells that choice in its
  return type, resolved at compile time, which is the same defence `error.zig`
  already applies to the translated enum. No second compatibility layer was
  added for it.

## 10. Documentation reconciled with the toolchain and the source

The five records this fork owns were checked against the pinned upstream
sources, the pinned compiler's own `lib/std` and `lib/compiler`, and the
current `zig/` facade. Three defects were documentation-only and invisible to
every command in the gate list, because no gate reads prose:

* **The system-integration flag was wrong.** `README.zig.md` and this file's
  entry 5 told a reader to pass `-Dsystem-spglib`. `b.systemIntegrationOption`
  does not call `b.option`, so it never enters the `-D` map
  (`lib/std/Build.zig:1141-1167`); the build runner fills its own map and spells
  the flag `-fsys=spglib` and `-fno-sys=spglib`
  (`lib/compiler/build_runner.zig:169-174`), with `--system` setting the
  default. Both files now name the flag the runner parses.
* **The replacement for the placeholder URL was also unusable.** `zig fetch`
  is not a command in this compiler: the build runner's package-management
  options are `--fetch[=mode]` and `--fork=[path]`
  (`build_runner.zig:1662-1666`). The dependency section now documents the form
  this repository's own consumer package uses, a `.path` dependency written
  into `.dependencies`, and states that no published URL or hash is confirmed.
* **A comment named a flag the runner does not parse.** `build.zig`'s own
  comments described system-library mode as `-Dsystem-spglib`. Its comments
  now say `-fsys=spglib`, the spelling
  `lib/compiler/build_runner.zig:1579` and `:169-174` use. `FORK-NOTES.md` entry
  24 records the rule.

The rest of the reconciliation makes prose match the code rather than restate
it: the site-tensor cardinality is stated as upstream's one-double-per-atom at
rank 0 and three at rank 1 with the exact-length rule, the lattice is described
as the column basis `include/spglib.h:56-60` documents, the ownership section
names the four-times-atom-count headroom the standardisation paths need and the
fact that `allocateCell` adds none, the error section keeps the thread-local
and cleared-by-success lifetime of the recorded status, and every status word
in `FORK-NOTES.md` is now the PENDING-VERIFICATION the workspace defines rather
than an informal one. No result of any gate is claimed; `README.zig.md`, this
entry and `FORK-NOTES.md` say so where a reader would otherwise look for one.

## 11. Three build-script API shapes that do not exist, and two gaps in the facade's own surface

The integration owner observed `zig build` stop three times inside this
package's build script. All three are compile-time shape errors rather than
wrong answers, and each was found by reading the pinned compiler's own
`lib/std` rather than by a probe:

* `build.zig` took `.step` off the result of `analyze`, but `analyze` declares
  `*std.Build.Step` as its return type and `Build.Step` has no `step` field.
  The pointer is now passed to `dependOn` directly. `check-targets` already did
  that, which is why only `check` was affected.
* `build.zig` called `translate_c.addCMacro`. `Module` has `addCMacro`;
  `Step.TranslateC` does not, it has `defineCMacro(name, value)` and
  `defineCMacroRaw` (`lib/std/Build/Step/TranslateC.zig:153-161`). The
  translation now uses `defineCMacro`, so `SPG_STATIC_LIBRARY=1` still reaches
  the aggregate header for the static-linkage case.
* The generated `version.h` formatted `package_version`, a
  `std.SemanticVersion`, with `{s}`. `Io/Writer.zig:1152-1168` accepts only
  pointer and array types for `{s}` and rejects everything else through
  `invalidFmtError` (`:1801-1803`). `{f}` is the specifier that calls a value's
  own `format` method (`Io/Writer.zig:1077`,
  `std/SemanticVersion.zig:153-157`), so `SPGLIB_VERSION` and
  `SPGLIB_VERSION_FULL` are written with it.
* A fourth shape error was found by reading rather than by a gate, because the
  standard gate list never runs system-library mode: `Module.linkSystemLibrary`
  calls `requireKnownTarget` (`lib/std/Build/Module.zig:370`, `:661-665`), which
  panics for a module created with only a root source file. The exported
  `spglib` module now carries the target and optimize mode of the build that
  created it, so `-fsys=spglib` configures instead of aborting.

Two gaps in the public surface were closed in the same pass:

* `allocateCell` was a public function of `zig/cell.zig` that `zig/root.zig`
  never exported, so the caller-supplied headroom contract `README.zig.md`
  documents was unreachable from a dependent package. It is exported now, and
  `zig/tests/api_surface.zig` drives it against `spgat_standardize_cell` on
  upstream's distorted bcc cell, which is the call the four-times-atom-count
  rule exists for.
* The two ends of each fallible type lookup were asserted only to not throw.
  They now carry the answers `src/spg_database.c` records for Hall 1 (P1) and
  Hall 530 (Ia-3d) and `database/msg/msg_numbers.csv` records for UNI 1
  (BNS 1.1, OG 1.1.1) and UNI 1651 (BNS 230.149, OG 230.5.1651).

Two tests were deleted rather than repaired: one compared `Symmetry`'s own
slices with the ones `operations` hands back, and one was a bare
`try cell.validate(...)`. Neither could fail while the code was correct.

`tools/check_provenance.sh` has observed the licence, SPDX and source records
against this pin. Nothing else in this section has been observed.

## 12. `spgms_get_magnetic_dataset` crashed on a NULL free

**Evidence.** `get_primitive` frees `pure_trans` on every attempt
(`src/primitive.c:246`), including the attempt where
`sym_get_pure_translation` returned NULL at `:239`. `mat_free_VecDBL`
dereferences its argument (`src/mathfunc.c:402`), so that attempt is a null
dereference. Observed: a call to `spgms_get_magnetic_dataset` for the test
cell with collinear spins aborted inside `mat_free_VecDBL`, through
`spglib.c:262`, `:1215`, `:1742`, `:1049`, `determination.c:41`, `:107` and
`primitive.c:104`.

**Cause.** The guarded free is the idiom the same file uses at
`src/primitive.c:399-404` and `:416-418`; this one call site simply missed it.

**Fix.** `patches/0002-guard-null-pure-translation.patch`, applied to
`src/primitive.c` and recorded in `tools/check_provenance.sh`. The call now
frees only a non-NULL pointer, which is what every other call site in the tree
already did. No return value, tolerance schedule or numerical result changes,
and on every path where the pointer was non-NULL the same block is freed.

**Rule.** A public entry point that crashes on a legal call is a defect in the
vendored C, not in the binding, and a test that exercises it is the evidence.
Guard the crash, keep the test, and record the guard as a patch the provenance
gate replays, so the difference stays visible instead of becoming drift.

## 13. The Zig caller is not built at `-O Debug`

**What was observed.** `zig build test` failed 13 tests in Debug and none of the
corresponding ReleaseSafe failures involved a library defect. Every failing call
is an spglib entry point with more than six integer-class arguments, and every
call that worked has six or fewer.

**Cause.** A Zig 0.16.0 defect at the `extern "C"` call boundary, not in spglib
and not in this binding. When such a call spills an argument onto the stack, the
same call's floating-point arguments are placed in xmm6 and xmm7 while the callee
reads xmm0 and xmm1. Only the doubles are wrong; spilled integers arrive
correctly. A C caller compiled with `zig cc -O1` against the same archive
returns `136`/`P4_2/mnm`, `16` operations, `40` at `8^3`, `4200` at `40^3` and
`msg_type = 3`, in both modes.

**Fix.** `zigCallerOptimize` compiles the Zig caller at `ReleaseSafe` when the
requested mode is `Debug`, for the test artifacts, the example and both branches
of the facade module, and `runConsumer` forwards the same value because the
nested consumer build configures this package as a dependency. C sanitization is
turned off on the core module so an instrumented archive can link into a
non-instrumented program. The C library keeps the requested optimisation and the
`-DSPGDEBUG` the Debug flags carry, so the Debug gate still exercises the debug
build of the C.

**What was not done.** No signature was rewritten, no wrapper was changed to
work around it, and no oracle was weakened. `FORK-NOTES.md` entry 30 has the
reproducer, which is five fixed-arity C functions and no spglib at all, and the
disassembly of the miscompiled call.

**Boundary.** Observed on x86-64 linux-gnu with Zig 0.16.0. No other
architecture or toolchain version was tested.
