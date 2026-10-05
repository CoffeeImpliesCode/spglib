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
  parameters, non-positive `symprec`, grid addresses and mesh entries whose
  doubled-mesh `int` arithmetic would overflow (`src/kgrid.c:39` doubles an
  address, `src/kgrid.c:125` doubles a mesh entry), out-of-range Hall and UNI
  numbers, and tensor ranks above 1. A grid address is not bound by its mesh:
  `src/kgrid.c` folds an address outside the mesh onto the point it names — in a
  2×2×2 mesh, `{3,0,0}`, `{1,0,0}` and `{5,0,0}` are all index 1 — and only a
  component above `2^30-1` is refused. Corrected 2026-10-04; the error names
  `MeshOutOfRange` and `GridAddressOutOfRange` did not change, and
  `zig/error.zig` is where their meaning is written down.
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
`spglib.h`. The link name is `spglib`, asked for through pkg-config with
`.force`, because `symspg` is upstream's own CMake file name
(`CMakeLists.txt:108-113`, `cmake/spglib.pc.in:4`) and is not a stem this
package installs or links. In this mode no artifact is produced, so
`dep.artifact` resolves to nothing.

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
* **The replacement for the placeholder URL was also unusable.** This entry
  recorded `zig fetch` as a command this compiler does not have, read out of the
  build runner's option list; `FORK-NOTES.md` entry 25 said the same.
  `zig fetch` does exist — the compiler's own usage text shows
  `zig fetch --save <url>` — and the correction is dated 2026-10-04 in entry 17.
  What remains true is the conclusion rather than the reason: the dependency
  section documents the form this repository's own consumer package uses, a
  `.path` dependency written into `.dependencies`, and states that no published
  URL or hash is confirmed, because this package has neither to fetch from.
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

## 14. Zig API contract alignment — 2026-10-03

**Condition.** Dataset views borrow native allocations; database result
records copy values, while Version strings point to static library storage.
Magnetic time reversal is 0/1, not the separate spin-flip +/-1 convention.

**Fix.** Document native versus stored-Zig allocator ownership, raw fields,
copies and invalidation at their declarations. Correct magnetic flags, rank
clamping, UNI naming, Hall sentinels, positive tolerance, standardization
capacity and deprecated-route guidance. Complete the module example and
remove false omitted-surface claims. Bound compiler observations to the
observed toolchain/ABI without asserting an unestablished register mechanism.

**Verification and bound.** Zig 0.16.0, native Linux x86-64: install,
Debug/ReleaseSafe requested tests, smoke, package consumer and module example
pass; the existing Debug workaround builds the Zig caller in ReleaseSafe and
the C core in Debug. Compile-only `check-targets` passes. System-provider and
foreign runtime results are not supplied here. Native bytes are unchanged.

## 15. Canonical README, owner-authorized fork licence, and standalone packaging — 2026-10-04

**README relocation.** Upstream's README is preserved byte for byte at
`README.upstream.md` (sha256
`294f6f53da4a096e17ab104f3cc8e2c385f2cbe98e4164ff6c94b717beea9ccc`), and
`README.md` is now this fork's own document. Its order is fixed: current
native-source deviations against the exact pin, current native-build deviations
with a link to the dated history in this file, the current build/run/test matrix
with each row's evidence status, and consumption. The Zig interface stays in
`README.zig.md`, which now points at `README.upstream.md` instead of the path
that moved, and points at `README.md` for everything else. Nothing upstream
wrote was edited to make room: the upstream prose is in the preserved file, and
`tools/check_provenance.sh` now proves that the two files are what they claim
to be rather than trusting their names.

**Licence.** `FORK-LICENSE.md` records the repository owner's direct
authorization, dated 2026-10-04, for a licence covering the files this fork
authored: BSD 3-Clause, matching the primary upstream terms, with
`BSD-3-Clause` as the SPDX identifier for a newly authored source or build
file. It asserts no individual copyright holder, and it credits nothing to
upstream's authors. `README.upstream.md` is upstream content and is explicitly
outside that grant. `NOTICE.md` gains a "Fork-authored files" section with the
inventory and the two paths that need their own sentence.

**Native delivery.** `build.zig` gained the second delivered variant,
`-Dlinkage=dynamic`, with the static default unchanged, and a complete
installed closure in both variants: the library, `include/spglib.h`, the
generated `include/spglib/version.h`, a relocatable `lib/pkgconfig/spglib.pc`,
and `share/licenses/spglib/{COPYING,NOTICE.md,FORK-LICENSE.md,UPSTREAM.md}`.
No data and no tools are installed, because the crystallographic tables are
compiled into the three `*_database.c` translation units and upstream installs
no tools either. `libm` and `-DSPG_STATIC_LIBRARY` appear in the installed
metadata on exactly the targets that need them, from the same decision the
library link makes. This part is the build owner's work; it is recorded here
because this file is the fork's single record of what differs from upstream.

