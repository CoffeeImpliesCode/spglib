# Licence of fork-authored additions

Upstream spglib is BSD 3-Clause. `COPYING` is authoritative and ships with library copies.

## The grant

* **Authorized by** the owner of this repository, directly, on **2026-10-04**; not by upstream.
* **Terms:** BSD 3-Clause, matching this project's primary upstream terms. `COPYING` is authoritative.
* **SPDX identifier for fork-authored files:** `BSD-3-Clause`.
* **Copyright holder:** authorizing party; no individual asserted. Upstream authors in `COPYING` are not credited for fork work.

## Files the grant covers

- `build.zig`, `build.zig.zon`; `zig/*.zig`, `zig/tests/`, `zig/examples/`, `zig/consumer/`; `runtime/`.
- `tools/check_provenance.sh`; `tools/derive_upstream_sha256.py`; `UPSTREAM.sha256`.
- `package.nix`, `flake.nix`; `devenv.nix`, `devenv.yaml`, `.envrc`.
- `README.md`, `README.zig.md`; `FORK-LICENSE.md`, `FORK-NOTES.md`, `CHANGELOG.md`, `NOTICE.md`, `UPSTREAM.md`.
- `.gitignore` fork block only; upstream entries remain upstream content.

`README.upstream.md` is upstream's `README.md` byte-for-byte at the pin; `COPYING` governs it; the check script compares it.

`patches/*.patch` quote upstream code under `COPYING`; patch files are fork-authored text.

`UPSTREAM.sha256` digests record upstream bytes or pin+patch; the header marks three patched entries. `#` lines are fork text under this grant, not digests.

## Exclusions

Upstream/fork scope is recorded in `UPSTREAM.md`, `CHANGELOG.md`, and this file. `src/base.h` has no upstream SPDX identifier and is listed in `NOTICE.md`; it is outside the grant. BSD 3-Clause has no explicit patent clause; this grant is not a patent grant.

## Redistribution

1. Redistribution keeps `COPYING`'s copyright notice, conditions, and disclaimer.
2. Each copy carries `share/licenses/spglib/COPYING`, `NOTICE.md`, `FORK-LICENSE.md`, and `UPSTREAM.md`.
3. Retain upstream per-file SPDX identifiers; `tools/check_provenance.sh` checks them.
4. Do not use upstream names to endorse derived products without permission (BSD third condition).
