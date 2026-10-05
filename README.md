# spglib, packaged as a Zig 0.16 SDK

This repository is a downstream packaging of upstream spglib **v2.7.0**
(commit `12355c77fb7c505a55f52cae36341d73b781a065`) that builds the upstream C
core with Zig **0.16.0** and adds a typed Zig facade over the complete public C
API. It is private and unpublished: nothing here has been pushed to any remote.

Upstream's own README is preserved byte for byte in
[`README.upstream.md`](README.upstream.md) (sha256
`294f6f53da4a096e17ab104f3cc8e2c385f2cbe98e4164ff6c94b717beea9ccc`), and
upstream's release notes are in `ChangeLog.md`, which is not edited here. This
file is the fork's own document and follows a fixed order: what deviates in the
native sources, what deviates in the build, the current support matrix, and how
to consume the result. The Zig interface itself is documented separately in
[`README.zig.md`](README.zig.md).

| Record | What it holds |
| --- | --- |
| `README.upstream.md` | Upstream's README, unmodified |
| `README.zig.md` | The Zig interface: dependency, ownership, errors, build steps |
| `UPSTREAM.md` | The pin, the clone, the sync procedure, the layout map |
| `CHANGELOG.md` | Numbered fork-only divergences, with evidence |
| `FORK-NOTES.md` | Issues met while packaging: condition, cause, fix, rule |
| `NOTICE.md` | Upstream notices, the per-file exception, the modifications |
| `FORK-LICENSE.md` | The owner's grant for fork-authored files |
| `COPYING` | Upstream's BSD 3-Clause text, unmodified |
| `UPSTREAM.sha256` | One SHA-256 digest per carried upstream byte at the pin, with the derivation in its header |

## Native-source deviations

The baseline is the pinned commit `12355c77…`. `src/`, `include/` and
`database/` are byte-identical to it except for **two files**, each changed by
exactly one recorded patch under `patches/`, and `tools/check_provenance.sh`
replays both patches and compares the result byte for byte. No algorithm, table,
numerical constant, header, data file or upstream test was changed.

That covers the C library. This repository also carries upstream's whole
`test/` suite and its functional fixtures, the data tables and their
generators, the Fortran, Python and Ruby bindings, the packaging tests, the
docs tree, the CMake project, the RPM spec under `.distro/`, the remaining
`.github/` config and the root build and tooling files. `UPSTREAM.sha256`
holds a SHA-256 digest for all 725 of those carried paths at the pin, and the
gate runs that record, so a changed byte anywhere in the set fails CI rather
than only one under `src/`, `include/` or `database/`.

Three carried paths are not upstream bytes. The record names each one
explicitly instead of letting it pass as upstream, and carries the pin's own
digest beside it so a reader can tell the fork's bytes from upstream's:

| File | Deviation | How the record shows it |
| --- | --- | --- |
| `src/overlap.c` | The `patches/` entry below | Fork-state digest, with the pin's digest on a `#!pin` line |
| `src/primitive.c` | The `patches/` entry below | Fork-state digest, with the pin's digest on a `#!pin` line |
| `.gitignore` | Upstream's 809 bytes verbatim, then this fork's own entries below a `# Fork additions below` marker | Fork-state digest, with the pin's digest on a `#!pin` line |

The seven upstream workflows under `.github/workflows/` are not carried; their
digests are recorded in `UPSTREAM.sha256` so the omission stays auditable.

| File | Deviation | Patch | Why |
| --- | --- | --- | --- |
| `src/overlap.c` | The order of two internal offsets in one allocation is swapped: `offset_perm_temp` moves after `offset_pos_sorted` | `patches/0001-align-overlap-buffers.patch` | For an odd atom count the `int` array landed on an odd `double` offset, so the buffer lost the alignment its `double` arrays rely on. No algorithm changes, nothing is allocated or padded, and the alignment checks stay enabled. |
| `src/primitive.c` | The `mat_free_VecDBL` call in `get_primitive` (`:246`) is guarded against a NULL argument | `patches/0002-guard-null-pure-translation.patch` | Upstream reaches that call with `pure_trans == NULL` when `sym_get_pure_translation` fails on every attempt, and `mat_free_VecDBL` dereferences its argument (`src/mathfunc.c:402`), so `spgms_get_magnetic_dataset` on a collinear-spin cell was a null dereference. The guard is the idiom the same file already uses at `:399-404`. |

Both deviations predate the 2026-10-04 contract migration and landed with their
own recorded basis in that earlier wave: `CHANGELOG.md` entries 9 and 12 and
`FORK-NOTES.md` carry the evidence for each. They are *not* covered by the later
bounded-portability authorization, which `AGENTS.md` section 4 limits to the
eight additions and explicitly excludes the original seven forks.
**The 2026-10-04 wave added no native-source deviation.**

Two non-source facts belong here because they change what the tree is:

* `src/version.h.in` is upstream and untouched. It is *configured*, not edited:
  `build.zig` writes `version.h` from it at build time, so the header cannot
  claim a release the repository does not contain.
* The only upstream-tree removal outside `src/`, `include/` and `database/` is
  the seven imported `.github/workflows` files. They are the upstream project's
  own CI and two of them publish to the upstream PyPI project and Codecov
  account, which this fork does not own (`CHANGELOG.md` entry 7).

