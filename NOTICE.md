# Notices

## Upstream

spglib is distributed under the BSD 3-Clause licence. The authoritative text is
upstream's `COPYING` file, carried in this repository unmodified:

```
Copyright (c) 2024, Spglib team

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

* Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.
* Neither the name of the <organization> nor the
  names of its contributors may be used to endorse or promote products
  derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT
HOLDER> BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

Individual upstream source files carry their own SPDX identifiers, for example
`// SPDX-License-Identifier: BSD-3-Clause` in `include/spglib.h` and
`src/spglib.c`. Those headers are unchanged.

Per-file exception: `src/base.h` carries no SPDX identifier upstream. It is
recorded rather than silently skipped, and `tools/check_provenance.sh` fails if
the file disappears or if any other upstream C file in `src/`, `include/` or
`database/` loses its BSD-3-Clause line.

The data under `database/` and the tables generated into `src/spg_database.c`,
`src/msg_database.c` and `src/sitesym_database.c` come from upstream's
crystallographic databases and carry the same BSD 3-Clause terms.

## This fork

This repository is a downstream packaging of upstream spglib, not a derivative
work with a different licence. The BSD 3-Clause terms above continue to apply to
the whole library, whether it is built from this repository or installed from an
upstream release. Being private does not remove an obligation: the licence text,
the copyright notices and the provenance records travel with every copy.

Modifications made by this fork are listed in `CHANGELOG.md` and, in summary,
are:

* Added `build.zig` and `build.zig.zon`, a Zig 0.16 build of the upstream C
  core, and the Zig facade under `zig/`.
* Added the runtime-loading sources under `runtime/`: the build-side graph
  (`graph.zig`), the host generator that turns one translation into a dispatch
  (`generate.zig`), the loader core (`loader.zig`), the SDK descriptor that
  names what a provider must export (`library.zig`), and the two-file C shim
  the dispatch calls back through (`sync.h` and `sync.c`). Nothing in `src/` or
  `include/` changes for it.
* Added a deterministic configuration of `src/version.h.in`. The template
  itself is untouched; `build.zig` writes `version.h` from it at build time.
* Added tests, a runnable example, a consumer package, the licence and
  provenance gate in `tools/`, and the fork's own CI workflow.
* Added `UPSTREAM.md`, `NOTICE.md`, `CHANGELOG.md`, `FORK-NOTES.md`,
  `FORK-LICENSE.md` and `README.zig.md`, and the standalone packaging
  `package.nix`, `flake.nix`, `flake.lock`, `devenv.nix`, `devenv.yaml` and
  `.envrc`. `flake.lock` pins the nixpkgs input `flake.nix` names, by revision
  and resolved hash; there is no `devenv.lock`, and `devenv.yaml` pins its own
  input by revision instead. None of these files builds, downloads or
  substitutes anything: `package.nix` runs the same `zig build install` this
  repository already ran, from this directory's own source.
* Appended `.zig-cache/`, `zig-cache/` and `zig-out/` to `.gitignore`, keeping
  every upstream entry, and later the packaging entries `zig-pkg/`, `.direnv/`,
  `devenv/`, `.devenv/`, `result`, `result-*` and `.nix-build/`.
* Removed the imported upstream `.github/workflows` files.
* Reordered the internal buffers in `src/overlap.c` so double arrays remain
  aligned for odd atom counts. The recorded patch changes no algorithm and
  adds no allocation or padding; alignment checks remain enabled.
* Guarded the `mat_free_VecDBL` call in `get_primitive`
  (`src/primitive.c:246`) against a NULL pointer. Upstream reaches that call
  with `pure_trans == NULL` whenever `sym_get_pure_translation` fails on every
  attempt, and `mat_free_VecDBL` dereferences its argument
  (`src/mathfunc.c:402`), so an ordinary `spgms_get_magnetic_dataset` call
  crashes. The guard changes no algorithm and no return value; on the paths
  where the pointer is non-NULL it frees exactly what it freed before.

`src/`, `include/` and `database/` match the pinned commit plus
`patches/0001-align-overlap-buffers.patch` and
`patches/0002-guard-null-pure-translation.patch`, checked by the provenance gate.
No upstream algorithm, table or numerical constant changed. Upstream's
`ChangeLog.md`, `Contributing.md` and `CITATION.cff` are unchanged, and its
`README.md` is preserved byte for byte as `README.upstream.md`, so this fork's
own `README.md` could take the canonical path without editing upstream prose.
`README.zig.md` documents the Zig package separately.

The upstream `.github/workflows` files that came in with the import are removed,
not carried: they are another maintainer's CI and two of them publish to the
upstream PyPI project and Codecov account. `CHANGELOG.md` entry 7 records which
files and why. The fork's own workflow is `.github/workflows/zig-fork-ci.yaml`,
and it is the only CI entry point in this repository.

## Fork-authored files

Upstream terms do not grant anything about files this fork wrote, so those files
have their own grant: `FORK-LICENSE.md` records that the repository owner
authorized it directly on 2026-10-04, under BSD 3-Clause to match the primary
upstream terms, with `BSD-3-Clause` as the SPDX identifier for a newly authored
source or build file. No individual copyright holder is asserted there, and the
upstream authors named in `COPYING` are not credited with anything this fork
wrote. The file-by-file inventory is `FORK-LICENSE.md`.

Two paths need their own sentence, because a filename does not say whose
content is inside it:

* `README.upstream.md` is upstream content: a byte-for-byte copy of upstream's
  `README.md` at the pinned commit. It is governed by `COPYING`, not by the fork
  grant, and `tools/check_provenance.sh` proves the bytes still match.
* `patches/*.patch` quote hunks of upstream C, which stays BSD 3-Clause under
  `COPYING`; the patch files themselves are fork-authored text.

* `UPSTREAM.sha256` is a record, not a copy: every digest line holds either an
  upstream byte at the pin or the pin plus one of the recorded patches, and the
  header names the three paths that are the latter. The `#` comment lines are
  fork-authored text, covered by the fork grant; the digests record upstream's
  bytes. `tools/check_provenance.sh` re-derives them from the pin on every run.

The installed licence and provenance set is `share/licenses/spglib/COPYING`,
`NOTICE.md`, `FORK-LICENSE.md` and `UPSTREAM.md`, copied from these files by
`build.zig`'s install step. `package.nix` verifies that set rather than writing
it a second time.

## Third-party code

None. The Zig build compiles only upstream's own C sources plus this
repository's own: the facade, its tests and the example under `zig/`, and,
under `-Druntime`, the `runtime/sync.c` shim. `runtime/generate.zig` is a host
program this build runs over its own translation output rather than a library
it ships. No vendored third-party library is bundled.