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
`tools/check_provenance.sh` re-checks the pin plus
`patches/0001-align-overlap-buffers.patch` on every CI run. All other files in
`src`, `include` and `database` must match the pin.

Nothing here records a service query. No release-listing API call, no remote
existence check and no publication receipt is part of this file: `origin` is
configured, which records an intention and not an outcome, and the downstream
repository is a private one whose URL and content hash are unconfirmed.

## Layout of this repository

Everything under `src/`, `include/`, `test/`, `database/`, `example/`,
`fortran/`, `python/`, `ruby/`, `docs/`, `cmake/`, `CMakeLists.txt`,
`CMakePresets.json`, `pyproject.toml`, `.pre-commit-config.yaml`,
`.packit.yaml`, `README.md`, `ChangeLog.md`, `CITATION.cff`, `Contributing.md`
and `.github/` is upstream content, unmodified except where this file and
`CHANGELOG.md` say otherwise.

The seven upstream workflows under
`.github/workflows` are not carried. They are the upstream project's own CI, and
two of them publish to the upstream PyPI project and Codecov account, which this
fork does not own. `CHANGELOG.md` entry 7 names them. They remain in the
upstream repository and in the imported history.

| Path | Purpose |
| --- | --- |
| `build.zig`, `build.zig.zon` | Zig 0.16 build, module and artifact exports |
| `zig/root.zig` and `zig/*.zig` | Public Zig facade and the `c` escape hatch |
| `zig/tests/` | Behaviour tests, raw-C tests, public-surface coverage |
| `zig/examples/smoke.zig` | Runnable example behind `zig build smoke` |
| `zig/consumer/` | Separate package that consumes the exported module |
| `tools/check_provenance.sh` | Licence, SPDX and pinned-source integrity gate |
| `README.zig.md` | Usage documentation for the Zig package |
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
`build.zig.zon`'s `.version` and the changelog entry. Re-check the behaviour
tests: a new upstream release may change a space-group answer that a fixture
pins, and `src/spg_database.c` is generated from the same tables the tests read.

After merging the tag, `git diff --stat <old-pin>..HEAD -- src include
database` must print nothing: that is the same check
`tools/check_provenance.sh` runs, and it is the only evidence that the bump did
not carry an upstream edit into the fork's region. `origin` must point at the
downstream and `upstream` at the canonical repository before the first push;
which remote is configured is not evidence that anything was published.

## Verification status

`tools/check_provenance.sh` has run green against this pin, once, with both
recorded patches in place and the two-patch loop in use. Every other
command in `README.zig.md` and in `.github/workflows/zig-fork-ci.yaml` is
PENDING-VERIFICATION, and `FORK-NOTES.md` records each correction with the same
status. The provenance claims in this file are read out of the clone and are
SOURCE-CONFIRMED; nothing here reports a build, a test run, a smoke run, a
cross-target analysis or a push.