**Packaging.** `package.nix` is one ordinary function taking `lib`, `stdenv`,
`zig` and an optional `linkage`, returning one derivation; the variant comes
from the caller. Its only build command is `zig build install` with one
optimization selection, `-Dcpu=baseline`, `-j${NIX_BUILD_CORES}` and both Zig
caches under the sandbox `TMPDIR`, and no C flag is restated. Its post-install
phase verifies the installed layout instead of writing a second copy of it.
`flake.nix` exposes `packages.<system>.static` and `.shared` over that one
definition, with `default` keeping the SDK's native static default.
`devenv.nix` keeps the SDK out of `packages` — Zig 0.16.0, `patch`, `git`, an
assertion that refuses any other Zig, and one namespaced task per build step —
and exposes the same two derivations as lazy `outputs.static` and
`outputs.shared`, so entering the shell never builds the library.
`devenv.yaml` and `.envrc` make devenv the canonical development environment.
There is no `../` import, no sibling dependency, no host path and no build-time
download anywhere in them. `flake.lock` now exists and pins the nixpkgs input
`flake.nix` names, by revision and resolved hash; there is no `devenv.lock`, and
`devenv.yaml` pins its own input by revision instead — corrected 2026-10-04, see
entry 17.

**What was not done.** No upstream source, public header, table, data file,
upstream test or licence byte changed. No default changed. No native-source
deviation was added by this wave. Nothing was published and nothing was
committed.

Runtime loading is part of the same wave and is open work, not a limitation.
`-Druntime` is a boolean build option, default false, orthogonal to `-Dlinkage`;
all four combinations are legal and each still delivers an artifact, with
identical headers and licence material and the same `spglib.pc` apart from the
two lines the linkage decides. Under the switch,
`runtime/graph.zig`'s `createModule` replaces the single
`translate.createModule()` call in `addSpglib`, and the generated dispatch it
runs through the shared generator — built from the real translation output for
the target being built — re-exports the translated namespace, so the facade a
consumer imports is unchanged. The facade gains `load(LoadSource) LoadError!void`,
`loadedSource()` and `runtime_loaded`; `LoadSource` is `{ path, system }` with no
fallback. A provider must export the whole 59-function declared surface except
the two declarations upstream never defines; those two are routed as optional
rather than left as direct `extern` references, so their absence never fails a
load and the first call to one panics by name — corrected 2026-10-04, see entry
17. `-fsys=spglib` is refused with `-Druntime=true`, because the installed
header carries no version macros for the dispatch to validate against.
`runtime/generate.zig`, the generator the dispatch is built from, is in the
tree, so a runtime build does configure — corrected 2026-10-04, see entry 17.
`README.md` carries the interface and the four ABI requirements.

**Verification status.** PENDING-VERIFICATION, all of it, as this entry stood
when it was written. Gates have since observed the dynamic variant, the runtime
route against this SDK's own provider, and the two `x86_64-linux` Nix
derivations — each against the source as it stood when it ran. `README.md`'s
matrix is the current record and entry 17 carries the corrections that go with
it; no row in either is a result for a tree other than the one it names.

## 16. A machine-checkable record of every carried upstream byte — 2026-10-04

**Condition.** The provenance gate checked `src/`, `include/` and `database/`
against the pin, replayed two patches, and compared `README.upstream.md` with
upstream's README. It saw none of the rest of what this repository carries:
upstream's whole `test/` suite and its 502 functional fixtures, the data tables
and the Python generators that produce `src/spg_database.c`, the Fortran, Python
and Ruby bindings, the packaging tests, `docs/`, `cmake/`, `.distro/`, the
remaining `.github/` config, `ChangeLog.md`, `CITATION.cff`, `Contributing.md`,
the root editor and CI dotfiles and `COPYING`. A changed byte in any of those
was invisible to the gate, and a future edit to one of them would have passed as
a routine change.

**Fix.** `UPSTREAM.sha256`, a new root-level record: one SHA-256 digest for
each of the 725 upstream paths this tree carries at
`12355c77fb7c505a55f52cae36341d73b781a065`, which is the pinned tree's 732
entries minus the seven uncarried upstream workflows, with upstream's `README.md`
recorded under this fork's name `README.upstream.md`. The header states the pin,
the repository, the tree id, the derivation, the path set, the counts per area
and every deliberate exclusion.

The digests come from the pinned commit's git objects and not from this working
tree. `tools/derive_upstream_sha256.py` is the derivation: it reads
`git ls-tree -r` for the path set, reads each blob with `git show`, and replays
each recorded patch onto the pinned blob to hash the forked result, so a drifted
working tree cannot be written into the record as if it were upstream. Running
it again at the same pin reproduces the committed file byte for byte.

Three records are not upstream bytes and say so in the header and beside
themselves, each carrying the pin's own digest on a `#!pin` line so a reader can
separate the fork's bytes from upstream's: `src/overlap.c` and `src/primitive.c`,
which are the pin plus `patches/0001-align-overlap-buffers.patch` and
`patches/0002-guard-null-pure-translation.patch`, and `.gitignore`, which keeps
upstream's 809 bytes verbatim and appends this fork's own entries below a
`# Fork additions below` marker. The patches remain the patches: the record
names the resulting state and the gate still replays both patches from the pin
and compares the result byte for byte. The six symlinks upstream carries are
recorded as `#!link` lines holding the digest of their link text, because
`sha256sum -c` would follow the link and four of the six point at a directory.

