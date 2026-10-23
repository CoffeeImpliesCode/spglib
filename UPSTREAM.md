# Upstream provenance

| Field | Value |
| --- | --- |
| Project | spglib |
| Canonical repository | <https://github.com/spglib/spglib.git> |
| Pinned release | `v2.7.0` |
| Pinned commit | `12355c77fb7c505a55f52cae36341d73b781a065` |
| Commit subject | `Release v2.7.0 (#628)` |
| Upstream default branch | `develop` |
| Fork branch at import | `main`, branched at the pinned commit |
| Source acquisition | Full `git clone`; upstream history preserved |
| Pinned tree | `3bb8527bfa8c9dfcc2bcffa2250c2f41605bc23c` |
| Carried path count | 725 of 732 tree entries; seven paths listed below were removed |
| Digest record | `UPSTREAM.sha256` records the carried upstream paths and their digests |
| Reference tarball | <https://codeload.github.com/spglib/spglib/tar.gz/refs/tags/v2.7.0> |
| Tarball size and SHA-256 | `2442495` bytes; `b22fc9abae9716c574fbc6d55cfc53ed654a714fccc5657a26ff5d18114bd8bd` |
| SPDX identifier | `BSD-3-Clause` (`COPYING`) |

## Path ownership

| Paths | Origin and state |
| --- | --- |
| `src/`, `include/`, `test/`, `database/`, `example/`, `fortran/`, `python/`, `ruby/`, `docs/`, `cmake/`, `.distro/`, remaining `.github/` files | Upstream content listed in `UPSTREAM.sha256`; files match the pinned commit except the recorded source patches. |
| `CMakeLists.txt`, `CMakePresets.json`, `pyproject.toml`, `ChangeLog.md`, `CITATION.cff`, `Contributing.md`, `COPYING`, and other carried root files | Upstream content listed in `UPSTREAM.sha256`. |
| `src/overlap.c` | Pinned upstream file plus `patches/0001-align-overlap-buffers.patch`. |
| `src/primitive.c` | Pinned upstream file plus `patches/0002-guard-null-pure-translation.patch`. |
| `.gitignore` | Retains upstream's 809 bytes unchanged and appends the fork's entries. |
| `README.upstream.md` | Byte-for-byte copy of upstream `README.md`; `README.md` is fork-authored. |
| `patches/*.patch` | Fork-authored patch text; quoted upstream code remains upstream content. |
| Other fork-authored paths | Listed in `FORK-LICENSE.md`; `UPSTREAM.sha256` distinguishes fork state from pinned bytes. |

## Removed upstream paths

`.github/workflows/ci.yaml`, `.github/workflows/release.yaml`, `.github/workflows/step_build-wheel.yaml`, `.github/workflows/step_coverage.yaml`, `.github/workflows/step_pre-commit.yaml`, `.github/workflows/step_test-docs.yaml`, `.github/workflows/step_test.yaml`.
