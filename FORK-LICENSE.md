# Licence of the fork-authored additions

Upstream spglib is BSD 3-Clause. Its authoritative text is `COPYING`, carried
here unmodified and installed with every copy of the library; it governs the
upstream material listed below. Upstream terms say nothing about files this fork
wrote, so those files have a separate grant, recorded here.

## The grant

* **Authorized by** the owner of this repository, directly, on **2026-10-04**, as
  part of the contract-migration wave. A direct authorization recorded here, not
  a permission from upstream and not a publication receipt.
* **Terms:** BSD 3-Clause, matching this project's primary upstream terms. The
  authoritative text is `COPYING`, not restated here.
* **SPDX identifier for fork-authored files:** `BSD-3-Clause`.
* **Copyright holder:** not asserted here as an individual. The holder is the
  party that made the authorization above. No personal name is invented, and the
  upstream authors named in `COPYING` are not credited with anything this fork
  wrote.

## Files the grant covers

| Path | What it is |
| --- | --- |
| `build.zig`, `build.zig.zon` | The Zig build of the upstream C core |
| `zig/*.zig`, `zig/tests/`, `zig/examples/`, `zig/consumer/` | Facade, tests, example, consumer package |
| `runtime/` | Runtime-loading core, when it lands; same terms |
| `tools/check_provenance.sh` | The licence and provenance gate |
| `tools/derive_upstream_sha256.py` | Regenerates `UPSTREAM.sha256` from the pinned commit's git objects |
| `UPSTREAM.sha256` | Digests of upstream bytes, plus this fork's text describing them; the digests are upstream's or pin-derived, not the fork's |
| `.github/workflows/zig-fork-ci.yaml` | This fork's only CI workflow |
| `package.nix`, `flake.nix` | The source-only package and its flake |
| `devenv.nix`, `devenv.yaml`, `.envrc` | The development environment |
| `README.md`, `README.zig.md` | This fork's documents |
| `FORK-LICENSE.md`, `FORK-NOTES.md`, `CHANGELOG.md`, `NOTICE.md`, `UPSTREAM.md` | The fork's records |
| `.gitignore` fork block | The appended build and packaging entries; the upstream entries stay upstream content |

Two paths need their own sentence, because a filename does not say whose content
is inside it:

* **`README.upstream.md` is upstream content** — a byte-for-byte copy of
  upstream's `README.md` at the pinned commit, preserved so this fork's README
  could take the canonical path. It is governed by `COPYING`, not by this grant,
  and `tools/check_provenance.sh` compares those bytes.
* **`patches/*.patch` quote upstream code.** The hunks stay BSD 3-Clause under
  `COPYING`; the patch files are fork-authored text describing the changes.

* **`UPSTREAM.sha256` mixes upstream bytes and this fork's prose in one file.**
  Every digest line is either an upstream byte at the pin or the pin plus a
  recorded patch, and the header says which is which for the three that are not
  upstream. The `#` comment lines are this fork's text. The grant covers that
  comment text; it claims nothing over the digests, which record upstream's
  bytes.

## What the grant does not do

* It does not make the tree one thing. A reader must still be able to tell
  upstream material from fork additions, which `UPSTREAM.md`, `CHANGELOG.md` and
  this file are for.
* It does not cover per-file exceptions: `src/base.h` carries no SPDX identifier
  upstream, recorded in `NOTICE.md` rather than papered over.
* It is not a patent grant. BSD 3-Clause has no explicit patent clause, so
  nothing here should be read as one.

## Obligations that travel with the library

1. Redistribution, in source or binary form, keeps `COPYING`'s copyright notice,
   its conditions and its disclaimer.
2. Every installed copy carries `share/licenses/spglib/COPYING`, `NOTICE.md`,
   `FORK-LICENSE.md` and `UPSTREAM.md`.
3. Per-file SPDX identifiers are not removed from upstream sources;
   `tools/check_provenance.sh` checks them.
4. Upstream's names are not used to endorse a derived product without
   permission — the third BSD condition, which applies to this fork's
   redistribution too.