**Gate.** `tools/check_provenance.sh` gained a sixth question: it runs the
record, re-derives the three fork-state digests from the pin, compares the six
symlinks against both the pin and the tree, and checks the path set in both
directions, so neither a dropped upstream file nor a stray file added inside a
carried upstream area passes unnoticed. The seven uncarried workflows keep their
digests in the header so the omission stays auditable.

**Divergences found, not fixed.** Every carried path matches the pin except the
three named above. Nothing else in the 725 paths differs in content or in file
mode. The seven uncarried workflows are absent by the decision in entry 7.

**Verification status.** OBSERVED on 2026-10-04. The gate reported 719 records
and 6 symlinks agreeing on the pin; the derivation script reproduced the
committed record byte for byte; and eleven deliberate tamperings were each
rejected while the restored tree passed: an appended data table, an edited YAML
fixture, a deleted docs page, a retargeted symlink, an extra edit to a patched
source, a stray file added to `database/` and to `.github/`, an altered Fortran
binding, an altered RPM spec, an altered public header, an appended `COPYING`, a
doctored `#!pin` digest and a truncated record. The record's derivation was
cross-checked against the `v2.7.0` source tarball (2442495 bytes, sha256
`b22fc9abae9716c574fbc6d55cfc53ed654a714fccc5657a26ff5d18114bd8bd`), which
matched the clone's blob contents for all 732 entries except `.git_archival.txt`,
where upstream's `export-subst` attribute explains the difference. No CI run is
observed, and no build, test or smoke run is claimed by this entry.

## 17. A delivered generator reported as missing, and an optional route reported as a link error — 2026-10-04

**Condition.** Documentation written while the runtime generator was still
being landed, read again against a tree that has it.

**What was wrong, against the source.**

* The readiness record said `runtime/generate.zig` was not in the tree, named
  `runtime/graph.zig:228` as the line that builds it, and concluded that a
  runtime build cannot configure yet. The generator is in the tree, and
  `runtime/graph.zig`'s `generateDispatch` builds it as a host program for the
  target being built and runs it over that target's own translation output.
  Both this file and `README.md` had kept a statement about a file that had
  landed.
* `provider_optional` was documented in three places as keeping
  `spg_get_grid_points_by_rotations` and `spg_get_BZ_grid_points_by_rotations`
  as direct `extern` references whose absence is a link error.
  `runtime/generate.zig`'s `Options.routeOf` routes every `--optional` name to
  the optional route instead. The generated dispatch declares a nullable table
  field for each, initialised `null`, lists them in `optional_symbols` rather
  than in `symbols`, and emits
  `table.<name> orelse requireAvailable("<name>", "<name>")` in the wrapper,
  where `requireAvailable` is a `std.debug.panic` naming the library, the symbol
  the provider lacks and the fact that this provider is not the library the
  build describes. A provider that does not export them still loads; the first
  call stops the program by name. The linked half of the old sentence was true
  and is kept: with no dispatch, both names stay unreferenced `extern`
  declarations that cost the linker nothing.
* The packaging records said `flake.lock` and `devenv.lock` were both absent.
  `flake.lock` exists, pins the nixpkgs revision `flake.nix` names and is listed
  in `build.zig.zon`'s `.paths`; `devenv.lock` does not exist, `devenv.yaml`
  pins its own input by revision, and the `.paths` entry naming it was removed
  rather than the file invented.
* Entry 10 below, and `FORK-NOTES.md` entry 25, said this compiler has no
  `zig fetch` command. It does: the compiler's own usage text shows
  `zig fetch --save <url>` and `zig fetch <path-or-url>`, and a recorded
  invocation diagnosed its argument as neither an existing file path nor a URL,
  which an absent subcommand could not do. What was true all along is the
  conclusion rather than the reason: with no published URL and no content hash,
  a `.path` dependency is the only form that resolves.

**Evidence for the current state.** Sixteen gates ran both routes of this SDK on
`x86_64-linux-gnu` with Zig 0.16.0 on 2026-10-04 — eight linked
(`-Druntime=false`) and eight loaded (`-Druntime=true`), each across both
linkages and `Debug`, `ReleaseSafe`, `ReleaseFast` and `ReleaseSmall` — all
exiting 0 on `zig build test smoke install`, 55 of 55 tests in each, the loaded
run opening this SDK's own `-Dlinkage=dynamic` install, and each loaded build
summary listing the generator as a real step. `README.md`'s matrix carries the
commands, the receipts and the boundary: those runs describe the source as it
stood while they ran; `build.zig`, `build.zig.zon`, `package.nix`,
`runtime/graph.zig` and `zig/consumer/build.zig` have been edited since, so a
replay against the frozen handoff is owed, and a replay that fails replaces
those rows rather than adding to them.