## Native-build deviations and build history

The build is Zig's own C frontend over the 23 upstream translation units. No
CMake, autotools, Make, downloaded upstream copy or installed system spglib is
used by default.

* **Source list** is written out explicitly in `build.zig` rather than globbed,
  so a new upstream translation unit cannot enter the archive unnoticed.
* **Flags** match upstream's own CMake settings: `-std=c11`,
  `-fvisibility=hidden`, `-DSPGINFO`, `-DSPGWARNING`, and `-DSPGDEBUG` in Debug.
  No C flag is restated anywhere else, including in `package.nix`.
* **`SPG_BUILD`** is defined for the core, and `SPG_STATIC_LIBRARY` whenever the
  linkage is static, which mirrors `src/CMakeLists.txt:8-10` and keeps a Windows
  translation from declaring a static archive `dllimport`.
* **Artefact name is `spglib`, not `symspg`.** `build.zig` calls
  `b.addLibrary(.{ .name = "spglib" })`, and `zig/consumer/build.zig` resolves
  `artifact("spglib")`. Upstream's CMake install names the same library
  `symspg` (`CMakeLists.txt:108-113`, `cmake/spglib.pc.in:4`), so this fork's
  installed `spglib.pc` says `-lspglib`; a `-lsymspg` copied from upstream would
  name a library this output does not contain.
* **Linkage**: `-Dlinkage=static` is the default and `-Dlinkage=dynamic` is the
  second delivered variant of the same SDK. In `-fsys=spglib` mode the link is
  `spglib` and it is asked for through pkg-config with `.force`, not written out
  by hand as `-lsymspg`: `module.linkSystemLibrary("spglib", .{
  .use_pkg_config = .force })` is the only spelling this graph uses, and
  `symspg` is upstream's own CMake file name, not a stem this package installs.
  See `README.zig.md`.
* **libm** is linked by the build itself on the platforms where it is a separate
  library (Linux, the BSDs, illumos), and the installed `spglib.pc` carries
  `-lm` for exactly those platforms. The core calls `sqrt`, `fabs`, `sin` and
  `cos`.
* **C sanitization is off** for the core module, and the Zig caller is compiled
  at `ReleaseSafe` when `Debug` is requested. The C library keeps the requested
  optimization and its `-DSPGDEBUG`; this works around a Zig 0.16.0 defect at
  the `extern "C"` call boundary that mis-passes the doubles of a call with
  seven or more integer-class arguments. `FORK-NOTES.md` entry 30 has the
  reproducer and the disassembly, and `CHANGELOG.md` entry 13 has the boundary:
  observed on x86-64 linux-gnu, Zig 0.16.0, nowhere else.
* **Installed layout**, both variants: `lib/libspglib.a` for static;
  `lib/libspglib.so` plus the version and soname links Zig derives from `2.7.0`
  for dynamic;
  `include/spglib.h`; `include/spglib/version.h`; `lib/pkgconfig/spglib.pc`;
  and the licence and provenance material under `share/licenses/spglib/`
  (`COPYING`, `NOTICE.md`, `FORK-LICENSE.md`, `UPSTREAM.md`).
* **No runtime data is installed**, because there is none to install:
  `src/spg_database.c`, `src/msg_database.c` and `src/sitesym_database.c` carry
  the crystallographic tables as compiled-in arrays. Upstream installs no data
  either.
* **No tools are installed.** Upstream installs a library, headers and package
  metadata; `ruby/getspg.c` and `example/c_api` are upstream example sources,
  not install targets.
* **No MSVC.** Nothing in this repository builds or tests `_MSC_VER`. The
  Windows path is MinGW (`x86_64-windows-gnu`) and is compile-only.

Dated build history is `CHANGELOG.md`: twenty-two numbered entries relative to
upstream `v2.7.0`, each stating what changed, why, and what a consumer can
observe. Entry 14 is dated `2026-10-03`, entries 15 through 21 are dated
`2026-10-04` and entry 22 is dated `2026-10-05`; the earlier entries carry their
evidence and boundary statements instead of a date.

## Build, run and test matrix

Five different kinds of statement are kept apart here. The first table is what
was observed in this repository before this wave. The second is the source-bound
53-cell matrix and the compile-only baseline, both taken against one recorded
source identity. The third is what a gate observed against the current tree. The
fourth is what a gate observed earlier today, against the source as it stood
then. The last list is what is still unobserved. A row is a verification of the
tree it names and of nothing else.

### Historical observations, before the 2026-10-04 wave

All rows below are `x86_64-linux-gnu` with Zig 0.16.0, recorded in this
repository's own history, not run for this README.

