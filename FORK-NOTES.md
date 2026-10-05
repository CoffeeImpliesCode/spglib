# Fork notes

Issues met while packaging upstream spglib `v2.7.0`
(`12355c77fb7c505a55f52cae36341d73b781a065`) under Zig 0.16. Each entry records
the evidence it came from, the cause hypothesis, what was done, and the rule
worth keeping.

Verification status is stated per entry. Nothing here has been run by the
packaging worker, by the corrective review, by the documentation
reconciliation or by the documentation correction in entry 34: no build, test,
smoke, cross-target, packaging or formatting command was executed for any
entry. `PENDING-VERIFICATION` is therefore the default status of a correction
in this file: the change is in the source and no gate has observed it.
`OBSERVED` is reserved for something the integration owner recorded in a
receipt, and where one entry holds both, it says which part is which.
Entries 13 to 23 come from the corrective review of the first
implementation and are SOURCE-CONFIRMED against the pinned upstream sources,
the pinned compiler's own translation and build sources, and the imported
workflow files. Entries 24 to 27 come from the second reconciliation and are
SOURCE-CONFIRMED against the same pinned sources.

## 1. The only configured header depends on a VCS query

* **Symptom and evidence.** `src/spglib.c` includes `"version.h"`, but the
  repository only carries `src/version.h.in`. Upstream fills it in with
  `cmake/DynamicVersion.cmake`, whose `get_dynamic_version` shells out to
  `git describe` and `git rev-parse` at configure time and writes
  `SPGLIB_MAJOR_VERSION`, `SPGLIB_MINOR_VERSION`, `SPGLIB_MICRO_VERSION`,
  `SPGLIB_VERSION`, `SPGLIB_VERSION_FULL` and `SPGLIB_COMMIT`.
* **Cause (hypothesis).** The CMake path ties the header to repository state at
  configure time, which is both non-deterministic across clones and unavailable
  to a consumer who fetched the package as a hash-addressed archive.
* **Fix.** `build.zig` configures the same template from two checked-in values,
  `build.zig.zon`'s `.version` and the pinned commit, and panics at configure
  time if the two drift apart from `UPSTREAM.md`.
* **Affected.** All targets; every build.
* **Rule.** A generated version header must come from checked-in values, never
  from a build-time VCS query, and the build must refuse to configure when the
  header and the provenance record disagree.
* **Verification.** PENDING-VERIFICATION. The integration owner's gate list has
  to show a successful build plus the version test in `zig/tests/facade_test.zig`.

## 2. The public header, the private headers and the generated header live in three places

* **Symptom and evidence.** `src/*.c` include `"spglib.h"`, which is in
  `include/`, and `"version.h"`, which CMake generates into the binary
  directory. `include/CMakeLists.txt` adds `include/` to the same target that
  `src/CMakeLists.txt` compiles, and adds it as a PUBLIC include directory;
  `src/CMakeLists.txt` adds the source and binary directories privately.
* **Cause (hypothesis).** Nothing states the three directories in one place, so
  any build system that mirrors only part of it fails either at compile time or
  later at translation time.
* **Fix.** The C module, the `addTranslateC` step and the exported module all get
  the same three include paths: `include/`, `src/` and the generated directory.
  Installing `spglib.h` and `spglib/version.h` with `installHeader` also puts
  them on the include path of every compilation that links the artifact.
* **Affected.** All targets.
* **Rule.** Configure include paths once and apply them to the compilation, the
  translation step and the exported module. Installing a header is not the same
  as configuring the compile line.
* **Verification.** PENDING-VERIFICATION. A missing path shows up immediately
  as a compile or translate error on the first gate run.

## 3. `SPG_API` turns into `dllimport` unless a macro says otherwise

* **Symptom and evidence.** `include/spglib.h` defines `SPG_API` as
  `__declspec(dllexport)` under `SPG_BUILD`, as `__declspec(dllimport)` when a
  MSVC compiler is used without `SPG_STATIC_LIBRARY`, and as
  `__attribute__((visibility("default")))` otherwise.
* **Cause (hypothesis).** The default is tuned for a Windows shared build; a
  static archive consumed elsewhere needs the third case spelled out.
* **Fix.** `build.zig` defines `SPG_BUILD` for the core and defines
  `SPG_STATIC_LIBRARY` for both the core and the translation step whenever the
  linkage is static, so all three translation units agree.
* **Affected.** Windows mainly; harmless elsewhere.
* **Rule.** When a C library has an import/export macro, define it identically
  in every place that sees the header.
* **Verification.** PENDING-VERIFICATION. Only observable on
  `x86_64-windows-gnu`.

## 4. The library file is called `symspg`, not `spglib`

* **Symptom and evidence.** `src/CMakeLists.txt` sets `OUTPUT_NAME symspg` and
  exports it as `symspg`, while the pkg-config file is `spglib.pc` and the
  project is `Spglib`.
* **Cause (hypothesis).** The public name and the file name drifted apart
  upstream.