**What was not done.** No native source, public header, table, upstream test or
licence byte changed, no default changed, no URL or hash was invented, and
nothing was published or committed. A correction that lands is not a result:
the installed-C proof, a foreign target, a host with an installed spglib, the
three Nix systems other than `x86_64-linux` and the fork's own CI workflow
remain PENDING-VERIFICATION.

## 18. A derivation that could not evaluate, and tasks that ran in the caller's directory — 2026-10-04

**Condition.** An 18-SDK acceptance run on 2026-10-04 evaluated this SDK's two
Nix variants and its devenv gates with
`devenv --from path:<this repository>` from a scratch project directory, so
every one of those commands started outside this checkout.

**What was wrong, against the source.**

* `package.nix` asked `stdenv.hostPlatform.linuxLibc` whether the host is musl,
  to pick the ABI component of the `-Dtarget` triple it derives. The pinned
  nixpkgs revision `c7def046b9a883d46974757852106483d741586f`, which `flake.nix`
  names and `flake.lock` pins, has no such attribute: `nix build` of either
  variant failed with `error: attribute 'linuxLibc' missing` at `package.nix:100`
  while evaluating `installPhase`, so neither derivation was built. That
  revision spells the same fact `hostPlatform.isMusl`, which it derives from
  `hostPlatform.parsed.abi` (`lib/systems/default.nix:442` merges
  `lib/systems/inspect.nix`'s patterns into the elaborated platform;
  `lib/systems/inspect.nix:429-437` is the musl sum-of-products), and it is the
  attribute nixpkgs itself uses to name the platform's libc
  (`lib/systems/default.nix:186`). The comment above it described
  `platform.linuxLibc` as "the string form of the platform's libc", which named
  an attribute the pinned revision does not define.
* Every task body ran with the *caller's* working directory, because devenv
  materialises a task as a generated shell program that inherits it.
  `sdk:consumer` therefore ran `zig build consumer` where there is no
  `build.zig` (`error: no build.zig file found, in the current directory or any
  parent directories`), and `sdk:provenance` ran `./tools/check_provenance.sh`
  where there is no `tools/` (`line 3: ./tools/check_provenance.sh: No such
  file or directory`).
* `sdk:build` runs `zig build`, which is the default install step: it writes the
  library, both headers, `spglib.pc` and the licence material. Run from this
  checkout, that was a `zig-out/` inside the repository, on the filesystem
  holding it.

**What changed.** `zigAbi` reads `stdenv.hostPlatform.isMusl`, so a musl package
set builds `…-linux-musl` and every other one `…-linux-gnu`, Darwin still takes
`none`, and nothing else about the target selection moved. Every task now begins
with `cd` to this directory, named from the module itself as
`builtins.toString ./.` and quoted with `lib.escapeShellArg`: `builtins.toString`
because an interpolated `${./.}` can copy the whole tree into the read-only Nix
store, and a store copy is not a tree `zig build` may write a cache into.
`sdk:build` additionally installs into `$SPGLIB_INSTALL`, else
`$ZIG_LOCAL_CACHE_DIR/spglib/zig-out`, else `$TMPDIR/spglib/zig-out` - with no
`/tmp` default, so a caller that exported none of the three gets a named error
instead of an install somewhere it was not told to; its `--prefix` is written
before `"$@"`, and `sdk:test`, `sdk:smoke`, `sdk:check`, `sdk:check-targets`,
`sdk:consumer` and `sdk:fmt-check` install nothing and take no `--prefix`;
every build task names the same fixed `-j8` (entry 19).

**What was not done.** No native source, public header, table, upstream test,
licence byte, build-graph step or default changed; no task, script or output was
renamed or removed; `devenv.yaml`, `flake.nix`, `flake.lock` and `build.zig.zon`
are untouched. Nothing was built, evaluated or run to produce this entry: the
acceptance run above is the receipt that the two failures were real, and a fresh
`nix build` of both variants plus both devenv gates on the corrected source is
owed before any of this is called green.

## 19. Every canonical build task names its cache, its job count and its summary - 2026-10-04

**Condition.** `foundation-libs/AGENTS.md:157-159` is the recipe: a library gate
is `zig build`, `zig build test`, `zig build smoke` and `zig build check`, a
consumer gate is `zig build run`, and each names `-j8`, an explicit
`--cache-dir` under the host's approved scratch cache, and `--summary all`.
None of the three is optional in that recipe.

**What was wrong, against the source.** `devenv.nix` named a fixed `-j8` on
`sdk:build` alone (`devenv.nix:86`, before this entry). The other six build
tasks named no job count, no cache directory and no summary, so each ran on
the build runner's own defaults: the driver-routed consumer gate `sdk:consumer`
and the `sdk:test`, `sdk:smoke`, `sdk:check`, `sdk:check-targets` and
`sdk:fmt-check` gates took whatever job count the host offered and wrote
their cache wherever the default pointed. `sdk:build` named no cache
directory either, although its prefix chain already showed that the caller has
to be asked before anything is written outside this repository.