| What | Where it was recorded | Status |
| --- | --- | --- |
| Library, module and headers build and install | `CHANGELOG.md` entry 14 | OBSERVED |
| `zig build test` in Debug and in ReleaseSafe, agreeing | `FORK-NOTES.md` entry 30 | OBSERVED — the last recorded count is 52 of 54, up from 41 of 54 before the Debug workaround; that note does not say what the remaining two were, and the count this wave observed is in the table below |
| `zig build smoke` | `CHANGELOG.md` entry 14 | OBSERVED |
| `zig/consumer` package run, and the module example it exercises | `CHANGELOG.md` entry 14 | OBSERVED |
| `zig build check` | `CHANGELOG.md` entry 14 | OBSERVED |
| `zig build check-targets`, six compile-only targets | `CHANGELOG.md` entry 14 | OBSERVED as compilation only; a foreign compile is not a passing test |
| `tools/check_provenance.sh` against the pin | `UPSTREAM.md`, verification status | OBSERVED once, green, with both patches in place |
| `UPSTREAM.sha256`: all 725 carried upstream paths hash to the pin | `UPSTREAM.md`, verification status | OBSERVED green on 2026-10-04, together with eleven deliberate tamperings the gate rejected; no CI run observed |
| `tools/derive_upstream_sha256.py` reproduces the committed record | `UPSTREAM.md`, verification status | OBSERVED on 2026-10-04: byte-for-byte identical at the same pin |

### The source-bound 53-cell matrix and baseline, 2026-10-04/05

One external driver ran this SDK's 53 platform cells at `-j8`, and a second
ran the compile-only baseline. Both receipts carry the same source identity, and
that identity is the boundary of every number below.

| Gate | Receipt | Result |
| --- | --- | --- |
| 53-cell platform matrix | `resume-8-evidence/20261004T221720228710Z-45046/spglib-53-target-8.json` | **53 cells, `pass 20`, `build_only 33`, `build_fail 0`, runtime `fail 0`, run exit 0.** All 53 targets built. 20 executed this SDK's tests and passed; the other 33 compiled and were not run, because no runner was available for them |
| Compile-only baseline | `baselines-and-configs/20261005T014547Z-797a73f2/receipts/baseline-spglib-check-targets-2026-10-05T01-45-58Z.json` | exit 0, `failed: false`. `check-targets` compiles; it runs nothing, so it is compile evidence and no test number may be read out of it |
| Native route, 8 cells | `native-final-evidence/20261004T233628757747Z-69351/run.json` | 8 of 8 passed |
| Own-provider loaded route, 8 cells | `loaded-final-evidence/20261004T232823091897Z-23133/run.json` | 8 of 8 passed, against this SDK's own shared object |

`build_only` is compiled-not-run and is **never** counted as a test pass: 33 of
the 53 cells are coverage of the compiler, not evidence about behaviour. This
SDK has no `build_fail` and no runtime `fail` in that matrix, and that is the
whole of its success — it is not a claim about any other SDK, about any
optimize mode other than the one the driver selected, or about this working
tree today.

**What this matrix does not cover.** The 53-cell run predates the later
build-graph, header and normalization edits, and the receipt's
`source_unchanged: true` speaks only to its own run. Those edits are not
retroactively covered by it, and neither this README nor `CHANGELOG.md` claims
they are. The `symspg` link-name corrections made with them — in `README.md`,
`README.zig.md`, `CHANGELOG.md` entry 5 and `FORK-NOTES.md` entry 4 — and the
consumer-obligation paragraph under "Escape hatch" are read against the sources
at this pin and are `SOURCE-CONFIRMED`, not gate results. The one thing that
**has** since been exercised is the obligation itself: a direct probe answered
8 of 8 steps on the linked static route and 8 of 8 on the loaded route against
an **own dynamically loaded provider** — the `libspglib.so` this SDK itself
built, at `…/native-final-prefixes/contract-final-after-20261004/spglib-dynamic-Debug/lib/libspglib.so`,
the same own-provider library the loaded sweep opened, not a downloaded or
independent one — every run giving space group 225 Fm-3m, Hall 523,
192 operations and a 2-atom primitive cell, with the borrowed input's bytes
unchanged afterwards. "Unchanged bytes" is the whole of that claim — equal bytes
cannot show that nothing was written — the fixture reads a dataset through
`getDataset`'s `const` lattice and then standardises a copy through an
`OwnedCell`, and **it is not a whole-SDK source-identity claim**. Its receipt is
named in `FORK-NOTES.md` entry 37.

### Observations against the current tree, 2026-10-04

Sixteen gates, all `x86_64-linux-gnu` with Zig 0.16.0, all exiting 0 between
15:13 and 15:21 UTC, each started from this directory with `-j8` and
`--summary all`. In the tables below `<scratch>` is
`/home/tmp2/gertullj/scratch/foundation-libs/contract-physics-lua`; each receipt
is a JSON file under `<scratch>/current-native-evidence/` and each is indexed in
the integration owner's `foundation-current-native-index.json`.

| Gate | Command | What its receipt shows |
| --- | --- | --- |
| `spglib-current-native-<linkage>-<mode>`, 8 gates: `static` and `dynamic`, each in `Debug`, `ReleaseSafe`, `ReleaseFast` and `ReleaseSmall` | `zig build test smoke install -Druntime=false -Dlinkage=<linkage> -Doptimize=<mode> --prefix <scratch>/spglib-static` or `<scratch>/spglib-shared` `-j8 --summary all` | 23/23 steps; `test` 55 of 55 (`testfacade_test` 34, `testc_api_test` 11, `testapi_surface` 10); `smoke` printing the linked provider's answers; `install` writing the requested library |
| `spglib-current-loaded-<linkage>-<mode>`, the same eight | the same command with `-Druntime=true` and `--prefix <scratch>/spglib-loaded-static` or `<scratch>/spglib-loaded-dynamic`, with `SPGLIB_TEST_PROVIDER=<scratch>/spglib-shared/lib/libspglib.so` | 24/24 steps: the same 55 of 55; `smoke` printing `loaded provider`; and a build summary that lists `run exe spglib-runtime-generate-x86_64-linux…` as a real step, so the generator ran over the translation step's own output |