* **Fix.** The Zig artifact is named `spglib` as the fork contract requires.
  System-library mode links `spglib` through pkg-config with `.force`
  (`build.zig`'s single `linkSystemLibrary("spglib", .{
  .use_pkg_config = .force })`), which is the name this package's own installed
  `spglib.pc` resolves and the one that actually resolves against a prefix built
  here.
* **Affected.** System-integration mode on every platform.
* **Rule.** Before writing a system-library mode, read what the upstream build
  actually installs; the project name, the artifact name and the pkg-config name
  can all differ.
* **Verification.** PENDING-VERIFICATION; it needs an installed spglib, which
  the standard gate list does not provide.

## 5. A translated C enum is not always a Zig enum

* **Symptom and evidence.** `SpglibError` in `include/spglib.h` is a plain C
  enum. The Zig facade needs to both read the value `spg_get_error_code()`
  returns and pass one to `spg_get_error_message`. Depending on the toolchain
  generation, `addTranslateC` represents such an enum either as an integer alias
  or as a fieldless Zig enum, and the two need different conversions.
* **Cause (hypothesis).** The C-to-Zig translation of enums is not stable across
  toolchain versions, and neither `@intFromEnum` nor `@intCast` works for both
  shapes.
* **Fix.** `zig/error.zig` derives the raw type with
  `@TypeOf(c.spg_get_error_code())` and converts through a comptime-guarded
  branch: `@enumFromInt` when the translation produced an enum, a width-checked
  integer cast otherwise. All facade code uses the facade's own `ErrorCode`, so
  the raw shape stays confined to one file.
* **Affected.** All targets; the risk appears when the toolchain is upgraded.
* **Rule.** Wrap C enums once, at the boundary, and make the conversion survive
  both translation shapes instead of assuming one.
* **Verification.** PENDING-VERIFICATION. A wrong assumption fails at compile
  time, which the first `zig build` will show.

## 6. `libm` is not always a separate library

* **Symptom and evidence.** Upstream links `m` for every non-MSVC target
  (`src/CMakeLists.txt`). Zig's libc bundles the math functions for macOS,
  Windows and wasi, where an explicit `-lm` has nothing to resolve to.
* **Cause (hypothesis).** glibc and the BSDs keep `libm` separate; musl-derived
  and Darwin targets do not.
* **Fix.** The core module links `libm` only for
  `linux`, `freebsd`, `netbsd`, `openbsd`, `dragonfly`, `illumos` and `solaris`.
* **Affected.** `wasm32-wasi` and `aarch64-macos-none` in the cross matrix.
* **Rule.** Decide system-library links per target family explicitly instead of
  copying a single upstream link line.
* **Verification.** PENDING-VERIFICATION. A wrong decision is a link error on
  that target in `zig build check-targets`.

## 7. Slices over a returned-by-value C struct dangle

* **Symptom and evidence.** `spg_get_spacegroup_type` returns a
  `SpglibSpacegroupType` by value whose members are fixed-size `char` arrays. A
  first version of the facade copied those arrays into a local `storage` variable
  and pointed slices at it; the copy into the returned struct invalidated every
  slice, so the values were read from a dead stack frame.
* **Cause (hypothesis).** Slices over the parameters of a by-value result look
  owned but live only as long as the temporary.
* **Fix.** `SpacegroupType` and `MagneticSpacegroupType` store the character
  arrays in the value and expose accessors that take `*const`, so the slices are
  taken from the caller's own copy.
* **Affected.** All targets; a latent wrong-answer bug rather than a build
  failure.
* **Rule.** Never build a slice over a temporary by-value copy of a C struct.
  Either own the characters in the returned value or keep a borrowed pointer to
  the owner and document its lifetime.
* **Verification.** PENDING-VERIFICATION; the accessor tests in
  `zig/tests/api_surface.zig` read the strings.

## 8. spglib's error status is thread-local and cleared by every success

* **Symptom and evidence.** `spg_get_error_code` returns `spglib_error_code`,
  declared `static thread_local` at `src/spglib.c:50`. Every successful entry
  point assigns `SPGLIB_SUCCESS` to it, including the six version functions at
  `src/spglib.c:176-204`, so reading it after any successful call yields
  `.success` and another thread's outcome is never visible. A draft of the
  facade returned `spglib.get_error_code()` as the error for an empty rotation
  list, so the result depended on whichever call ran before it.
* **Cause (hypothesis).** A status variable without an associated operation is
  only meaningful immediately after that operation fails, and a per-thread
  variable cannot answer a question about another thread.
* **Fix.** Caller mistakes are detected in Zig and reported as `InputError`
  before any C call happens; the recorded status is consulted only after a call
  that actually failed, and `error.zig` and `README.zig.md` now state the
  per-thread, cleared-by-success lifetime instead of claiming the status is
  readable after any call.
* **Affected.** All targets.
* **Rule.** Separate "the library said no" from "the caller got the arguments
  wrong". Never surface a global or per-thread status as the answer to a call
  you rejected yourself, and never document it as durable state.
* **Verification.** PENDING-VERIFICATION; the test that reads the status after
  a failure and again after `getVersion` covers it.

## 9. The C entry points bound their output buffer by failing, not by truncating

* **Symptom and evidence.** `src/spglib.c` compares `dataset->n_operations`
  against `max_size` and, when the buffer is too small, frees the dataset, sets
  `SPGERR_ARRAY_SIZE_SHORTAGE` and returns 0. `spg_get_symmetry` is additionally
  marked deprecated in the header and forwards to `spgat_get_symmetry` with an
  angle tolerance of `-1.0`.
* **Cause (hypothesis).** The truncation behaviour is easy to assume and would
  silently produce a wrong group.
* **Fix.** `getSymmetry` takes the caller's `max_operations`, refuses a zero or
  out-of-`int` bound before calling C, and surfaces the refusal as an error. It
  calls the non-deprecated `spgat_get_symmetry` with the same `-1.0` sentinel the
  deprecated wrapper uses, so behaviour is unchanged.
* **Affected.** All targets.
* **Rule.** When wrapping a buffer-filling C API, check what it does when the
  buffer is too small, and make the facade's bound an error rather than a
  truncation.
* **Verification.** PENDING-VERIFICATION; the bounded-search test and the smoke
  output line about the eight-slot search cover it.

## 10. Fixture atom counts have to respect centring

* **Symptom and evidence.** Draft assertions expected the rutile primitive cell
  to hold 2 atoms and the cubic perovskite primitive cell to hold 1. Rutile is
  `P4_2/mnm` and perovskite is `Pm-3m`: both primitive lattices, so the primitive
  cell is the conventional cell (6 and 5 atoms). Body-centred iron is the case
  that reduces, from 2 atoms to 1.
* **Cause (hypothesis).** The habitual "primitive cells are smaller" intuition
  does not hold for P lattices.
* **Fix.** The fixtures and their provenance comments state the centring, and
  the assertions were corrected rather than relaxed.
* **Affected.** Tests only.
* **Rule.** Derive fixture expectations from the space group's centring, not
  from intuition; state the centring next to the fixture.
* **Verification.** PENDING-VERIFICATION; the affected tests are
  `symprec decides whether a distorted bcc cell standardises to bcc`,
  `primitive and conventional standardisation keep the cell volume` and the
  consumer's primitive-cell check.

## 11. System-library mode must translate the installed header

* **Symptom and evidence.** A single aggregate header that includes this
  repository's `spglib.h` would be translated even when the build links an
  installed spglib, so the bindings would describe 2.7.0 while the linked
  library could be an older release. Struct layouts and function signatures can
  differ between releases, so the translation would be silently wrong.
* **Cause (hypothesis).** Sharing one header between vendored and system mode
  hides which declarations the linker actually has to satisfy.
* **Fix.** The aggregate header is generated per mode. Vendored mode includes
  `spglib.h` and the generated `version.h` with both include paths; system mode
  includes `<spglib.h>` with no include path at all, so the translation sees the
  header installed next to the library. In system mode no artifact is produced,
  so `dep.artifact` has nothing to resolve. The bare name is not a guess:
  `include/CMakeLists.txt:1-5` attaches `spglib.h` to a `FILE_SET HEADERS`
  whose `INSTALL_INTERFACE` is `${CMAKE_INSTALL_INCLUDEDIR}` with no
  `BASE_DIRS` override, `cmake/spglib.pc.in` declares
  `Cflags: -I@CMAKE_INSTALL_FULL_INCLUDEDIR@`, `.distro/spglib.spec:122`
  packages `%{_includedir}/spglib.h`, and `ruby/extconf.rb:7` probes for the
  bare `spglib.h`. A first version guessed `<spglib/spglib.h>`, which no
  upstream install provides. The translation step asks for the package under
  its pkg-config name with `use_pkg_config = .force` and not `.yes`, because a
  query that fails under `.yes` falls back to `-lspglib`
  (`lib/std/Build/Step/TranslateC.zig:257-268`), which no upstream install
  produces, and a translation that silently finds no header is worse than a
  build that stops. This fork's own `installHeader` agrees, writing `spglib.h`
  flat.
* **Affected.** `-fsys=spglib` only; the vendored path is unaffected. Entry 24
  records the flag itself.
* **Rule.** A wrapper that can link either a vendored or an installed library
  must translate the header that belongs to the library it links, and must not
  advertise an artifact it does not produce.
* **Verification.** PENDING-VERIFICATION; requires an installed spglib.

## 12. Toolchain facts of this machine

* **Symptom and evidence.** The `zig` on `PATH` here is an anyzig dispatcher and
  exits with an error on a directory without a version-bearing project. The
  pinned 0.16.0 compiler lives at a fixed path under the local global cache and
  is the one to use.
* **Cause (hypothesis).** The dispatcher needs a package root to pick a
  toolchain.
* **Fix.** All builds and generators use the pinned binary by absolute path.
  `zig init --minimal` was used once, as package generation, only to obtain a
  valid `.name` and `.fingerprint` for the manifest; its generated `build.zig`
  and `build.zig.zon` were replaced.
* **Affected.** Every gate the integration owner runs.
* **Rule.** Generate manifests with the toolchain, then replace the generated
  build script by hand; never keep a generated one.
* **Verification.** PENDING-VERIFICATION.

## 13. `spg_get_error_message` returns NULL for SPGERR_NONE

* **Symptom and evidence.** `src/spglib.c:214-228` walks
  `spglib_error_message[]` and breaks on the `{SPGERR_NONE, ""}` sentinel at
  index 9 *before* it compares the argument, then returns NULL. `SPGERR_NONE`
  is a recorded code, not a hypothetical: a magnetic dataset that cannot be
  assembled sets it at `src/spglib.c:1247-1252`, and `fromRaw` maps any
  unrecognised recorded code to it. The facade passed the result straight to
  `std.mem.span`, so `.none` dereferenced a null pointer.
* **Cause (hypothesis).** A C API that signals "no entry" with a null pointer
  is indistinguishable from one that returns an empty string only by
  convention; the empty sentinel entry in the table suggests the latter.
* **Fix.** `errorMessage` returns `?[]const u8`, keeping the distinction
  between "spglib has a message" and "spglib has no entry" instead of
  substituting a fabricated success diagnostic. The two tests that asserted an
  empty string for `.none` were wrong about upstream and were corrected.
* **Affected.** All targets; a latent crash rather than a build failure.
* **Rule.** A wrapper that returns a C string must model the C API's own
  "absent" signal. Do not invent a non-null value to keep a slice type simple.
* **Verification.** PENDING-VERIFICATION; the raw and wrapped lookups are both
  asserted in `zig/tests/`.

## 14. Site tensors are one or three doubles per atom, and rank stops at 1

* **Symptom and evidence.** `cel_alloc_cell` allocates `num_atoms` doubles for
  `COLLINEAR` and `num_atoms * 3` for `NONCOLLINEAR` (`src/cell.c:67-79`),
  `spn_alloc_site_tensors` does the same and returns NULL for any other rank
  (`src/spin.c:279-293`), and the struct contract states both counts
  (`src/cell.h:31-32`). The standard tensors are copied as `tensors[i]` and
  `tensors[i * 3 + s]` (`src/spglib.c:1635-1641`). The facade computed
  `(rank + 1)^3`, which is 8 at rank 1: it rejected a search upstream accepts
  and, for a caller who followed its own documentation, handed C an
  8-per-atom slice over a 3-per-atom allocation. `SiteTensorType` has only
  three values (`src/cell.h:10-14`) and `cel_alloc_cell` allocates tensor
  storage for nothing else, so a higher rank reaches a `Cell` whose
  `cell->tensors` member was never written: the struct comes from a bare
  `malloc` (`src/cell.c:45`) and the `tensors` field is set only in the
  `COLLINEAR` and `NONCOLLINEAR` branches. `cel_free_cell` then tests that
  member for null (`src/cell.c:104`), so for such a rank the test itself reads
  an indeterminate pointer.
* **Cause (hypothesis).** A general "rank n tensor" formula was invented where
  upstream has exactly two cases, and the comment, the code and the test all
  agreed with the invention.
* **Fix.** `tensorVolume` is a switch returning 1, 3 or 0, and a rank above 1
  is `error.TensorRankOutOfRange` before any C call.
* **Affected.** All targets; the old `standardTensors` was a heap over-read
  of 5/3 of the allocation.
* **Rule.** Take array cardinalities from the code that allocates them, not
  from a formula that sounds right. When a C enum bounds a valid range, reject
  the rest rather than passing it down.
* **Verification.** PENDING-VERIFICATION; the rank-1 cases use upstream's
  non-collinear cell, which carries three doubles for one atom.

## 15. The lattice is a column basis, and a diagonal fixture cannot tell

* **Symptom and evidence.** `include/spglib.h:56-60` documents
  `[[a_x, b_x, c_x], [a_y, b_y, c_y], [a_z, b_z, c_z]]`, the doc comment of
  `spg_get_spacegroup_type_from_symmetry` says "Basis vectors given as column
  vectors", and `rot_cart = lattice @ rot @ lattice^-1` (`src/spin.c:322-325`)
  is a Cartesian rotation only when the columns are a, b and c. The facade
  documented rows and read them that way in `length` and `toCartesian`. Every
  lattice in the fixture suite was diagonal, and the two oblique ones were
  checked only through a determinant, which a transpose preserves, so the
  whole suite passed with the wrong basis.
* **Cause (hypothesis).** A diagonal matrix equals its transpose, so no
  diagonal fixture can distinguish the two conventions, and the raw pass-through
  into spglib was unaffected, so nothing else failed.
* **Fix.** `Cell.lattice` is documented as columns, `length` and `toCartesian`
  read columns, and `Cell.column` and `Cell.angle` make the reading explicit.
  The upstream 30-atom corundum cell is now a fixture: a = b = 4.8076344022756095
  with gamma = 120 and c = 13.1172699198127543 under the column reading, and
  5.378 and 4.164 under the row reading.
* **Affected.** Every consumer on a monoclinic, triclinic, tetragonal or
  hexagonal cell; a confidently wrong space group, not a crash.
* **Rule.** When a C API documents a memory layout, mirror it exactly and add
  a fixture that is not invariant under the mistake. Check the transpose
  symmetry of any property used to test a layout.
* **Verification.** PENDING-VERIFICATION; the corundum tests assert the three
  lengths, the a-b angle, a Cartesian site and the 30-to-10 R-centring
  reduction.

## 16. A space-group type lookup dropped its own status code

* **Symptom and evidence.** `spg_get_spacegroup_type` records
  `SPGERR_SPACEGROUP_SEARCH_FAILED` and returns a fully zeroed struct for a Hall
  number outside 1..530 (`src/spglib.c:751-761` over `get_spacegroup_type` at
  `2287-2326`), and `spg_get_magnetic_spacegroup_type` does the same outside
  1..1651 (`src/spglib.c:763-792`). The facade discarded the return type of the
  status and handed the zeroed struct back as a plain value: `number == 0` and
  empty strings, with no error.
* **Cause (hypothesis).** A struct-returning C function has no null to check, so
  the failure looks like a successful lookup until a field is read.
* **Fix.** Both facade entry points return an error union and reject an
  out-of-range number with `error.HallNumberOutOfRange` or
  `error.UniNumberOutOfRange` before the C call, in the same style as
  `getPointGroup` and `getSymmetry`. Every caller was migrated to `try`,
  including the consumer package and the smoke example.
* **Affected.** All targets; a silently wrong answer.
* **Rule.** A by-value struct result is a failure channel too. Check the
  library's documented range and its recorded status before trusting one.
* **Verification.** PENDING-VERIFICATION; both ends of each range are covered.

## 17. The package fingerprint was never valid

* **Symptom and evidence.** The toolchain rejected `build.zig.zon`'s
  `.fingerprint` and reported the value it computes for the package name
  `spglib`, `0x35191367c8f3aeca` (parent receipt
  `local://foundation-spglib-fmt.json`). Nothing downstream could be configured
  while it stood, so no build, test or smoke run had ever happened.