**What changed.** One let-bound shell line, `cacheSetup` (`devenv.nix:48-50`),
resolves that directory before the compiler starts, and every task body reuses
it rather than restating it: `base="${ZIG_LOCAL_CACHE_DIR:-${XDG_CACHE_HOME:-${TMPDIR:?...}}}"`,
`cache="$base/spglib/zig-cache"`, `mkdir -p "$cache"`. An exported
`ZIG_LOCAL_CACHE_DIR` is taken exactly as it stands, then `XDG_CACHE_HOME`,
then `TMPDIR`; when the caller exported none of the three the task stops and
names them, before Zig runs. `ZIG_GLOBAL_CACHE_DIR` is deliberately untouched:
an exported one keeps applying, and without one the compiler's own external
default stands. No task can fall back to this checkout's `.zig-cache`.

All seven build tasks now carry `--cache-dir "$cache" -j8 --summary all`,
written after the step name and any `--prefix` and before `"$@"`, so a
caller's own flags remain the last word and can still override the explicit
cache. `sdk:provenance` runs no build and is unchanged.

`base` is also the install base for `sdk:build`, the one task that installs:
`$SPGLIB_INSTALL` when the caller exported it, else `$base/spglib/zig-out`.
That is the three-variable chain entry 18 recorded, with `XDG_CACHE_HOME`
inserted between `ZIG_LOCAL_CACHE_DIR` and `TMPDIR` so that one resolved base
names both the cache and the delivery. There is still no `/tmp` default, no
repository default, and no named error replaced by a silent write.

**Boundary, not fixed here.** `sdk:consumer` drives a nested `zig build run`
(or `install` for a target no enabled executor can run) inside `zig/consumer`.
That nested invocation forwards `-Dtarget=`, `-Dcpu=`, `-Doptimize=`,
`-Druntime=`, `-Dlinkage=`, `-fsys=spglib` and, now that the outer build names a
cache, `--cache-dir <cache>/consumer`, so the nested build leaves this checkout,
but it forwards no job count. `-j8` therefore governs the outer graph only;
changing the nested one needs `build.zig`, which this entry does not touch.
Entry 21 closed this boundary afterwards: `runConsumer` now names `-j8` and
`--summary all` itself, and the global cache, the install prefix and the
caller's own arguments besides.

**What was not done.** No native source, header, table, test, data or licence
byte, no build-graph step, no linkage default, no task name and no output
changed; `build.zig`, `package.nix`, `flake.nix`, `devenv.yaml` and
`build.zig.zon` are untouched. Nothing was built, evaluated or run to produce
this entry: the change is read out of `devenv.nix`, and the canonical
`sdk:consumer` and `sdk:provenance` gates are owed against the edited file
before it is called green.

## 20. A const justification upstream contradicts, and an incomplete omitted-surface account - 2026-10-04

**Condition.** A wrapper that drops `const` has to name the file and line where
the C writes (`AGENTS.md` section 4), and a module that claims to account for
what its typed surface leaves out has to be complete.

**What was wrong, against the source.** `Cell.mutableTypePtr` justified dropping
the qualifier by saying the `spgat_*` family "only reads the types", across "the
eleven call sites". Upstream writes it: `set_cell` assigns
`types[i] = cell->types[i]` at `src/spglib.c:2072` and `standardize_cell` at
`src/spglib.c:1928`, both reached from the six declarations that drop `const`
(`include/spglib.h:437,442,454,458,469,473`), and the header warns of exactly
that at `include/spglib.h:450`. There are six such declarations and the facade
reaches two (`zig/dataset.zig:310,360`). `Cell.latticePtr` justified the same
drop by saying "upstream's read-only entry points take non-const pointers".
Every search entry point declares it const, `spg_get_dataset`
(`include/spglib.h:206-209`) and the layer, magnetic and symmetry searches with
it; only the six standardisation declarations drop it, and those write at
`src/spglib.c:2070` and `src/spglib.c:1926`. The module doc then claimed the
typed surface omits three things - layer groups, reciprocal-mesh construction
and magnetic operation-database lookup - which `include/spglib.h` contradicts:
26 declarations are non-deprecated and have no facade function, including
`spg_delaunay_reduce` (:480), the collinear-spin (:261,267,273) and site-tensor
(:301,308,316) searches, the symmetry-to-type searches (:341,345) and
`spgat_get_dataset_with_hall_number` (:239).

**What changed.** Prose only. `Cell.mutableTypePtr` and `Cell.latticePtr` now
name the six declarations and the source lines that write, and say plainly that
a search entry point never writes through them; the same premise at
`OwnedCell.mutableTypePtr` is corrected with it. `Cell.mutableTypePtr` also
states what the qualifier costs: `Cell.types` is caller storage that may sit in
read-only data, so a caller that must standardise copies into an `OwnedCell`.
The module doc now enumerates all 26 omitted non-deprecated declarations and
the 8 deprecated ones with no facade route, and `README.zig.md` points at it
instead of repeating a partial list. No signature, type, cast, buffer,
allocation or error changed, and no native byte was touched.