The provider those eight loaded gates opened is this SDK's own
`-Dlinkage=dynamic` install from the same day, in the prefix the native dynamic
gates wrote. These are therefore own-provider gates: both linkages and all four
optimize modes, the linked route and the loaded route, and — in the four
prefixes on disk — the installed layout the Consumption section documents:
`include/spglib.h`, `include/spglib/version.h`, `lib/pkgconfig/spglib.pc`, the
four licence records under `share/licenses/spglib/`, `libspglib.a` for the
static linkage and `libspglib.so` with its `.so.2` and `.so.2.7.0` for the
dynamic one. The two `spglib.pc` files are the two forms described there: the
static one carries `-lm` in `Libs` and `-DSPG_STATIC_LIBRARY` in `Cflags`, the
dynamic one carries `-lm` in `Libs.private` and neither extra, and both are
`${pcfiledir}`-based.

These sixteen receipts describe the source as it stood while they ran.
`build.zig`, `build.zig.zon`, `package.nix`, `runtime/graph.zig` and
`zig/consumer/build.zig` have been edited since, so both routes are owed a
replay against the frozen handoff; a replay that fails replaces these rows
rather than adding to them.

### Nested consumer delivery, 2026-10-04

Nine cases, all on this host's `x86_64-linux-gnu` with Zig 0.16.0, started from
this directory at 22:31 UTC through one nested-delivery driver. Its receipt is
the `index.json` under `<proof>/evidence/<epoch>/`, where `<proof>` is
`/home/tmp2/gertullj/scratch/foundation-libs/nested-delivery-proof` and `<epoch>`
is `20261004T223101807175Z-ca145a8dcf4a`. Every case reports `PASS`, the run
reports 9 of 9 passed with 0 boundary and 0 non-pass, and the driver itself
exited 0.

| Case | What its receipt shows |
| --- | --- |
| `nested-default-linked-static`, `nested-default-linked-dynamic`, `nested-default-loaded-static`, `nested-default-loaded-dynamic` and the same four `nested-explicit-*` names | The nested command line the outer one produced: `-Dtarget=native -Dcpu=native` for the default selection and `-Dtarget=x86_64-linux-gnu -Dcpu=baseline` for the explicit one, `-Doptimize=ReleaseSafe` from an outer `-Doptimize=Debug`, `-Druntime` and `-Dlinkage` written out in both directions, `-fno-sys=spglib` in place of the omitted `-fsys=spglib`, `-j8`, `--summary all`, `--cache-dir <outer>/consumer`, the caller's `--global-cache-dir` unchanged, and `--prefix` carrying the caller's own prefix. The four linked cases exit 0 and print the answers the earlier consumer table records. The four loaded cases exit 0, are given `-- --scratch <abs> --provider <abs>` after the `--`, and load the shared object named there |
| `nested-no-provider` | `-Druntime=true` with no provider given and `SPGLIB_TEST_PROVIDER` absent from the child environment, which the driver records as deliberately absent. The program runs, exits 1 and prints the refusal its own source declares. That refusal is the expected result, and the case passes on it |

So the provider reaches the program as a flag and never as an environment
variable: no loaded case can be passing on an inherited variable, because none
was inherited.

That same receipt also carries a `status_note` string reading that the driver
has never been executed. Its own records contradict that string: every case has
`compiler_started` true, `started_utc` and `finished_utc`, an exit code, a build
summary and matched program output, and the run totals read `SOURCE_ONLY_PLAN` 0
with `plan_only` false.

What this evidence does not cover: a WASI cell with `-fwasmtime`, a foreign cell
with `-fqemu --libc-runtimes`, and a `-fsys=spglib` cell. All nine cases are this
host's own target, so the external-executor arms of `hostCanExecute` and the
system mode remain unobserved, and the Pending verification list below is
unchanged apart from the cells named here.

### Observations from earlier on 2026-10-04, against the source as it stood then

These were run before the runtime generator and the later build work landed.
Each is recorded with what it printed; none of them verifies the current tree,
and none is re-claimed by the table above.

