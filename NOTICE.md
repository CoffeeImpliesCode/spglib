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
* Added a deterministic configuration of `src/version.h.in`. The template
  itself is untouched; `build.zig` writes `version.h` from it at build time.
* Added tests, a runnable example, a consumer package, the licence and
  provenance gate in `tools/`, and the fork's own CI workflow.
* Added `UPSTREAM.md`, `NOTICE.md`, `CHANGELOG.md`, `FORK-NOTES.md` and
  `README.zig.md`.
* Appended `.zig-cache/`, `zig-cache/` and `zig-out/` to `.gitignore`, keeping
  every upstream entry.
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
No upstream algorithm, table or numerical constant changed. The upstream
`README.md`, `ChangeLog.md`, `Contributing.md` and
`CITATION.cff` are unchanged; `README.zig.md` documents the Zig package
separately instead of rewriting upstream prose.

The upstream `.github/workflows` files that came in with the import are removed,
not carried: they are another maintainer's CI and two of them publish to the
upstream PyPI project and Codecov account. `CHANGELOG.md` entry 7 records which
files and why. The fork's own workflow is `.github/workflows/zig-fork-ci.yaml`,
and it is the only CI entry point in this repository.

## Third-party code

None. The Zig build compiles only upstream's own C sources plus the Zig sources
under `zig/`. No vendored third-party library is bundled.