**Boundary, fixed here too.** `zig/consumer/build.zig` builds its `run` step
with no `b.args`, so `zig build run -- --provider <path>` dropped the flag that
`src/main.zig:11-12` documents - a `-Druntime` run then prints that it wants a
flag the caller just passed. One `if (b.args) |args| run.addArgs(args);`, the
shape `mpfr`, `random123` and `geographiclib-c` already use. The native job's
`zig build` (`.github/workflows/zig-fork-ci.yaml:67`) is the install step, so it
now carries `--prefix "$RUNNER_TEMP/spglib-default"` like the delivery job's
installs instead of writing `zig-out` into the checkout; the test, smoke, check
and consumer steps install nothing and are unchanged. No CI job was added.

**Verification and bound.** SOURCE-CONFIRMED against `include/spglib.h`,
`src/spglib.c`, `zig/cell.zig`, `zig/dataset.zig` and the workflow file. Nothing
was built, run or executed for this entry: `zig build`, `test`, `smoke`,
`check`, `check-targets`, `zig/consumer` `zig build run` and this workflow are
owed against the edited files before any of it is called green.

## 21. The nested consumer build is given what the outer one resolved - 2026-10-04

**Condition.** `zig build consumer` is not an in-process step. `runConsumer`
(`build.zig:533`) spawns a second `zig build` with
`b.addSystemCommand(&.{ b.graph.zig_exe, "build" })` in `zig/consumer`, because
that package depends on this one by path and a manifest dependency would close
a cycle. Two build graphs therefore have to agree, and every resolved choice of
the outer one has to reach the nested one by command line: the target query and
cpu, the optimize mode, the delivery and runtime selections, the system mode,
the executor switches, the job count and summary this workspace reads gates
against (`AGENTS.md:157-159`), both cache directories, the install prefix, and
the caller's own trailing arguments. Seven of those were missing.

**What was wrong, against the source.**

`run.addArg(if (query.isNative()) "run" else "install")` chose the step by
`Target.Query.isNative()`, which is `isNativeTriple() and ofmt == null`
(`lib/std/Target/Query.zig:396-398`) and `isNativeTriple()` (`:392-394`) demands
`cpu_arch`, `os_tag` and `abi` all be null. Every target that names itself
therefore took the `install` branch, so `zig build consumer
-Dtarget=x86_64-linux-gnu` installed the nested build on an x86_64 Linux host
instead of running it - and `x86_64-linux-gnu` is the first entry of this
repository's own `check_targets` (`build.zig:66-67`). The predicate also cannot
see an executor: a WASI consumer and a foreign-architecture consumer are the
cases `-fwasmtime` and `-fqemu` exist for, and `Query` says nothing about either.

The helper forwarded no executor switch and no `--libc-runtimes` at all, so a
nested build could not execute a foreign target even when the caller had enabled
the runner that does it. It named no `-j8` and no `--summary all`, which is the
boundary entry 19 recorded and explicitly deferred to `build.zig`: with nothing
on the command line, the nested build derives its own width from
`std.Thread.getCpuCount() - 1` (`lib/std/Io/Threaded.zig:1639`), and nothing can
append a `-j` to a `Run` step's command afterwards. It forwarded no
`--global-cache-dir`, so a global cache the caller selected on the outer command
line was invisible to the nested build, which then resolved one of its own
outside the approved root. It wrote `-fsys=spglib` only when the system mode was
selected, leaving the in-tree case to the nested build's own default rather than
to the caller's selection. And it emitted no `--`, so `b.args` was empty: the
nested `run` step does hand `b.args` to the consumer program
(`zig/consumer/build.zig:125`, landed by entry 20), and that program reads
`--provider <path>` (`zig/consumer/src/main.zig:125-133`) and refuses to invent
one (`:138-143`), so under `-Druntime=true` a caller who passed a provider got a
consumer that reported wanting the flag they had just passed.

**What changed.** One predicate and six argument blocks inside `runConsumer`,
plus the helper it names.

`hostCanExecute` (`build.zig:683`) replaces the query test with
`std.zig.system.getExternalExecutor` (`lib/std/zig/system.zig:42`), which is the
predicate `std.Build.Step.Run` asks about the artifact it is about to spawn
(`lib/std/Build/Step/Run.zig:1268`), asked about the *resolved* target rather
than the query. Its two `Run`-derived inputs are filled in from the same facts
`Run` reads: the consumer executable links libc (`zig/consumer/build.zig:81`), so
`link_libc` is true, and QEMU reaches a foreign dynamic linker only with
`--libc-runtimes`, so `qemu_fixes_dl` is `isGnuLibC() and
libc_runtimes_dir != null`. Each external executor counts as available only when
the build runner was told it may use one, which is what the `allow_*` fields
carry. The `.qemu` arm answers no for a glibc target with no `libc_runtimes_dir`,
because `Run` calls `failForeign` there (`Run.zig:1310`) rather than skipping.
This is the shape `lmdb` and `inchi` already carry, so there is one answer to
this question in this workspace rather than three.