| What | Command | Exit | What it observed |
| --- | --- | --- | --- |
| Consumer package on its own, four configurations | `zig build run -Druntime=false` or `-Druntime=true`, with `-Dlinkage=static` or `-Dlinkage=dynamic`, in `zig/consumer`, and `SPGLIB_TEST_PROVIDER` naming this SDK's own `<scratch>/spglib-shared/lib/libspglib.so.2.7.0` | 0, four times | The exported module and artifact consumed by a separate package that depends on this one by path. Each run printed `spglib 2.7.0, linked provider` or `loaded provider`, then the same answers: space group 221 Pm-3m, 48 operations, a 5-atom primitive cell, Hall 517 is Pm-3m (Oh^1), and `spg_get_spacegroup_type(460)` = 167 R-3c through the raw C entry point, at 8/8 steps |
| The same consumer in a copy of this package under the scratch tree | `zig build run -Dlinkage=static -Druntime=false` in `<scratch>/fetched-consumer/spglib` | 0 | The same answers from a tree that is not this working directory. It is a copy, not a registry fetch: this package has no URL or hash to fetch from |
| Nix flake evaluation | `nix eval --json --impure --expr …` over `packages.x86_64-linux` | 0 | `names` = `default`, `shared`, `static`; `passthru.linkage` per variant; `nativeBuildInputs` reporting Zig 0.16.0 |
| Nix build of both derivations | `nix build --no-link --print-out-paths -L path:/vol/fob-vol7/mi19/gertullj/foundation-libs/spglib#static path:/vol/fob-vol7/mi19/gertullj/foundation-libs/spglib#shared` | 0 | Both derivations, each running `zig build install` and its own post-install layout check. Both were built on `x86_64-linux`, and both predate the `-Dtarget` `package.nix` now derives from `stdenv.hostPlatform`, so they are observations of the derivation as it was then |
| devenv lazy outputs | `devenv --from path:/vol/fob-vol7/mi19/gertullj/foundation-libs/spglib --no-tui eval packages outputs.static.drvPath outputs.shared.drvPath outputs.default.drvPath` | 0 | The three lazy attributes evaluate, and the shell's package set is Zig 0.16.0, `patch` and `git` |
| Compile-only analysis | `zig build check` | 0 | The library, the facade, the tests and the example compile with nothing run |
| Pinned-byte record in this working tree | `sha256sum --check --strict UPSTREAM.sha256` | 0 | The committed record matches this working tree. That is the weaker of the two provenance questions: it does not re-derive the record from the pinned commit, which `tools/check_provenance.sh` does |
| Installed-C probe | `zig cc -std=c11 -O2 -Wall -Werror -I/home/tmp2/gertullj/scratch/foundation-libs/contract-physics-lua/relocated/spglib/include -L/home/tmp2/gertullj/scratch/foundation-libs/contract-physics-lua/relocated/spglib/lib -lspglib -Wl,-rpath,/home/tmp2/gertullj/scratch/foundation-libs/contract-physics-lua/relocated/spglib/lib /home/tmp2/gertullj/scratch/foundation-libs/contract-physics-lua/installed-c/spglib.c`, then the resulting binary | 1, then 0 | Two receipts from two probe revisions, not one build followed by one run. The exit-1 build is an older revision that called `spglib_get_version`, a name this library does not declare — `include/spglib.h:196` declares `spg_get_version`; it predates the file now at that path. The exit-0 run is a later revision that printed `spglib 2.7.0`, and its source is not the file now at that path either. The current revision — a real symmetry search against answers pinned from upstream's functional tests, both ownership rules, both failure paths — has neither a build nor a run receipt, so this row records a probe defect that was fixed, not a passing proof |
| Fetch | `zig fetch --global-cache-dir /home/tmp2/gertullj/cache/foundation-libs/contract-physics-lua/global /home/tmp2/gertullj/scratch/foundation-libs/contract-physics-lua/fetch-src/spglib-static` | 1 | An expected refusal, not a pass and not a hosted proof: `zig fetch` is a real subcommand in this compiler and it diagnosed its argument as neither an existing file path nor a URL (`FileNotFound`, `InvalidFormat`) |

### Pending verification

Everything below is `PENDING-VERIFICATION`: the source states it and no gate
recorded above has observed it. A correction that lands is not a result. The
integration owner records what a gate printed — command, target, optimization
mode, exit code, date, receipt — and moves an item out of this list then. An
item with no observation is not a boundary, and nothing here is a permanent
exclusion.

* Any foreign **execution**. `x86_64-windows-gnu`, `aarch64-macos-none`,
  `riscv64-linux-gnu`, `wasm32-wasi` and `aarch64-linux-gnu` are compiled, not
  run. The 53-platform matrix is run by the integration owner rather than by
  this repository's CI, and its 53 cells are recorded above; what is still owed
  is a **replay of those 53 cells against the current source**, because the run
  recorded there predates the later build-graph, header and normalization
  edits.
* `-fsys=spglib` against a real installed spglib. Nothing here has one, and the
  fork's own CI runner has none either. The pair `-fsys=spglib` with
  `-Druntime=true` is refused by design, and the refusal branch itself has never
  been taken by a gate.
* Any MSVC build.
* A hosted fetch, and therefore any fetch identity: this package has no
  published URL and no content hash, so only a `.path` dependency resolves.
* A Nix build for a system other than the one it was built on. `flake.nix`
  exposes `x86_64-linux`, `aarch64-linux`, `x86_64-darwin` and `aarch64-darwin`,
  and `package.nix` derives its `-Dtarget` from `stdenv.hostPlatform`, so each
  derivation builds for the system it is for; the derivation's post-install
  phase still checks names and link metadata rather than machine code. The only
  observed Nix builds are the two `x86_64-linux` ones recorded above, and they
  predate the `-Dtarget` derivation, so the other three systems are owed a
  build each.
  The ABI component of that triple is `hostPlatform.isMusl`, the attribute the
  pinned nixpkgs derives from `hostPlatform.parsed.abi`, so a musl package set
  builds `…-linux-musl` and every other one `…-linux-gnu`; Darwin takes `none`.
  `package.nix` names no libc attribute of its own, and that nixpkgs revision
  has no `linuxLibc` to name.