* **Cause (hypothesis).** The manifest was hand-written rather than generated,
  so the value was a plausible-looking constant.
* **Fix.** The reported value is in the manifest.
* **Affected.** Every gate.
* **Rule.** Take `.name` and `.fingerprint` from the toolchain, never from
  memory. A constant that nothing has ever validated is not evidence.
* **Verification.** OBSERVED by the integration owner as a rejected manifest;
  PENDING-VERIFICATION as accepted, which needs the first `zig build`.

## 18. Three test expectations the library cannot produce

* **Symptom and evidence.** `SpglibSpacegroupType.international` is the
  32-character spaced form and `schoenflies` carries its superscript
  (`include/spglib.h:143-156`), so for Hall 419 the values are
  `"P 4_2/m n m"` and `"D4h^14"`, and for Hall 529 `"I m -3 m"` and `"Oh^9"`.
  Three assertions read the short symbol from `international` and `"Oh"` from
  `schoenflies`, all four of which upstream's own Fortran functional test
  contradicts. Separately, `zig/tests/api_surface.zig` called a helper,
  `cellVolumeHelper`, that is defined nowhere in the package, and the smoke
  example expected 2 primitive atoms for the distorted bcc cell where the
  facade test and `FORK-NOTES.md` entry 10 both say 1.
* **Cause (hypothesis).** Nothing had ever been compiled, so a test file could
  name an undefined function and pin a string no code path produces.
* **Fix.** The symbol assertions read the right fields with the values
  upstream's own test pins, the undefined call was replaced by the volume
  property it stood in for, and the smoke count is 1. The message-string tables
  that only restated `src/spglib.c` were deleted rather than repinned.
* **Affected.** Tests and the example only; no library code.
* **Rule.** A fixture assertion is a claim about a value, not about which
  field it came from. Take it from the upstream test that pins the same
  struct, and treat a name that resolves to nothing as a gate failure, not as
  a detail.
* **Verification.** PENDING-VERIFICATION; the corrected values are cited from
  `test/functional/fortran/test_fortran_spg_get_spacegroup_type.F90:40-69`.

## 19. Ten public accessors had no compile call site

* **Symptom and evidence.** `build.zig`'s analysis step compiles the three test
  roots and the example, and no file under `zig/` referenced
  `Dataset.hallSymbol`, `Dataset.choice`, `SpacegroupType.hallSymbol`,
  `.choice`, `.internationalFull`, `.pointgroupSchoenflies`,
  `.arithmeticCrystalClassSymbol`, `MagneticSpacegroupType.ogNumber`,
  `MagneticDataset.standardLattice` or `MagneticDataset.standardRotationMatrix`,
  so those bodies were never analysed for any of the six targets. That is the
  gap the package contract's "analyse all public facade methods" rule exists to
  close.
* **Cause (hypothesis).** The accessors were written to mirror the C struct and
  nothing in the package had to call them.
* **Fix.** `zig/tests/api_surface.zig` reads all ten, each against an
  independent oracle: Hall 419 against upstream's Fortran functional test, the
  Hall 529 arithmetic class against `src/arithmetic.c`, the OG and Litvin
  numbers against `database/msg/msg_numbers.csv`, and the magnetic standard
  cell against the input cell's geometry. A test that compared an accessor to
  the raw struct member it forwards to was rejected: that can only fail if the
  accessor is removed, not if it is wrong.
* **Affected.** All targets; a coverage gap in `check` and `check-targets`.
* **Rule.** Every public declaration needs a real call site in something the
  compile-only step builds. Test it against a value from outside the wrapper,
  or the test only proves the accessor exists.
* **Verification.** PENDING-VERIFICATION; the analysis step has never run.

## 20. The published dependency instructions could not work

* **Symptom and evidence.** `README.zig.md` told a reader to run
  `zig fetch --save git+https://github.com/CoffeeImpliesCode/spglib` and then to
  paste `.spglib = .{ .url = "...", .hash = "..." }`. The repository is
  private, so an unauthenticated fetch cannot succeed, and the manifest line
  contained placeholders. No other file recorded a downstream URL or a digest.
  Entry 25 records a second defect in the command this entry installed in its
  place.
* **Cause (hypothesis).** Documentation was written for a public package in a
  private one, and a placeholder was mistaken for a value.
* **Fix.** The section now documents the arrangement that resolves today, a
  `.path` dependency on a local clone, which is what `zig/consumer/` uses, and
  states that no published URL or hash has been confirmed. Confirming those is
  the integration owner's job, not this package's.
* **Affected.** Documentation only.
* **Rule.** Document the dependency form that works, and say plainly when a
  value is unconfirmed. A configured `origin` is an intention, not a receipt.
* **Verification.** PENDING-VERIFICATION. `zig/consumer/build.zig.zon` carries
  the `.path` form the section now describes; entry 25 corrects the command
  that was documented beside it.

## 21. The facade unwrapped C pointers that have no null in their type

* **Symptom and evidence.** `dataset.zig` and `magnetic.zig` wrote
  `c.spg_get_dataset(...) orelse return err.lastError();` and
  `self.raw.rotations.?`, and the raw C test wrote `failed == null`. This
  toolchain's `addTranslateC` does not produce optional pointers for these
  declarations: `lib/compiler/translate-c/Translator.zig:1215-1237` makes an
  optional single pointer only when the child type is opaque or a function,
  and `lib/compiler/translate-c/ast.zig:1625-1636` renders every other C
  pointer as `[*c]T`, which carries no null and takes neither `?` nor
  `orelse`. `std.mem.span` says the same from its side: "`[*c]` pointers are
  assumed to be non-null and 0-terminated". `SpglibDataset *`,
  `int (*)[3][3]`, `char (*)[7]` and `char const *` are all complete,
  non-opaque types here.
* **Cause (hypothesis).** The facade was written against a nullable-pointer
  convention that no `addTranslateC` output actually has. Nothing had been
  compiled, so the shape assumption was never checked.
