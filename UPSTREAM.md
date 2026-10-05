# Upstream provenance

| Field | Value |
| --- | --- |
| Canonical repository | <https://github.com/spglib/spglib.git> |
| Pinned release | `v2.7.0` |
| Pinned commit | `12355c77fb7c505a55f52cae36341d73b781a065` |
| Release commit subject | `Release v2.7.0 (#628)` |
| Upstream default branch | `develop` |
| This fork's branch | `main`, branched at the pinned commit |
| Clone method | Full `git clone`, upstream history preserved |
| `upstream` remote | `https://github.com/spglib/spglib.git` |
| `origin` remote | `https://github.com/CoffeeImpliesCode/spglib.git`, the downstream |
| SPDX identifier | `BSD-3-Clause` (see `COPYING`) |

The commit, its subject and the tag are read out of this clone: the tag `v2.7.0`
resolves to the pinned commit, and `main` is still at it.
`tools/check_provenance.sh` re-checks the pin plus both recorded patches,
`patches/0001-align-overlap-buffers.patch` and
`patches/0002-guard-null-pure-translation.patch`, on every CI run, and since
2026-10-04 also re-checks that `README.upstream.md` still matches upstream's
README at this pin byte for byte. All other files in `src`, `include` and
`database` must match the pin.

Since 2026-10-04 that is no longer the whole obligation. `UPSTREAM.sha256`
records a SHA-256 digest for every upstream byte this repository carries at the
pin -- all 725 paths: the C core and its headers, the public header, the
generated-table inputs, the data tables, upstream's whole test suite and its
functional fixtures, the Fortran, Python and Ruby bindings, the docs tree, the
CMake project, the packaging tests, the RPM spec, the licence text and the
uncompiled build and tooling files. `tools/check_provenance.sh` runs that
record, so a changed byte anywhere in that set fails CI, not only one under
`src`, `include` or `database`. The record's digests were derived from the
pinned commit's git objects by `tools/derive_upstream_sha256.py`, never from
this working tree, and that script reproduces the file byte for byte at this
pin.

Nothing here records a service query. No release-listing API call, no remote
existence check and no publication receipt is part of this file: `origin` is
configured, which records an intention and not an outcome, and the downstream
repository is a private one whose URL and content hash are unconfirmed.

## Layout of this repository

Everything under `src/`, `include/`, `test/`, `database/`, `example/`,
`fortran/`, `python/`, `ruby/`, `docs/`, `cmake/`, `.distro/`, the upstream part
of `.github/`, `CMakeLists.txt`, `CMakePresets.json`, `pyproject.toml`, the
root editor and CI dotfiles, `ChangeLog.md`, `CITATION.cff`,
`Contributing.md` and `COPYING` is upstream content, unmodified except where
this file and `CHANGELOG.md` say otherwise. Upstream's `README.md` is also
upstream content, preserved byte for byte under the name `README.upstream.md`;
`README.md` itself is now this fork's own document, written on 2026-10-04.

The exhaustive list of those paths, one line each with a digest, is
`UPSTREAM.sha256`; this paragraph describes the shape and the record enumerates
the bytes. Three carried paths are forked rather than upstream and the record
names them as such: `src/overlap.c` and `src/primitive.c`, which differ from the
pin by the two recorded patches, and `.gitignore`, which keeps upstream's 809
bytes verbatim and appends this fork's own entries below a marker. The record
carries each one's upstream digest separately, so a reader can tell the fork's
bytes from upstream's.

The seven upstream workflows under
`.github/workflows` are not carried. They are the upstream project's own CI, and
two of them publish to the upstream PyPI project and Codecov account, which this
fork does not own. `CHANGELOG.md` entry 7 names them, and `UPSTREAM.sha256`
records their digests so the omission stays auditable. They remain in the
upstream repository and in the imported history.