* The fork's CI workflow itself. `.github/workflows/zig-fork-ci.yaml` defines the
  provenance, native, cross, consumer and delivery jobs; no run of it is
  observed here.
* `devenv shell` entered as a shell. `devenv.nix`'s three lazy output
  attributes evaluated; the shell itself was not entered.
* The installed-C proof in its current form. `zig build check-targets`, the six
  compile-only targets and `tools/check_provenance.sh` are covered by the
  historical table above, but nothing has run the current probe, or upstream's
  own `example/c_api/example.c`, against a freshly installed prefix through the
  installed `spglib.pc`. The probe asserts one string per route, and those are
  the strings a receipt is matched against rather than read by eye: for the
  installed-C route, `spacegroup 136 P4_2/mnm, Hall 419, point group 4/mmm, 32
  operations, 12 atoms, closed under composition, species-preserving`; for an
  external provider named by path,
  `rutile supercell -> spacegroup 136 P4_2/mnm, Hall 419, point group 4/mmm, 32
  operations, 12 atoms, closed under composition`. Every number behind them is an
  upstream assertion — the 12-atom rutile fixture and its answers in
  `test/functional/fortran/test_fortran_spg_get_dataset.F90:42-77`, the Hall 419
  type in `test_fortran_spg_get_spacegroup_type.F90:40-69` — not something the
  probe computes and compares with itself. A `system`-named provider is expected
  to refuse here: this host has no installed `spglib` and no `symspg`, so
  `OpenFailed` and a non-zero exit are the recorded outcome, and an absent
  external route is neither a pass nor a defect.

## Consumption

### From Zig, linked

The interface, ownership rules, error mapping and every build step are in
[`README.zig.md`](README.zig.md). The short version, which is also the complete
mechanism:

```zon
// build.zig.zon
.dependencies = .{
    .spglib = .{ .path = "../spglib" },
},
```

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

`dep.module("spglib")` links the compiled library; code that compiles its own C
against `spglib.h` also wants `dep.artifact("spglib")`, which carries the
installed include path. `zig/consumer/` is that arrangement as a separate
package, and `zig build consumer` drives it from the root.

There is **no published URL and no content hash** for this package, so a `.path`
dependency is the arrangement that resolves without credentials. Nothing in this
repository should be read as a publication receipt.

### From C, against an installed library

```
lib/libspglib.a                                      # -Dlinkage=static
lib/libspglib.so, plus .so.2 and .so.2.7.0           # -Dlinkage=dynamic
include/spglib.h
include/spglib/version.h
lib/pkgconfig/spglib.pc
share/licenses/spglib/{COPYING,NOTICE.md,FORK-LICENSE.md,UPSTREAM.md}
```

`spglib.pc` is relocatable (`${pcfiledir}`-based), so it works under any
`--prefix` and from a store path. Two of its lines carry a real decision. The
static variant's `Libs` carries `-lm` on the platforms where libm is a separate
library, because a consumer that links the archive performs spglib's own
`sqrt`/`fabs`/`sin`/`cos` calls itself; the shared object recorded them when it
was linked, so there `-lm` is `Libs.private` instead. And the static variant's
`Cflags` adds `-DSPG_STATIC_LIBRARY`, mirroring upstream's own PUBLIC define for
a Windows static build (`src/CMakeLists.txt:8-10`), without which a Windows
consumer would see `__declspec(dllimport)` on every declaration.

### Nix and devenv

`package.nix` is one source-only definition that returns one derivation; the
linkage variant comes from the caller. `src` is this directory without build,
VCS and development state, the only build command is `zig build install`, and
there is no fetch, no `../` import, no host path and no sibling SDK. Its
post-install phase verifies the installed layout instead of writing it, so a
plain `zig build install` and the derivation produce the same tree.

```sh
nix build .#static                 # the SDK's native default
nix build .#shared                 # the dynamic variant
devenv shell                       # canonical development, tools only
devenv build outputs.static        # the same two derivations from devenv
devenv tasks run sdk:test -- -Doptimize=Debug
```

`devenv.nix` keeps the SDK out of `packages` — Zig 0.16.0, `patch` and `git`,
plus an assertion that refuses any other Zig — and exposes it as the lazy
`outputs.static` and `outputs.shared`, so entering the shell never builds the
library. `flake.lock` is the integration owner's file, and it pins the nixpkgs
revision `flake.nix` names together with its resolved `narHash`. There is no
`devenv.lock`: `devenv.yaml` pins its own nixpkgs input by revision instead, and
`build.zig.zon`'s `.paths` no longer lists a file the tree does not have.