* **Fix.** `zig/ffi.zig` holds the four places where the shape matters:
  `isNull` compares the address, `borrow` and `single` produce the borrowed
  slice and the owner handle, and `spanOrNull` keeps the C API's own null
  signal. Each accepts either shape, so a toolchain that switches to optional
  pointers does not break the facade; that is the same defence `error.zig`
  already applies to the translated `SpglibError` enum. Every accessor in
  `dataset.zig` and `magnetic.zig` now goes through it. `cell.zig`'s
  `positionPtr` had the same class of defect in the other direction: it
  returned `[*c]const [*c]const f64`, a pointer to a pointer, where the C
  entry points declare `double const (*)[3]`; the element type is now the one
  the header declares, so the C side keeps its stride of three doubles.
* **Affected.** All targets; a compile error in the library's own Zig layer,
  not a wrong answer.
* **Rule.** Do not assume what a translation step emits. Read the translation
  code shipped with the pinned compiler, and put the assumption behind one
  helper instead of repeating it at every call site.
* **Verification.** PENDING-VERIFICATION. The shape is SOURCE-CONFIRMED from
  the pinned sources above; that the corrected calls compile needs the first
  `zig build`. Entry 26 records the toolchain's own objection to the first
  form of the shared helper.

## 22. The imported upstream workflows publish to services this fork does not own

* **Symptom and evidence.** `.github/workflows` held the seven upstream
  workflows beside `zig-fork-ci.yaml`. `release.yaml:5-7` triggers on
  `v[0-9]+.[0-9]+.[0-9]+` tags, `release.yaml:18-40` publishes built wheels to
  `https://pypi.org/project/spglib/` with `id-token: write` and then cuts a
  GitHub release, `step_coverage.yaml` uploads coverage to the upstream Codecov
  project, and `ci.yaml` invokes the reusable steps, so the seven only work as a
  set. `zig-fork-ci.yaml` calls none of them.
* **Cause (hypothesis).** A full `git clone` import brings `.github/` with it,
  and leaving the files in place looks like preserving upstream content while
  actually carrying a publication pipeline aimed at another account.
* **Fix.** The seven files are removed and `zig-fork-ci.yaml` is the only
  workflow left. `CHANGELOG.md` entry 7, `NOTICE.md` and `UPSTREAM.md` record
  the cutover and name the files. Nothing else in the repository referenced
  them: no build script, no tooling and no workflow.
* **Affected.** CI configuration only. No C source, table, test, build input or
  algorithm changed, and the removed files remain in the upstream repository
  and in the imported history.
* **Rule.** When importing a repository, an inherited workflow is inherited
  behaviour, not inherited documentation. Check what a copied workflow
  publishes, with which credentials, before keeping it.
* **Verification.** PENDING-VERIFICATION; no workflow was executed. The claims
  above are SOURCE-CONFIRMED from the workflow files as they were before
  removal.
* **Not touched, for the driver to decide.** `.github/.codecov.yaml`,
  `.github/renovate.json`, `.github/release.yml`, `.github/ISSUE_TEMPLATE/` and
  the CI and Codecov badge links in the upstream `README.md` are still present.
  They are upstream repository configuration and prose rather than publication
  workflows, so they were left alone; the upstream `README.md` was not edited
  because this fork documented itself in `README.zig.md` instead. **Superseded
  on 2026-10-04:** upstream's README now lives unchanged at
  `README.upstream.md` and this fork's own `README.md` is a separate document;
  see entry 31. The badge links still live in the preserved upstream file.

## 23. A cross target named a field that does not exist, and the root depended on its own consumer

* **Symptom and evidence.** `build.zig` resolved each entry of the six-target
  matrix with `b.resolveTargetQuery(.{ .cpu_arch_os_abi = triple })`. A triple
  string is not a `std.Target.Query` value: `Query`
  (lib/std/Target/Query.zig:15-54) holds `cpu_arch`, `cpu_model`,
  `cpu_features_add` and `_sub`, `os_tag`, the OS versions, `glibc_version`,
  `android_api_level`, `abi`, `dynamic_linker` and `ofmt`, and the triple string
  itself is an input to `Query.ParseOptions`, whose `arch_os_abi` field is at
  Query.zig:165. There is no `cpu_arch_os_abi` anywhere, so the initializer
  named no field of the struct it was initialising. Separately,
  `build.zig.zon` declared `.consumer_probe = .{ .path = "zig/consumer" }` and
  `build()` called `b.dependency("consumer_probe", ...)` unconditionally, while
  `zig/consumer/build.zig.zon` declares `.spglib = .{ .path = "../.." }`. That is
  the root depending on a package that depends on the root.
* **Cause (hypothesis).** Both were written against an API shape and a
  dependency direction nobody had checked, and a cycle in a manifest is a
  load-time failure rather than a compile one, so it would only surface once
  everything else was green.
* **Fix.** Targets go through `std.Build.parseTargetQuery(.{ .arch_os_abi =
  triple })` (lib/std/Build.zig:1423), which is the very entry point
  `standardTargetOptionsQueryOnly` uses at Build.zig:1500, so `-Dtarget=` and
  the matrix agree on what a triple means. The manifest dependency is deleted.
  `zig build consumer` now invokes the consumer as its own build in
  `zig/consumer`, as `b.graph.zig_exe build run` or
  `b.graph.zig_exe build install`, with `-Dtarget=`, `-Dcpu=` and
  `-Doptimize=` forwarded as single arguments from `Target.Query.zigTriple`
  (:421) and `Query.serializeCpuAlloc` (:530), and with `--cache-dir` and
  `<outer>/consumer` as two arguments when the outer build was given an
  explicit cache directory (`b.cache_root.path`,
  lib/std/Build/Cache/Directory.zig:13).
  A subdirectory, not the outer path itself, because two build graphs must not
  share one manifest directory; a null path means "the current directory" and
  the working directory is already the consumer package.
  The install prefix follows as `--prefix` and an absolute path when the caller
  named one, and is left out while `b.install_prefix` is still `<build
  root>/zig-out`. Without it the nested build installs into
  `zig/consumer/zig-out`, a build artefact inside this checkout, and a relative
  value would resolve against `zig/consumer` instead of against this build's
  root.
  The step is `run` when `hostCanExecute` says this build can execute the
  resolved target, and `install` when it cannot. That predicate is
  `std.zig.system.getExternalExecutor`, the one `std.Build.Step.Run` asks about
  the artifact it is about to spawn, and an external executor counts only when
  the build runner was told it may use one. A foreign target therefore runs
  under QEMU, Wasmtime, Wine or Darling when that switch is on, and `install`
  is not the answer for every target this host cannot run natively. Because the
  consumer is a separate process, its choices constrain nothing else in this
  build, which is what a build-time dependency on it would have done.
* **Affected.** `build.zig`, `build.zig.zon`, `zig/consumer` and the CI job that
  calls `zig build consumer`; no C source, facade or test changed.
* **Rule.** A package must not depend on a package that depends on it: run the
  consumer as a separate build instead. And read the pinned toolchain's struct
  before writing an initializer against it, because a wrong field name is not
  a default, it is an error.
* **Verification.** Partly observed. Every claim above is SOURCE-CONFIRMED from
  the pinned `lib/std` and from the current `runConsumer` and `hostCanExecute` in
  `build.zig`. Nine `zig build consumer` cases on this host's
  `x86_64-linux-gnu` then observed the forwarding itself: both linkages, both
  runtime selections, the default and the explicit target, both cache
  directories and the install prefix, with the provider handed to the program as
  a flag and no provider variable in the child environment. `README.md` records
  them under "Nested consumer delivery". A foreign target under an enabled
  executor, the `-fsys=spglib` route and `zig build check-targets` are still
  PENDING-VERIFICATION.
* **Not a risk, checked.** The cache forwarding above is the same shape the
  Random123 fork uses and needs no new helper: `b.cache_root` is a
  `Cache.Directory` whose `path` field is already the nullable string
  `Build.zig:58` sets from the runner's `--cache-dir`. The global cache is read
  the same way, as `b.graph.global_cache_root.path`, because `global_cache_root`
  is a field of `pub const Graph` and not of `Build`.

## 24. The system-integration flag is `-fsys=`, not a `-D` option

* **Symptom and evidence.** `README.zig.md`, `CHANGELOG.md` entry 5 and this
  file's entry 11 all told a reader to pass `-Dsystem-spglib`. That flag does not
  exist. `b.systemIntegrationOption` (lib/std/Build.zig:2726-2753) does not call
  `b.option`, so it never enters the `-D` map that `b.option` populates
  (Build.zig:1141-1167); it writes to `b.graph.system_library_options`
  (Build.zig:116), a separate map keyed by library name. The build runner is
  what fills that map, and its spelling is `-fsys=<name>` and `-fno-sys=<name>`
  (lib/compiler/build_runner.zig:169-174). `--system [pkgdir]` sets
  `graph.system_package_mode` (build_runner.zig:318-322), which is the default
  `systemIntegrationOption` falls back to when `config.default` is null
  (Build.zig:2745). A name the build script never declared is a hard error, not
  a silently ignored option: the runner prints "system library name not
  recognized by build script" (build_runner.zig:1747-1751).
* **Cause (hypothesis).** The flag was named after the API that reads it rather
  than after the argument the runner parses, and nothing in the repository ever
  passed the flag, so no gate could show it was wrong.