| Path | Purpose |
| --- | --- |
| `build.zig`, `build.zig.zon` | Zig 0.16 build, module and artifact exports |
| `zig/root.zig` and `zig/*.zig` | Public Zig facade and the `c` escape hatch |
| `zig/tests/` | Behaviour tests, raw-C tests, public-surface coverage |
| `zig/examples/smoke.zig` | Runnable example behind `zig build smoke` |
| `zig/consumer/` | Separate package that consumes the exported module |
| `tools/check_provenance.sh` | Licence, SPDX and pinned-source integrity gate |
| `UPSTREAM.sha256` | One SHA-256 digest per carried upstream byte at the pin, with the pin, the path set, the counts per area and the derivation in its header |
| `tools/derive_upstream_sha256.py` | Regenerates `UPSTREAM.sha256` from the pinned commit's git objects |
| `README.zig.md` | Usage documentation for the Zig package |
| `README.md` | This fork's own README: native-source deviations, native-build deviations and their history link, the support matrix with its evidence status, and consumption |
| `README.upstream.md` | Upstream's `README.md`, preserved byte for byte at the pinned commit; upstream content, not fork-authored |
| `FORK-LICENSE.md` | The owner's grant for the files this fork authored, with the SPDX identifier |
| `package.nix` | The one source-only package definition, consumed by both `flake.nix` and `devenv.nix` |
| `flake.nix` | `packages.<system>.static` and `.shared` over that definition, plus an optional dev shell |
| `devenv.nix`, `devenv.yaml`, `.envrc` | The canonical development environment and its pinned input |
| `CHANGELOG.md` | Numbered fork-only divergences |
| `NOTICE.md` | Upstream notices and the modifications made here |
| `FORK-NOTES.md` | Issues met while packaging, with fixes and rules |
| `.github/workflows/zig-fork-ci.yaml` | This fork's only CI workflow; the imported upstream workflows are removed (see `CHANGELOG.md` entry 7) |

## Upstream sources that are generated

`src/version.h.in` is the only configured header. Upstream fills it in with
CMake's `dynamic_version()` helper, which reads `git describe` at configure
time. The Zig build configures the same template from two checked-in values
instead: `build.zig.zon`'s `.version` and the pinned commit above. That keeps
the header deterministic and keeps it tied to `UPSTREAM.md`; `build.zig` refuses
to configure if the two ever disagree.

Upstream's Fortran, Python and Ruby bindings are not built by the Zig package.
They need CMake, a Fortran compiler or a Python environment and are out of scope
for this fork; the C core, the public C header and the C tests are what this
package ships.

## Sync mechanism

```sh
# fetch a newer upstream release
git remote update upstream
git fetch upstream --tags

# show what a bump would bring
git log --oneline main..upstream/v2.X.Y

# move the pin, then record it here and in build.zig
git checkout -b bump/v2.X.Y upstream/v2.X.Y
```

After moving the pin, update the table above, `build.zig`'s `upstream` block,
`build.zig.zon`'s `.version` and the changelog entry, then regenerate the byte
record:

```sh
# move the pin in UPSTREAM.md and build.zig first, then:
python3 tools/derive_upstream_sha256.py UPSTREAM.sha256
tools/check_provenance.sh
```

Re-check the behaviour tests as well: a new upstream release may change a
space-group answer that a fixture pins, and `src/spg_database.c` is generated
from the same tables the tests read.

`git diff --stat <old-pin>..HEAD -- src include database` printing nothing is
still the same check `tools/check_provenance.sh` runs, but it is no longer the
only one: `UPSTREAM.sha256` covers the whole carried tree, so a bump that
carried an upstream edit into `test/`, `docs/`, `database/`, `python/` or
anywhere else now fails the gate too. `origin` must point at the downstream and
`upstream` at the canonical repository before the first push; which remote is
configured is not evidence that anything was published.

## Verification status

`tools/check_provenance.sh` has run green against this pin, once, with both
recorded patches in place and the two-patch loop in use. Its README checks —
that `README.upstream.md` still matches upstream's README at the pinned commit
byte for byte, that `README.md` is this fork's own document rather than a copy
of it, and that `FORK-LICENSE.md` exists — were added on 2026-10-04 and are
PENDING-VERIFICATION; no run has observed them.

The `UPSTREAM.sha256` check and `tools/derive_upstream_sha256.py` were added on
2026-10-04 and have been OBSERVED green against this pin on this day: the gate
reported 719 records and 6 symlinks agreeing on
`12355c77fb7c505a55f52cae36341d73b781a065`, the derivation script reproduced
the committed `UPSTREAM.sha256` byte for byte, and eleven deliberate
tamperings — an appended data table, an edited YAML fixture, a deleted docs
page, a retargeted symlink, a stray file added to `database/` and to
`.github/`, an altered Fortran binding, an altered RPM spec, an altered public
header, an appended `COPYING`, an extra edit to a patched source, a doctored
`#!pin` digest and a truncated record — were each rejected while the restored
tree passed. That run says nothing about any build, test or smoke run, and it
observed no CI run.

Every other command in `README.md`, `README.zig.md`,
`.github/workflows/zig-fork-ci.yaml`, `flake.nix` and `devenv.nix` is
PENDING-VERIFICATION, and `FORK-NOTES.md` records each correction with the same
status. The provenance claims in this file are read out of the clone and are
SOURCE-CONFIRMED; nothing here reports a build, a test run, a smoke run, a
cross-target analysis, a Nix derivation, a devenv shell or a push. `README.md`
holds the full matrix with each row's evidence status.