Every task names this directory before it runs anything, from the module itself
(`builtins.toString ./.`, quoted with `lib.escapeShellArg`): devenv materialises
a task as a generated program that inherits the *caller's* working directory, so
a task run from a scratch project would otherwise invoke `zig build` where there
is no `build.zig` and `tools/check_provenance.sh` where there is no `tools/`.
Every task that reaches `zig build` resolves an external cache directory before
the compiler starts, from one shared line in `devenv.nix`: an exported
`ZIG_LOCAL_CACHE_DIR` is taken exactly as it stands, else `XDG_CACHE_HOME`, else
`$TMPDIR`, and the task stops and names the three when the caller exported none
of them. There is no `.zig-cache` fallback into this checkout and no `/tmp`
default; `ZIG_GLOBAL_CACHE_DIR` is left to the caller. All seven build tasks
then run `zig build <step> --cache-dir "$cache" -j8 --summary all "$@"`, the
flags after the step and any `--prefix` and before `"$@"`, so a caller's own
arguments stay the last word and can still override the explicit cache.
`sdk:build` is the one task whose command installs — `zig build` runs the default
install step, which writes the library, both headers, `spglib.pc` and the
licence material — so it installs into `$SPGLIB_INSTALL`, else
`<resolved base>/spglib/zig-out`; no branch of it writes a `zig-out/` inside this
checkout. The other tasks install nothing and take no `--prefix`: they run
`zig build test`, `smoke`, `check`, `check-targets`, `consumer` and `fmt-check`
from the SDK root, with `"$@"` as before. `sdk:consumer` drives the consumer's
own nested `zig build` inside `zig/consumer`. That nested build is a second
graph, so no devenv task can put a flag on its command line. `runConsumer` in
`build.zig` writes them instead, and it now carries `-j8` and `--summary all`
as well, `--cache-dir <outer>/consumer` when the outer build was given an
explicit cache directory, the caller's `--global-cache-dir` unchanged when the
outer build named one, `--prefix` when the resolved install prefix is not the
default, and the caller's own trailing arguments behind `--`.

### Runtime loading

One facade, two configurations. **Linked** is the default and every native call
is direct. `-Druntime` — a boolean build option, default false — selects the
route where the same facade reaches the selected native entry points through
one process-lifetime table instead. `@import("spglib")` does not change: the
generated dispatch re-exports the translated namespace, so
`spglib.c.SpglibDataset` is the same nominal type in both configurations and
every existing `pub fn` keeps its meaning.

`-Druntime` and `-Dlinkage` are orthogonal and all four combinations are legal,
delivering an artifact in each case, with identical headers and licence
material and the same `spglib.pc` apart from the two lines the linkage decides.
All four installed trees are on disk and the matrix above is what produced them.

The route does **not** imply a loadable file: under
`-Druntime=true -Dlinkage=static` this tree installs only `libspglib.a`, so a
provider has to come from elsewhere; under `-Dlinkage=dynamic` the tree builds
the shared object a caller may name. `-fsys=spglib` is refused together with
`-Druntime=true`, and the build says so in one message: the installed
`spglib.h` carries no version macros, and the dispatch validates a provider
against the generated `version.h` this repository's own build produces. There is
no system-mode runtime route.

On the facade module:

* `pub fn load(source: LoadSource) LoadError!void` — explicit load; a call
  before a successful load panics in every optimize mode.
* `pub fn loadedSource() ?LoadSource` — the provider that was actually opened,
  or `null` on a linked build.
* `pub const runtime_loaded: bool`.
* `LoadSource` is `union(enum) { path: []const u8, system: []const u8 }`;
  `LoadError` is `error{EmptySource, SourceTooLong, UnsupportedTarget,
  OpenFailed, MissingSymbol, ValidationFailed, ProviderMismatch, ReentrantLoad}`.
  Both are the same nominal types in either configuration, so a consumer names
  one type whichever build it links.
* On a linked build `load` panics naming the library and `loadedSource()` returns
  `null`.

**Selecting a provider is explicit.** `.path` reaches the platform loader
unchanged and `.system` reaches it as a name; there is no fallback between them
and no preferred name. The installed `libspglib.so`, its soname
`libspglib.so.2` and the real file `libspglib.so.2.7.0` are all valid `.path`
values; `libspglib.so.2` is a valid `.system` value.

**What a provider must export.** The whole declared surface — 59 `SPG_API`
functions — not the subset the typed facade happens to call, with one documented
exception. Two of them are declared and defined nowhere in this tree:
`spg_get_grid_points_by_rotations` (`include/spglib.h:544-546`) and
`spg_get_BZ_grid_points_by_rotations` (`:551-554`), whose `size_t` twins are
what `src/spglib.c:945,955` define. They are named in `provider_optional`, and
in a loaded build that list is a route rather than a link. `runtime/graph.zig`
passes each name to the generator with `--optional`, `runtime/generate.zig`'s
`Options.routeOf` turns that into the optional route, and the generated dispatch
then gives each one a nullable table field that starts `null` and appears in
`optional_symbols` rather than in `symbols`. A provider that does not export
them therefore still loads, and their absence is never a `MissingSymbol`; the
first call to one reaches
`table.<name> orelse requireAvailable("<name>", "<name>")`, which is a
`std.debug.panic` naming the library, the symbol the provider lacks and the fact
that this provider is not the library the build describes. In a linked build
there is no dispatch: both names stay unreferenced `extern` declarations in the
translated namespace, which nothing in this package calls and which therefore
cost the linker nothing. No data symbol is exported: all 59 are functions, and
the crystallographic tables are `static` arrays inside the library.

**The ABI boundary**, all four structural, from `runtime/library.zig`:

* **Struct layout.** `SpglibDataset` (`:115-141`) and `SpglibMagneticDataset`
  (`:158-185`) come back as pointers to provider-allocated memory whose twenty-odd
  fields the caller reads directly. A layout mismatch produces a dataset that
  looks complete and is nonsense rather than a crash. No macro, configure test
  or conditional typedef touches those structs.