* **Fix.** Every document and comment now says `-fsys=spglib`, and
  `README.zig.md` lists the three flags the runner actually accepts. The
  vendored default is unchanged: with no flag, `system_package_mode` is false
  and this repository's own C sources are compiled.
* **Affected.** System-library mode on every target; the vendored default is
  unaffected.
* **Rule.** Take a command-line flag from the build runner that parses it, not
  from the name of the `std.Build` function that consults it. In Zig 0.16.0 the
  `std.Build` option surface and the runner surface are different: `-D` comes
  from `b.option`, and system integrations from `-fsys=`.
* **Verification.** PENDING-VERIFICATION; the flag needs an installed spglib,
  which the standard gate list does not provide. The spelling above is
  SOURCE-CONFIRMED from the pinned compiler's `lib/std/Build.zig` and
  `lib/compiler/build_runner.zig`.

## 25. A command list read from the build runner is not the compiler's command list

* **Symptom and evidence.** Entry 20 replaced a placeholder fetch instruction
  with `zig fetch --save ../spglib`, and this entry then recorded that there is
  no `fetch` command in this compiler at all. Both halves were wrong, in
  opposite directions. `zig fetch` exists: the pinned compiler's own usage text
  carries `zig fetch --save git+https://example.com/andrewrk/fun-example-tool.git`
  and the matching `.tar.gz` form, and a recorded invocation of `zig fetch
  <path>` on this toolchain exited 1 with "could not be recognized as a file
  path (FileNotFound) or an URL (InvalidFormat)" — a subcommand that did not
  exist could not diagnose its argument. What this entry had read was the build
  runner's own package-management options, `--fetch[=mode]` ("Fetch dependency
  tree and exit"), `--fetch=needed`, `--fetch=all` and `--fork=[path]` ("Override
  one or more projects from dependency tree")
  (lib/compiler/build_runner.zig:1662-1666), and then a text search of `lib/`
  for `zig fetch`, which returns that flag list rather than the CLI's commands.
* **Cause (hypothesis).** The conclusion was drawn from one subsystem's option
  list standing in for another's command list, and the check that was meant to
  confirm it — a search — could only find what that option list contains.
* **Fix.** The recommendation never changed and was right for the wrong reason: a
  `.path` dependency is what resolves, because this package has no published URL
  and no content hash to fetch from. What changed is the account of why, here,
  in `README.zig.md` and in `CHANGELOG.md` entry 10: `zig fetch` exists and is
  simply not an answer for this package, and the build runner's `--fetch` and
  `--fork` are a separate pair of options.
* **Affected.** Documentation only; `zig/consumer/build.zig.zon` already used
  the `.path` form and never used a fetch command.
* **Rule.** Before a document tells a reader to run a tool command, read it out
  of the tool's own help or run it once. A flag list from one subsystem is not
  the command list of another, and a search that can only return that flag list
  cannot refute a command. When the fix for a placeholder is to replace a
  sentence, check the command inside it too.
* **Verification.** OBSERVED for the command's existence, on the toolchain this
  package pins, by a recorded `zig fetch` invocation that reached its own
  argument diagnostic. Whether a hosted fetch would resolve is not claimed and
  cannot be: there is no URL and no hash to fetch from.

## 26. `anytype` is not a return type

* **Symptom and evidence.** The integration owner reported the gate stopping at
  `zig/ffi.zig:32` with an anytype return type rejected as invalid. The shared
  pointer helper in that file declares its return as a compile-time-selected
  concrete type: `if (@typeInfo(@TypeOf(pointer)) == .optional) then the
  optional's child type, else the pointer type itself`. `error.zig` already
  makes the same kind of choice one file up, when it branches between an enum
  translation and an integer alias.
* **Cause (hypothesis).** `anytype` is a parameter placeholder, not a result
  type, and a helper that has to return one of two shapes has to name both.
* **Fix.** `unwrap` declares that choice in its return type, resolved at
  compile time, and the four helpers keep their own `anytype` parameters. No
  second pointer compatibility layer was added for the problem.
* **Affected.** The library's own Zig layer on every target; a compile-time
  failure in the facade, not a wrong answer.
* **Rule.** Put a compile-time branch in the return *type* expression when the
  two branches return different types, and keep the choice in the one helper
  that owns the assumption. Do not add a second pointer compatibility layer to
  work around it.
* **Verification.** PENDING-VERIFICATION. The form in `zig/ffi.zig:32` is
  SOURCE-CONFIRMED from the source; that it compiles needs the next gate run.

## 27. A document that names a flag is a gate

* **Symptom and evidence.** All three defects in entries 20, 24 and 25 were in
  a document, and none of them would have been caught by a build: a placeholder
  `.url` and `.hash`, a `-D` flag the runner does not parse, and a `zig fetch`
  command that does not exist. All three were invisible to every command in
  the gate list, because no gate reads prose.
* **Cause (hypothesis).** Documentation is written from the shape of the API
  rather than from the tool that runs it, and no review step covers the text.
* **Fix.** Every command, flag and path in `README.zig.md` is now either quoted
  from the pinned compiler's own sources, or named as a step in `build.zig`, or
  marked as unconfirmed. The workflow runs only commands that exist.
* **Affected.** This repository's documents, and any later wave that documents a
  toolchain-dependent command.
* **Rule.** A documented command is part of the verification surface: quote it
  from the tool or say it is unconfirmed. "It reads correctly" is not evidence,
  and neither is a configured remote.
* **Verification.** PENDING-VERIFICATION; the reconciliation is a source
  review, not a run.

## 28. Three build-script shapes the pinned `std` does not have

* **Symptom and evidence.** The integration owner observed `zig build` exit 2
  three times inside `build.zig`. First, `check_step.dependOn(&analyze(...).step)`
  read a `step` field that `Build.Step` does not have: `analyze` declares
  `*std.Build.Step` as its return type (`build.zig:233-238`), and
  `lib/std/Build/Step.zig:305-307` takes the pointer itself. The `check-targets`
  call site already passed the value directly, which is why only `check` was
  red. Second, `translate_c.addCMacro("SPG_STATIC_LIBRARY", "1")` named a
  method that exists on `Module` (`lib/std/Build/Module.zig:533-536`) and not on
  `Step.TranslateC`, whose macros are `defineCMacro` and `defineCMacroRaw`
  (`lib/std/Build/Step/TranslateC.zig:153-161`). Third, the generated
  `version.h` passed a `std.SemanticVersion` to `{s}`: `Io/Writer.zig:1152-1168`
  accepts only pointer, slice and array types for `{s}` and rejects everything
  else through `invalidFmtError` (`:1801-1803`), and the type's own `format`
  (`lib/std/SemanticVersion.zig:153-157`) is reached by `{f}`
  (`Io/Writer.zig:1077`).
* **Cause (hypothesis).** Each call site was written from the shape of a
  neighbouring type: a step that owns a step, a module method on a translate
  step, and a version that reads like a string. Entry 26 is the same class of
  mistake one file over, where a neighbouring declaration set the shape.
* **Fix.** The step pointer is passed to `dependOn` unchanged, the translation
  defines the macro with `defineCMacro`, and both version macros are written
  with `{f}`. No compatibility wrapper was added: each call is the API the
  pinned compiler actually ships. Reading the same file for a fourth shape
  turned up a defect no gate in the standard list can reach, because none of
  them runs system-library mode: `Module.linkSystemLibrary` calls
  `requireKnownTarget` (`lib/std/Build/Module.zig:370`, `:661-665`), which
  panics for a module created with only a root source file, and the exported
  `spglib` module was created that way. It now carries the target and optimize
  mode of the build that created it, so `-fsys=spglib` configures.
* **Affected.** `zig build`, and therefore every step in this repository on
  every target. No C source, facade or test changed for these three.
* **Rule.** Read the declaration on the type you are calling, not the one on
  the type that looks like it. `Step` has no `step` field even though
  `Step.Compile` has one, and `Module` and `Step.TranslateC` share `addIncludePath`
  without sharing `addCMacro`. Bound: Zig 0.16.0, whose `lib/std` and
  `lib/compiler` are the only evidence.
* **Verification.** PENDING-VERIFICATION. Each replacement is SOURCE-CONFIRMED
  against the pinned compiler's own source at the lines cited; that the build
  now configures needs the next `zig build`.

## 29. A public function with no export and no call site is not public

* **Symptom and evidence.** `zig/cell.zig` declared
  `pub fn allocateCell(allocator, capacity)`, `README.zig.md:127-129` documents
  it as the way a caller supplies the four-times-atom-count headroom that
  `spg_standardize_cell`, `spg_find_primitive` and `spg_refine_cell` need, and
  `zig/root.zig` exported `Cell` and `OwnedCell` without exporting it. Its only
  caller in the tree was `dataset.zig`, so nothing in the package a dependent
  program imports could reach it, and the `check` step never analysed its body.
  The two ends of the fallible type lookups were also asserted only with
  `_ = try spglib.getSpacegroupType(1);` and its three siblings, which is the
  "a call that does not throw" shape the workspace forbids.
* **Cause (hypothesis).** The module root was written from the types a consumer
  needs to hold, and a function that only the package itself used never made it
  onto the list. The bare `try` lines were placeholders left where a value was
  needed and nothing pinned one.