The executor switches are forwarded when enabled (`-fdarling`, `-fqemu`,
`-frosetta`, `-fwasmtime`, `-fwine`; `--libc-runtimes` with its directory), so
the nested build runs under the same executor the decision above was made with.
`-j8` and `--summary all` follow, the latter as the two tokens the build runner
documents (`lib/compiler/build_runner.zig:262`, `:1639-1640`). `--cache-dir`
keeps its `/consumer` subdirectory and is unchanged;
`--global-cache-dir` is added as two tokens from `b.graph.global_cache_root.path`
with no subdirectory, because that cache holds fetched packages which every
graph in this workspace shares, and the same read and the same two-token
spelling the build system itself emits (`lib/std/Build/Step/Compile.zig:1478-1479`).
`b.graph` is the correct spelling: `global_cache_root` is a field of `pub const
Graph` (`lib/std/Build.zig:122`, struct at `:112`), not of `Build`, whose own
cache field is `cache_root` (`:58`).

The install prefix is handed on as `--prefix` and an absolute path when
`b.install_prefix` is not `<build root>/zig-out`, which is the prefix a nested
`zig build` would otherwise install into `zig/consumer/zig-out`, a build artefact
inside this checkout. A relative value is joined against `b.graph.cache.cwd`
first, because a relative `--prefix` would otherwise resolve against the
working directory set above, which is `zig/consumer`. `DESTDIR` is not
forwarded: the nested build inherits the environment this one ran with. This is
the shape `tzdata/build.zig` already carries.

The system selection is written in both directions,
`-fsys=spglib` or `-fno-sys=spglib`. Both are recorded on the graph by the build
runner before any script runs (`lib/compiler/build_runner.zig:169`, `:172`) and
reach the dependency inside the nested build because a dependency child shares
the parent's graph (`lib/std/Build.zig:352`), so the flag is the interface and
there is no option to read here. The caller's `b.args` is emitted last, behind
`--`, which must follow every argument above because it ends the nested build's
option parsing.

**What was not done.** No `-D` option was added to either build script and none
was removed: the nested package still declares only `linkage`, `runtime` and
`b.systemIntegrationOption("spglib", .{})`, and its `-fno-sys` route arrives
through the graph rather than through a new option. No step name, linkage
default, library source, header, table, upstream test, data byte or licence byte
changed; `zig/consumer/**`, `runtime/**`, `zig/**`, `devenv.nix`, `package.nix`,
`flake.nix`, `build.zig.zon` and CI are untouched. No permanent forwarding or
copy test was added: every item above is an argument list or a predicate inside
one existing function, and the existing `zig build consumer` route is the gate.

**Verification and bound.** SOURCE-CONFIRMED against this `build.zig`, the
pinned compiler's `lib/std` and `lib/compiler/build_runner.zig`, and the two
`hostCanExecute` implementations already in this workspace. Bounded execution
evidence arrived afterwards and is recorded in `README.md` under "Nested
consumer delivery": nine cases on this host's `x86_64-linux-gnu`, all passing,
each recording the nested command line the outer build produced. Those nine
cover `zig build consumer` on the default native selection and with
`-Dtarget=x86_64-linux-gnu`, which is the cell that separates the old predicate
from the new one; both linkages; both runtime selections, the loaded four given
`-- --provider <path>` after the `--` and with `SPGLIB_TEST_PROVIDER`
deliberately absent from the child environment; the `-j8` and `--summary all`
pair; both cache directories; and the install prefix. Still owed before the rest
is called green: a WASI cell with `-fwasmtime` and a foreign cell with
`-fqemu --libc-runtimes`, both currently unreachable by construction, and a
`-fsys=spglib` cell comparing the nested configure line. The `nested-no-provider`
case records the refusal the program declares, and a refusal is not a passing
route. Entry 19's deferred nested `-j8` boundary is closed by this entry.
`runConsumer` is named by its arguments rather than by a line number, because
that argument list is what this entry is about: the system selection, the
executor switches, `-j8` and `--summary all`, `--cache-dir`, `--global-cache-dir`,
`--prefix`, and `b.args`.

## 22. The current graph is described against its sources, and the 53-cell matrix is bounded to its own epoch - 2026-10-05

**Condition — SOURCE-CONFIRMED.** Four records still described this graph's
system-library route by a link name the graph does not use, and the matrix
section still named seventeen `CHANGELOG.md` entries when this file numbers
twenty-two.