* **By-value struct return.** `spg_get_spacegroup_type` (`:428`),
  `spg_get_spacegroup_type_from_symmetry` (`:341`),
  `spg_get_magnetic_spacegroup_type` (`:434`) and
  `spg_get_magnetic_spacegroup_type_from_symmetry` (`:345`) return an 80-to-110
  byte struct by value, past the register-return limit on every ABI this SDK
  targets, so the hidden-return-pointer convention has to match as well.
* **Scalar widths.** `int` for counts, `double` for tolerances and coordinates,
  and `size_t` for the `spg_get_dense_*` family while its `int`-returning twin
  returns `c_int` (`:493`, `:517`, `:535`) — the one width difference inside
  the surface.
* **Allocator ownership.** There is no allocator hook and no allocator argument
  anywhere in the header. Every provider-allocated result is released by the
  matching `spg_free_dataset` (`:244`) or `spg_free_magnetic_dataset` (`:245`)
  *from the same provider*. The loader holds exactly one provider for the life
  of the process and refuses a second, so a `Dataset` cannot cross a provider
  boundary; that is what makes the rule hold instead of being a convention.

**Not part of the boundary:** `SPG_API` itself (`include/spglib.h:12-27`), which
decides which symbols are visible and not what any of them mean; `SPG_DEPRECATED`
(`:35-48`); and the internal `GRID_ORDER_XYZ` / `GRID_BOUNDARY_AS_NEGATIVE`
(`src/kgrid.c:87,112,122`), which change which grid point an address maps onto —
provider behaviour, not a visible ABI difference. The provider's optimize mode
matters not at all, because nothing in the public header depends on it.

**Symbol visibility.** `SPG_API` is `__attribute__((visibility("default")))`
when the library itself is being built and the compiler is not MSVC, and empty
otherwise; a shared build here defines `SPG_BUILD`, so an ELF or Mach-O object
exports the surface and a static archive needs no export attribute. On Windows
that export branch is `_MSC_VER`-only, so **a MinGW-built DLL carries no explicit
export list** and a provider there has to export its entry points itself;
nothing in this repository is built or gated under MSVC.

**External ABI families.** ELF with glibc (Linux) and Mach-O (macOS) are what
this build produces; PE/COFF comes from the MinGW path with the export
limitation above. `include/spglib.h:51` includes `<stddef.h>` and nothing else,
which is the only C library door in the surface.

**What a load actually checks.** Three calls run after every symbol resolves and
before anything is published, none taking a cell and none allocating: the
major/minor/micro versions must equal the translated header's
`SPGLIB_MAJOR_VERSION`/`MINOR`/`MICRO`, `spg_get_version()` must return exactly
`SPGLIB_VERSION`, and `spg_get_spacegroup_type(1)` must answer space group 1 at
Hall number 1 with the symbol `P1` — an independent known answer from the
International Tables. That last one is a by-value struct return, so it is the
only check that observes a calling convention. Resolving symbols and
translating a header are the boundary, not proof of compatibility: no load-time
check inspects the `SpglibDataset` layout, because producing one needs a cell
and a successful symmetry search. That is the caller's business.

Status: the route's own source is complete, and this SDK's own dynamic build
has been loaded through it. `build.zig` declares the switch and wires the seam
— `runtime/graph.zig`'s `createModule` in place of the single
`translate.createModule()` call in `addSpglib`, with the same target and the
same optimize mode the facade module is created with, so the generated dispatch
inherits the Debug extern-call workaround — and `zig/consumer/build.zig`
forwards its own `-Druntime` in both directions. All six runtime files are in
the tree: `graph.zig`, the build-side graph; `generate.zig`, the host generator
that `fn generateDispatch` builds for the target being built and runs over that
target's own translation output; `loader.zig`, the loader core;
`library.zig`, the descriptor that names what a provider must export; and the
two-file `sync.c` / `sync.h` shim the dispatch calls back through. The eight
`spglib-current-loaded-*` gates in the matrix ran this route in both linkages
and all four optimize modes, with the generator as a visible build step, against
the source as it stood when they ran; the replay that section names is owed
against the current source.

What is still unobserved on this route is listed under Pending verification
above, and none of it is this route's own source: a provider this SDK did not
build, a foreign target, and `-fsys=spglib`, which is refused rather than
implemented. The fork's CI delivery job installs and compile-checks the runtime
route under both linkages, so a red runtime job there would be a real failure of
the tree rather than a missing file.

## Licence

Upstream spglib is BSD 3-Clause; `COPYING` is upstream's text, carried
unmodified, and `NOTICE.md` records the notices, the per-file exception
(`src/base.h` carries no SPDX identifier upstream) and every modification this
fork makes. Fork-authored files carry their own grant in `FORK-LICENSE.md`:
`BSD-3-Clause`, authorized directly by the repository owner on 2026-10-04 to
match the primary upstream terms. No individual copyright holder is invented,
and upstream's authors are not credited with anything this fork wrote.

Private hosting removes no obligation. Every installed copy carries
`COPYING`, `NOTICE.md`, `FORK-LICENSE.md` and `UPSTREAM.md` under
`share/licenses/spglib/`, and `tools/check_provenance.sh` fails if the licence
text, an SPDX identifier or a recorded patch stops matching.