* **Fix.** `zig/root.zig` exports `allocateCell`, and `zig/tests/api_surface.zig`
  calls it and hands the buffers to `spgat_standardize_cell` on upstream's
  distorted bcc cell, checking the known primitive result (one atom, lattice
  vectors within 1e-2 of sqrt(8)/2, volume within 1e-2 of the input). The four
  boundary lookups now carry the answers `src/spg_database.c` records for Hall 1
  and Hall 530 and `database/msg/msg_numbers.csv` records for UNI 1 and UNI
  1651.
* **Affected.** The exported module surface on every target, and the coverage of
  the compile-only analysis step.
* **Rule.** A public declaration needs an export and a real call site, and a
  test that only proves a call did not throw is not a test. When a boundary
  exists, pin the value the upstream data records at that boundary, not that the
  call survived.
* **Verification.** PENDING-VERIFICATION. The database values are read out of
  `src/spg_database.c:11-13` and `:1072-1073` and
  `database/msg/msg_numbers.csv:2,1652`; that the lookups return them needs the
  next `zig build test`.
## 30. Zig 0.16.0 mis-passes the doubles of a wide `extern "C"` call

**Evidence.** `zig build test` failed 13 tests. Every failing call is an
spglib entry point with more than six integer-class arguments; every call that
worked has six or fewer:

| call | integers | doubles | result from Zig |
|---|---|---|---|
| `spg_get_dataset`, `spg_get_international`, `spg_get_multiplicity`, `spg_get_pointgroup`, `spg_get_symmetry_from_database`, `spg_get_magnetic_symmetry_from_database`, `spg_get_spacegroup_type_from_symmetry`, `spg_niggli_reduce`, `spg_standardize_cell`, `spg_refine_cell` | <= 6 | 0-1 | correct |
| `spgat_get_symmetry` | 7 | 2 | `SPACEGROUP_SEARCH_FAILED`, 0 |
| `spgms_get_magnetic_dataset` | 7 | 3 | NULL |
| `spg_get_ir_reciprocal_mesh`, `spg_get_dense_ir_reciprocal_mesh` | 9 | 1 | `SPACEGROUP_SEARCH_FAILED`, 0, both output arrays untouched |

A standalone C program compiled with `zig cc -O1` and linked against the same
`libspglib.a` returns `136`/`P4_2/mnm`, `16` for `spg_get_symmetry`, `40` at
`8^3` and `4200` at `40^3`, and `msg_type = 3` for the magnetic dataset, with
errcode 0 throughout. The same calls from Zig at ReleaseSafe return the same
answers. So the library is right and the binding is right, and the difference is
in how the call is emitted.

**Reproducer, with no spglib in it.** Five fixed-arity C functions, all `int`
and pointer parameters except three `double`s in the last one, called from Zig
0.16.0. `six_args`, `seven_args`, `nine_args` and `ten_args` all return the
value their C definitions return, in Debug and ReleaseSafe alike. The function
interleaving three doubles among seven integers returns `1356891247` where the C
definition returns `1234567891`, in both modes. Only the floating-point
arguments are wrong: spilled integers arrive correctly.

**Cause.** Not established. The pattern is x86-64 psABI argument classification,
where doubles go to SSE registers independently of the six integer registers, so
a signature with more than six integer-class arguments mixes register and stack
slots. This is a compiler defect, not a defect in spglib or in this binding, and
it is bounded to what was observed: x86-64 linux-gnu, Zig 0.16.0.

**Fix.** `build.zig` compiles the Zig caller at `ReleaseSafe` when the requested
mode is `Debug`, and turns C sanitization off on the core module because an
instrumented archive cannot link into a non-instrumented program. The C library
keeps the requested optimisation and the `-DSPGDEBUG` the Debug flags carry, so
what the tests exercise is still the debug build of the C. No signature was
rewritten and no oracle was weakened.

**Rule.** When every failing call shares an argument-count property and every
passing one does not, count the arguments before reading the callee. A C probe
against the same archive separates a library defect from a caller defect in one
command, and a fixed-arity reproducer in the caller's own language separates a
binding defect from a compiler defect.

**Verification status.** Observed: 41/54 before the change, 52/54 after, with
Debug and ReleaseSafe agreeing.

## 31. The upstream README occupied the path this fork needed, and packaging wanted to be a second writer

Two problems from the 2026-10-04 contract migration, both of which look like
documentation until they become a licence or a link error.

### 31a. A vendored project's own README is upstream content at the canonical path

* **Condition.** A downstream packaging of an upstream project that ships its
  own `README.md` at the repository root.
* **Symptom and evidence.** `README.md` was upstream's file, byte for byte
  (sha256 `294f6f53…`), so this fork had no README of its own: every fact about
  the fork lived in `README.zig.md`, and the document a reader opens first
  described CMake, PyPI and the upstream badge links instead. `FORK-NOTES.md`
  entry 22 records the earlier decision to leave that file alone, and states the
  reason that produced the gap.
* **Fix.** Upstream's bytes were preserved at `README.upstream.md` and the
  canonical `README.md` became this fork's document, in the fixed order:
  native-source deviations, native-build deviations with the dated history link,
  the support matrix with each row's evidence status, then consumption. The
  Zig interface stayed in `README.zig.md`. `UPSTREAM.md`, `NOTICE.md`,
  `CHANGELOG.md` and the one README citation in `FORK-NOTES.md` entry 22 now name
  the preserved path. `tools/check_provenance.sh` gained the check that makes
  this durable: `README.upstream.md` must equal upstream's README at the pinned
  commit, extracted from the clone and compared byte for byte, and `README.md`
  must *not* equal it. A name is not evidence; bytes are.
* **Rule.** Never label a fork-authored README upstream, and never overwrite an
  upstream file without preserving its bytes somewhere a gate can compare. When
  a preserved copy and a new document share a name's history, record the
  preserved one's digest in the record file, not just its path.
* **Targets bound.** Any vendored or imported project with a root README. The
  comparison needs the full clone, because it reads the pinned commit; it cannot
  run against a filtered or fetched source copy.

### 31b. A package definition must not re-author what the build already installs

* **Condition.** A derivation whose only build command is the project's own
  `zig build install`, and an installed tree the build already owns completely.
* **Symptom and evidence.** `build.zig` installs the library, both headers, a
  relocatable `spglib.pc` and the four licence and provenance records. The
  natural instinct for `package.nix` was to copy the licence files again and to
  write its own `spglib.pc` with `-L$out/lib` — a second writer, a second
  spelling of one fact, and a metadata file that silently disagrees with the
  `${pcfiledir}` form the build emits. Neither would ever have failed loudly.
* **Fix.** `build.zig` is the single writer; `package.nix` verifies. Its
  post-install phase checks both headers, the four records under
  `share/licenses/spglib/`, the library file for the requested linkage, and that
  the installed `spglib.pc` links `-lspglib`. It writes nothing.
* **Three facts this made visible, each read out of a file rather than
  remembered.** `build.zig` names the artefact `spglib`, so the installed
  metadata must say `-lspglib`; upstream's CMake install names the same library
  `symspg` (`CMakeLists.txt:108-113`, `cmake/spglib.pc.in:4`), and a `.pc`
  copied from upstream would name a library the output does not contain. The
  static archive needs `-lm` in `Libs` because the consumer performs spglib's
  `sqrt`/`fabs`/`sin`/`cos` calls itself, while the shared object recorded them
  at link time, so only it carries `Libs.private: -lm` — and which of the two a
  target needs is the same `needsLibM` decision the library link makes. And
  upstream's `.pc.in` bakes in absolute `@CMAKE_INSTALL_FULL_*@` paths, which
  are wrong for both a `--prefix` install and a store path.
* **Rule.** Packaging may verify a build's installed output; it must not
  re-author it. When a derivation has to know a fact, make the check fail
  loudly on the fact's absence instead of writing a second copy of it.
* **Open, and deliberately not asserted.** Whether Zig's build graph consumes
  nixpkgs' `NIX_CFLAGS_COMPILE` was not determined here, so this file makes no
  claim that the packaged library carries nixpkgs' hardening flags, and
  `package.nix` passes no C flag of its own. If a gate shows the flags are
  ignored, the correction belongs in the build, not in the derivation.
* **Targets bound.** Any SDK whose native build owns a complete install tree.
* **Verification status.** Partly observed on 2026-10-04, against the source as
  it stood then; `README.md`'s matrix carries the receipts. `nix build` of both
  `x86_64-linux` derivations exited 0, the flake's three package names and each
  variant's `passthru.linkage` evaluated, and devenv's three lazy output
  attributes evaluated without building the library. `devenv shell` itself was
  not entered, no installed-C consumer has run, and the extended provenance gate
  has not been re-run since it was extended. Those two Nix builds also predate
  the `-Dtarget` `package.nix` now derives from `stdenv.hostPlatform`, so the
  three systems other than `x86_64-linux` are owed a build each.
  `flake.lock` now exists and pins the nixpkgs revision `flake.nix` names, by
  revision and resolved hash; there is no `devenv.lock`, and `devenv.yaml` pins
  its own input by revision. Corrected 2026-10-04.

## 32. "Not in this stage" is not the same as "not part of the SDK"

* **Condition.** Documentation written while a migration wave is still moving,
  for a feature another role is delivering in the same wave.