**The `symspg` paragraphs.** `README.md` §Native-build deviations,
`README.zig.md` "Platform notes", `CHANGELOG.md` entry 5 and `FORK-NOTES.md`
entry 4 each said that `-fsys=spglib` links `symspg`, `symspg` being "the name
upstream's build and `spglib.pc` use". That is half true and therefore
misleading: `symspg` is upstream's own CMake output name
(`src/CMakeLists.txt`'s `OUTPUT_NAME`, `CMakeLists.txt:108-113`,
`cmake/spglib.pc.in:4`), but **this** package's installed `spglib.pc` says
`-lspglib` (`pkgConfigContents` in `build.zig`, and the CI assertions on both
linkages' `.pc`), and the graph's only system-library link is
`module.linkSystemLibrary("spglib", .{ .use_pkg_config = .force })`. All four
now say `spglib`, reached through pkg-config with `.force`, and name
`symspg` for what it is — upstream's file name. `FORK-NOTES.md` entry 4's
symptom, evidence and rule are upstream facts and are unchanged; only its
fix line moved. `FORK-NOTES.md` entry 11 already recorded the `.force`
choice correctly, and `README.md`'s "Artefact name is `spglib`, not `symspg`"
bullet already recorded the installed-metadata half; nothing else in either
changed.

**The consumer obligation, stated once where a caller meets it.** The six
declarations that drop `const` — `spg_standardize_cell` and its `spgat_`
spelling (`include/spglib.h:437,442`), `spg_find_primitive` and its `spgat_`
spelling (`:454,458`), `spg_refine_cell` and its `spgat_` spelling
(`:469,473`) — write through the caller's lattice and types in
`src/spglib.c:2070`, `:2072` and `:1926-1928`, with the header's own warning at
`:450`. Every other declaration in the header takes them `const`. A caller who
reaches for `spglib.c.spgat_standardize_cell` owes writable storage; the typed
surface's copy-into-an-`OwnedCell` behaviour is what the raw route does not
give. `README.zig.md` "Escape hatch" now carries that, and `FORK-NOTES.md`
entry 37 remains the record of how the list of six was established. Entry 20's
correction of the two false doc comments is not re-stated and not undone; this
entry records the same fact where a raw-route caller reads it.

**That obligation has now been exercised on both routes, and the scope is
bounded on purpose.** The integration owner's direct probe answered **8 of 8
steps on the linked static route and 8 of 8 on the loaded route** against an
**own dynamically loaded provider** — this SDK's own `libspglib.so`, built at
`…/native-final-prefixes/contract-final-after-20261004/spglib-dynamic-Debug/lib/libspglib.so`
and not downloaded or independent — and every run gave space group **225 Fm-3m**, Hall
**523**, **192** operations and a **2-atom** primitive cell — the scientifically
correct answer — with the borrowed input's bytes unchanged. That comparison is
recorded as **unchanged bytes**, not as "no write occurred": equal bytes cannot
distinguish an array that was never written from one written back with the same
values, and the six declarations above do write. The probe's fixture reads a
dataset through `getDataset`'s `const` lattice and then standardises a copy
through an `OwnedCell`, checking the borrowed cell is preserved. **This is not a
whole-SDK source-identity claim**: the runs were direct smokes against this tree
while its Markdown was still being written, no build-graph or native byte moved
during them, and nothing is claimed about a target, an optimize mode or a step
they did not run. No API type, macro, native source or C cast changed. Receipt:
`/home/tmp2/gertullj/scratch/foundation-libs/spglib-const-cell-evidence-20261005.json`,
built from the two observed runs; `FORK-NOTES.md` entry 37 carries the same
record. Two earlier compile errors in that probe — an absolute zone path, then
`memcpy` types — were faults in the probe's own throwaway manifest and bytes
helper, not in this SDK; the helper was corrected with **no SDK change** and the
corrected probe ran directly in 4.12 s.

**The 53-cell matrix, bounded.** `README.md` "Build, run and test matrix"
gains the source-bound matrix and the compile-only baseline: 53 cells,
`pass 20`, `build_only 33`, `build_fail 0`, runtime `fail 0`, run exit 0, from
`resume-8-evidence/20261004T221720228710Z-45046/spglib-53-target-8.json`; the
baseline receipt `baseline-spglib-check-targets`, exit 0, `failed: false`, from
`baselines-and-configs/20261005T014547Z-797a73f2/`; 8 of 8 native cells from
`native-final-evidence/20261004T233628757747Z-69351/run.json`; 8 of 8 own-provider
loaded cells from `loaded-final-evidence/20261004T232823091897Z-23133/run.json`.
`build_only` is compiled-not-run and is stated as coverage, never as a pass, and
the 20 passing cells are 20 of this SDK's 53 — not 20 of anything else. The
run predates the later build-graph, header and normalization edits; its
`source_unchanged: true` speaks only to its own run, and those edits are not
claimed to be covered by it.

**Not a gate of its own.** No build, test, smoke, check or provenance run was
executed for this entry. Every claim in it is read off the sources at this pin or
off a receipt another gate wrote, and the four `symspg` paragraphs and the
consumer paragraph are `SOURCE-CONFIRMED` — the pinned `build.zig`,
`include/spglib.h` and `src/spglib.c`, and the pinned compiler's `lib/std`. The
probe quoted above was run by the integration owner against `FORK-NOTES.md`
entry 37's subject, is cited with its receipt, and is recorded there; this entry
does not widen it into a source-identity claim. The pending rows of `README.md`
are unchanged by this entry, and no earlier entry's status moved.