* **Symptom and evidence.** `README.md` described runtime loading with
  stage-scoped wording — "not wired in this stage", "a later stage replaces
  this paragraph" — and the first report repeated that phrasing. Runtime loading
  is part of the SDK contract for all nineteen migrations, and the graph,
  descriptor, facade and loader core were landing in the same wave. A reader
  takes "not in this stage" as "not supported", and a report that says it turns
  a moving part into an apparent exclusion that the next reader has to undo.
* **Fix.** The README now describes what the package does — it links its C core,
  and the dynamic variant is an ordinary shared object — then lists the provider
  requirements that hold whenever a provider is loaded, and marks the route as
  PENDING-VERIFICATION until the driver gates it. The matrix says "no gate has
  observed these yet; they are open work, not exclusions" instead of "not
  claimed anywhere in this repository". No sentence in the fork's documents
  refuses a capability the contract requires.
* **Rule.** Describe the current boundary and the pending work; never describe a
  moving part as an exclusion. "No observation yet" is a statement about evidence.
  "Not a feature" is a statement about the product, and only the interface owner
  may make it.
* **Targets bound.** Any document or report written mid-wave. A stage number in
  prose is a maintenance liability: it expires silently.
* **Verification status.** PENDING-VERIFICATION for the runtime route itself. The
  interface is taken from the owning role's source, not from this entry.

## 33. A dispatch that validates against a macro needs the header configuration that macro lives in

* **Condition.** A runtime dispatch that checks a provider by calling an entry
  point and comparing the answer with a macro from the translated header.
* **Evidence.** `runtime/library.zig` compares `spg_get_major_version()` with
  `dispatch.SPGLIB_MAJOR_VERSION` and the minor and micro the same way, and
  `spg_get_version()` with `dispatch.SPGLIB_VERSION`. Those macros come from
  `version.h`, which `build.zig` configures from `src/version.h.in` for this
  repository's own translation. A `-fsys=spglib` translation includes the bare
  installed `<spglib.h>`, which includes only `<stddef.h>`
  (`include/spglib.h:51`) and defines no version macro at all.
* **Alternative that was rejected.** Translating this repository's generated
  `version.h` next to the installed header would make the combination compile —
  and would bind an installed library to this tree's version claim, which is the
  exact substitution `-fsys=spglib` exists to avoid.
* **Fix.** `addSpglib` refuses the pair in the one place where the two modes
  meet, with a message that names the reason and the way out: build spglib from
  these sources to use the runtime route.
* **Rule.** When a mode's viability comes from the *configuration* of a
  translation rather than from its text, the honest answer is to refuse the
  combination out loud. Synthesising the missing input from this tree converts
  a foreign library into a claim about this one.
* **Targets bound.** Any SDK whose dispatch or loader validates against a macro
  that a generated header supplies, which is every SDK where the version macros
  are configured rather than checked in.
* **Verification status.** PENDING-VERIFICATION. The refusal is
  SOURCE-CONFIRMED at `build.zig`; no build has been run that took that branch.

## 34. A record of what is missing expires when the file lands, and a route is not a linker error

* **Condition.** A readiness record written while a source file was still in
  flight, and a provider contract that described a code path by the kind of
  symbol it used to be.
* **Symptom and evidence.** `README.md`, `README.zig.md` and `CHANGELOG.md`
  entry 15 all reported `runtime/generate.zig` as not in the tree, named
  `runtime/graph.zig:228` as the line that builds it, and concluded that a
  runtime build cannot configure yet — while `runtime/graph.zig`'s
  `generateDispatch` builds exactly that file as a host program for the target
  being built and runs it over that target's own translation output. The same
  documents described the two `provider_optional` names as direct `extern`
  references whose absence is a link error, which is what they were before the
  generator existed: `runtime/generate.zig`'s `Options.routeOf` sends every
  `--optional` name down the optional route, where the dispatch gives it a
  nullable field initialised `null`, lists it in `optional_symbols` rather than
  in `symbols`, and emits
  `table.<name> orelse requireAvailable("<name>", "<name>")` — a
  `std.debug.panic` naming the library, the symbol the provider lacks and the
  reason. A provider that does not export them therefore loads, and the first
  call stops the program by name. The packaging records said two lock files were
  both absent; one exists and one is not wanted, because `devenv.yaml` pins its
  input by revision.
* **Fix.** Each statement now describes the code that exists and names the file
  or the function rather than a line number a later edit moves.
  `CHANGELOG.md` entry 17 records the corrections and points at the evidence,
  and `runtime/graph.zig`'s own comment on `provider_optional` now says the
  same thing in the file a maintainer reads first.
* **Rule.** Name the file or the function, not the line, in any statement about
  moving source; and describe a route by what it does at run time rather than by
  what it used to be called. A statement about what is missing is a claim with
  an expiry date, and the day it is wrong it excuses a failure that no longer
  exists — entry 32's rule applied one level up.
* **Targets bound.** Any readiness or verification record, in any SDK whose
  sources are still landing.
* **Verification status.** SOURCE-CONFIRMED for every claim above, read out of
  `runtime/generate.zig`, `runtime/graph.zig`, `build.zig.zon`, `flake.lock`,
  `devenv.yaml` and the pinned compiler's own usage text. The gates that
  observed both routes are in `README.md`'s matrix with their receipts, and a
  replay against the frozen handoff is owed for the edits that landed after
  them.

## 35. A facade guard needs an arithmetic site the C really performs

* **Condition.** A wrapper rejecting an argument on a range a reader can
  imagine, while the native routine reduces that argument before using it.
* **Evidence.** `gridPointFromAddress` guards two things and no more: a mesh
  entry that is not positive or is above `2^30-1` (`MeshOutOfRange`), and an
  address component above `2^30-1` in either direction
  (`GridAddressOutOfRange`), then calls `spg_get_dense_grid_point_from_address`.
  Both guards name arithmetic upstream really performs: `modulo_i3` divides by
  `mesh[i]` (`src/kgrid.c:100`), the double-mesh conversion computes
  `address[i] * 2` (`src/kgrid.c:39`), and the reduction computes
  `2 * mesh[i]` (`src/kgrid.c:125`). What is not there is a bound of the address
  by its mesh, and there cannot be one, because upstream folds first:
  `spg_get_dense_grid_point_from_address` (`src/spglib.c:893-904`) doubles each
  component, subtracts `2 * mesh[i]` once where the doubled component exceeds
  the mesh, halves it, and takes the remainder modulo the mesh
  (`src/kgrid.c:120-128`, `:68-83`, `:96-106`, `:85-94`). Worked through that
  path: in a 2x2x2 mesh `{3,0,0}`, `{1,0,0}` and `{5,0,0}` all answer index 1,
  and in a 4x4x4 mesh `{5,0,0}` answers index 1.
* **Fix.** The mesh-membership bound is gone and the two overflow guards are
  what remain, under the same two error names, with their meaning written in
  `zig/error.zig` rather than restated in prose. The integration owner's run on
  the tree before the change is the receipt that the bound existed: it refused
  `{3,0,0}` and `{5,0,0}`, and answered index 1 for mesh `{1073741824,2,2}`,
  where the doubling overflows.
  A mesh entry of `2^30` is what makes that threshold the one it is: `2 * mesh[i]`
  is `2^31`, which does not fit a signed 32-bit `int`, so before the guards an
  entry that large reached an overflow inside the library and what a build
  reported for it depended on how that build wrapped the overflow rather than on
  anything the header means. With the guards no signed overflow is reachable from
  this entry point at all, so the answer does not depend on the optimization
  mode — which is a claim for the replay to confirm in both modes, not one this
  entry makes on anyone's behalf.
* **Rule.** A guard in a facade is justified by an arithmetic site in the C it
  calls, not by a range that seems plausible. When the C normalises its
  argument first, a bound the C never needed refuses a valid answer — and a
  document that repeats the bound then outlives the code by years, which is
  entry 34's failure mode one level down.
* **Targets bound.** Any facade that validates an argument the native routine
  normalises: grid addresses and meshes, indices, tolerances, counts.
* **Verification status.** SOURCE-CONFIRMED from `zig/symmetry.zig`,
  `zig/error.zig`, `src/spglib.c:893-904` and `src/kgrid.c`, including the
  folded indices above. The behaviour is still PENDING-VERIFICATION: the red run
  on the previous tree is recorded above, and a matching green run is owed with
  the rest of this SDK's replay.

## 36. A platform attribute that this nixpkgs does not have, and a task that inherits the caller's directory

* **Condition.** An 18-SDK acceptance run on 2026-10-04 evaluated this SDK's Nix
  variants and devenv gates from a scratch project directory, using
  `devenv --from path:<this repository>`. Two of the SDK's own gates failed and
  the packaging route never started.
* **Evidence.** `nix build path:<this repository>#static #shared` exited 1 with
  `error: attribute 'linuxLibc' missing` at `package.nix:100`,
  `else if stdenv.hostPlatform.linuxLibc == "musl" then "musl"`, raised from
  `derivationStrict` while evaluating attribute `installPhase` of derivation
  `spglib-2.7.0`; the run recorded no output path at all, because evaluation
  failed before any derivation existed. The attribute is not a spelling this
  revision dropped from one place: the pinned nixpkgs
  `c7def046b9a883d46974757852106483d741586f` defines no `linuxLibc` in
  `lib/systems/parse.nix`, `lib/systems/inspect.nix` or
  `lib/systems/default.nix`. It does define the same fact. `lib/systems/parse.nix`
  gives every platform an ABI (`abis.gnu`, `abis.musl`, `abis.musleabi`,
  `abis.musleabihf`, `abis.muslabin32`, `abis.muslabi64`, `abis.unknown`),
  `lib/systems/inspect.nix:429-437` writes `isMusl` as the sum-of-products over
  the five musl ABIs, `lib/systems/default.nix:442` runs those patterns over
  `final.parsed` to give the elaborated platform every `is*` predicate, and
  `lib/systems/default.nix:186` is nixpkgs asking `final.isMusl` when it names
  the platform's own libc. Separately, `devenv tasks run sdk:consumer` reported
  `error: no build.zig file found, in the current directory or any parent
  directories` and `sdk:provenance` reported `line 3:
  ./tools/check_provenance.sh: No such file or directory`, while `devenv info`
  printed `DEVENV_ROOT` as the scratch *project* directory - which is the
  directory those two commands ran in, and which holds `.devenv` and
  `devenv.lock` and neither `build.zig` nor `tools/`.
* **Fix.** `zigAbi` asks `stdenv.hostPlatform.isMusl`. The Darwin arm stays
  first, because `lib/systems/parse.nix:963-964` parses every non-Linux,
  non-Windows platform's ABI as `abis.unknown`, which no `isMusl` disjunct
  matches. `sdk:build`, whose `zig build` *is* the default install step, gains
  `--prefix` under `$SPGLIB_INSTALL`, else the exported `ZIG_LOCAL_CACHE_DIR`,
  else the exported `TMPDIR` - with no `/tmp` default, so a caller that exported
  none of the three is told which variable to set instead of having output
  written somewhere it did not name, and no longer writes a `zig-out/` into the
  checkout it was pointed at. Every task begins with
  `cd ${lib.escapeShellArg (builtins.toString ./.)}`; the root is named by the
  file that owns it, because `$DEVENV_ROOT` names the caller's project and
  `builtins.toString` avoids the store copy an interpolated `${./.}` can pull
  the whole tree into - a read-only tree that `zig build` cannot cache into.
* **Rule.** Read a platform's libc from the ABI nixpkgs actually parsed
  (`parsed.abi`, and the predicate built from it), never from an attribute name
  remembered from another revision; and a generated task body owns its working
  directory, because the harness that runs it does not. A task whose command
  installs takes its prefix from outside the tree by default, even when the
  command looks like an ordinary build.
* **Targets bound.** Any Nix expression in this repository that derives a tool
  triple, an ABI, a libc or a platform predicate from `stdenv.hostPlatform`, and
  any devenv task or script in this repository that names a path.
* **Verification status.** SOURCE-CONFIRMED against the pinned nixpkgs sources
  cited above and against `devenv info`'s recorded `DEVENV_ROOT`; the acceptance
  log is the receipt that both gates were red. PENDING-VERIFICATION: nothing was
  built, evaluated, installed or run for this entry, and both Nix variants and
  both devenv gates are owed a replay on the corrected source.

## 37. A qualifier dropped on a premise the C contradicts, and a boundary list that stops short

* **Condition.** A wrapper drops `const` where a native declaration does, and a
  module doc states which native entry points its typed surface leaves out.
* **Evidence.** `Cell.mutableTypePtr` said the `spgat_*` family takes `int *type`
  "even though it only reads the types", across "the eleven call sites", and
  `Cell.latticePtr` said "upstream's read-only entry points take non-const
  pointers". Both are false against `include/spglib.h` and `src/spglib.c`. The six
  declarations that drop `const` are exactly the standardisation ones
  (`include/spglib.h:437,442,454,458,469,473`), and every other declaration in
  the header - `spg_get_dataset` (`:206-209`), the layer, magnetic and symmetry
  searches - declares the lattice `double const` and the types `int const`. The
  writing is in the C, not only in the header's prose: `set_cell` copies the
  lattice at `src/spglib.c:2070` and assigns `types[i] = cell->types[i]` at
  `:2072`, `standardize_cell` at `:1926-1928`, and the header warns of it at
  `:450`. The call-site count is two, not eleven - `spgat_standardize_cell` and
  `spgat_refine_cell` (`zig/dataset.zig:310,360`) - each through an `OwnedCell`.
  The module doc's boundary sentence named three omissions
  (`zig/root.zig:49-52`, and the same three again in `README.zig.md:294-297`)
  where `include/spglib.h` declares 26 non-deprecated entry points with no facade
  function: `spg_delaunay_reduce` (`:480`), the non-dense
  `spg_get_grid_point_from_address` (`:491`), four standardisation declarations
  that take no angle tolerance (`:437,454,458,469`),
  `spgat_get_dataset_with_hall_number` (`:239`), the collinear-spin
  (`:261,267,273`) and site-tensor (`:301,308,316`) searches, the
  symmetry-to-type searches (`:341,345`), the magnetic operation-database
  lookup (`:420`), the four reciprocal-mesh constructors (`:512,517,531,535`),
  the four grid-points-by-rotations entry points (`:544,547,551,555`) and the
  two Brillouin-zone relocations (`:582,587`).
* **Fix.** Both doc comments name the six declarations and the `src/spglib.c`
  lines that write, and say that a search entry point never writes through the
  pointer - which is what `AGENTS.md` section 4 asks for and the old text did
  not. `Cell.mutableTypePtr` also names what the dropped qualifier costs: a
  `Cell.types` is caller storage that may be in read-only data, so a caller that
  must standardise copies into an `OwnedCell`. The same false premise at
  `OwnedCell.mutableTypePtr` went with it. The module doc is now the single
  complete account, and the README points at it.
* **Rule.** A `const` is dropped for a named file and line that writes, never
  for a claim about what a *family* of entry points does; and a list of what a
  facade omits is only worth printing if it was produced by reading every
  declaration, because the omissions that hurt are the ones a reader would
  otherwise assume exist - `niggliReduce` sat next to `delaunayReduce` in the
  export list while only the first had a binding.
* **Targets bound.** Any binding over a C header whose declarations disagree
  about `const`, and any facade whose doc comment enumerates its own
  omissions - `zig/cell.zig` and `zig/root.zig` here.
* **Verification status.** SOURCE-CONFIRMED by reading `include/spglib.h`,
  `src/spglib.c`, `zig/cell.zig` and `zig/dataset.zig`. **OBSERVED-PASS on both
  routes**: the integration owner's probe ran the linked static route and the
  loaded route against an **own dynamically loaded provider** — the
  `libspglib.so` this SDK itself built at
  `/home/tmp2/gertullj/scratch/foundation-libs/native-final-prefixes/contract-final-after-20261004/spglib-dynamic-Debug/lib/libspglib.so`,
  the same own-provider library the loaded sweep opened, **not a downloaded or
  independent one** — **8 of 8 steps each**,
  and every run answered space group **225 Fm-3m**, Hall **523**, **192**
  operations and a **2-atom** primitive cell. Its receipt is
  `/home/tmp2/gertullj/scratch/foundation-libs/spglib-const-cell-evidence-20261005.json`,
  built from the two observed runs. PENDING-VERIFICATION: `smoke`, `check` and
  `check-targets` as whole-SDK gates against the edited source are still owed —
  see the bound below.
* **What changed, and what did not.** The edit is documentation: the two doc
  comments in `zig/cell.zig`, the module doc in `zig/root.zig`, the
  `README.zig.md` escape-hatch paragraph and the consumer-obligation paragraph
  beside it. No exported signature, error set, ABI, cast, macro or preprocessor
  define changed, and no native source, header, upstream test, data byte or
  licence byte changed. The finding was cleared by reading all four files
  named above, which is what `SOURCE-CONFIRMED` means here and was never a
  substitute for a gate. The integration owner's probe is that gate, and it has
  now printed for both routes.
* **The borrowed arrays came back byte-identical, and that is the whole of what
  the comparison establishes.** It is recorded as **unchanged bytes**, not as
  "no write occurred": equal bytes cannot distinguish an array that was never
  written from one written back with the same values, and the six declarations
  above do write. What the probe adds to the source reading is the
  *scientific answer* — the standardisation entry points return the primitive
  cell upstream's own fixture expects — not a claim about the store.
* **What the probe actually covers, and what it deliberately does not claim.**
  It is a direct smoke over the typed surface plus an FFI fixture that reads a
  dataset through `getDataset`'s `const` lattice and then standardises a copy
  through an `OwnedCell`, checking that the borrowed cell is preserved. That is
  the whole of its scope. **It is not a whole-SDK source-identity claim**: the
  runs were direct smokes against this tree while this SDK's Markdown was still
  being written, no build-graph or native byte changed during them, and nothing
  here says they cover a target, an optimize mode or a step they did not run.
  No API type, macro, native source or C cast changed, and the documentation
  correction that started this — the `Cell.mutableTypePtr` /
  `OwnedCell.mutableTypePtr` comments and the module doc's omitted-surface list
  — is landed and accepted against exactly this source.
* **Two compile errors in an earlier private probe were that probe's faults.**
  It stopped first on an absolute zone path and then on `memcpy` types. Both
  were in the probe's own throwaway manifest and bytes helper, not in this SDK;
  the helper was corrected with **no SDK change**, and the corrected probe ran
  directly in 4.12 s. They are recorded here so no future reader mistakes a
  harness error for a library finding.
