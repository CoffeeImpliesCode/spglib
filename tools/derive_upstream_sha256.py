#!/usr/bin/env python3
"""Derive spglib's UPSTREAM.sha256 from the pinned commit's git objects.

Every digest is computed from `git show <pin>:<path>`, i.e. from the object
store at the pin. The two patched files' carried digests are derived the same
way: the recorded patch is replayed onto the pinned blob and the result is
hashed, so the working tree is never read to produce a digest. Only
`.gitignore` is read from the tree, because this fork appended to it in place
with no recorded patch; its upstream bytes are still derived from the pin and
are asserted to be an exact prefix.

Run it from the repository root, with the pinned commit present in the local
clone:

     python3 tools/derive_upstream_sha256.py UPSTREAM.sha256

It writes the record and prints the counts. It needs `git`, `tar`, `patch`
and Python 3; it needs no network access and runs no build. Diff the result
against the committed UPSTREAM.sha256: at the same pin the two must be
identical, and any difference is either a moved pin or an edit to a carried
upstream byte.

SPDX-License-Identifier: BSD-3-Clause
"""

import hashlib
import os
import subprocess
import sys
import tempfile

PIN = "12355c77fb7c505a55f52cae36341d73b781a065"
TAG = "v2.7.0"
REPO = "https://github.com/spglib/spglib.git"
TARBALL_URL = "https://codeload.github.com/spglib/spglib/tar.gz/refs/tags/v2.7.0"
TARBALL_SHA256 = "b22fc9abae9716c574fbc6d55cfc53ed654a714fccc5657a26ff5d18114bd8bd"
TARBALL_SIZE = 2442495

# Upstream workflows this fork deliberately does not carry (CHANGELOG.md entry 7).
DROPPED = {
    ".github/workflows/ci.yaml",
    ".github/workflows/release.yaml",
    ".github/workflows/step_build-wheel.yaml",
    ".github/workflows/step_coverage.yaml",
    ".github/workflows/step_pre-commit.yaml",
    ".github/workflows/step_test-docs.yaml",
    ".github/workflows/step_test.yaml",
}

# Paths this fork edits on purpose. Each carries a recorded patch, except
# .gitignore, which upstream and this fork both append to.
PATCHED = {
    "src/overlap.c": "patches/0001-align-overlap-buffers.patch",
    "src/primitive.c": "patches/0002-guard-null-pure-translation.patch",
}
APPENDED = {".gitignore": None}
FORK_STATE = sorted(set(PATCHED) | set(APPENDED))

# The one path this fork renames: upstream README.md travels as README.upstream.md.
RENAMES = {"README.md": "README.upstream.md"}


def git(*args, binary=False):
    out = subprocess.run(["git", *args], check=True, capture_output=True).stdout
    return out if binary else out.decode()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def replay(patch_path: str, pin_path: str) -> bytes:
    """Apply a recorded patch to the pinned blob and return the result."""
    with tempfile.TemporaryDirectory() as td:
        archive = subprocess.run(["git", "archive", "--format=tar", PIN, pin_path],
                                 check=True, capture_output=True).stdout
        subprocess.run(["tar", "-xf", "-", "-C", td], input=archive, check=True)
        with open(patch_path, "rb") as fh:
            subprocess.run(["patch", "-s", "-d", td, "-p1"], stdin=fh, check=True)
        with open(os.path.join(td, pin_path), "rb") as fh:
            return fh.read()


def main() -> int:
    tree = {}
    for line in git("ls-tree", "-r", PIN).splitlines():
        meta, path = line.split("\t", 1)
        mode, _typ, oid = meta.split()
        tree[path] = (mode, oid)

    # Carry set: everything the pin has except the seven uncarried workflows,
    # with upstream's README renamed to the name it travels under.
    carried = {}
    for path, (mode, oid) in tree.items():
        if path in DROPPED:
            continue
        carried[RENAMES.get(path, path)] = (path, mode, oid)

    pin_bytes = {p: git("show", f"{PIN}:{p}", binary=True) for p in tree}

    lines = []
    symlinks = []
    fork_state = []
    for carried_path in sorted(carried):
        pin_path, mode, _oid = carried[carried_path]
        data = pin_bytes[pin_path]
        if mode == "120000":
            symlinks.append((sha256(data), carried_path))
            continue
        if carried_path in PATCHED:
            # The pin, plus the recorded patch. Never the working tree.
            wt = replay(PATCHED[carried_path], pin_path)
        elif carried_path in APPENDED:
            # Upstream's bytes plus this fork's own appended entries, in place
            # and with no recorded patch. Upstream's bytes still come from the
            # pin, and are required to be an exact prefix of the carried file.
            wt = open(carried_path, "rb").read()
            if not wt.startswith(data):
                raise SystemExit(f"{carried_path} no longer starts with upstream's bytes")
        else:
            wt = data
        if carried_path in FORK_STATE:
            fork_state.append((carried_path, sha256(wt), sha256(data), len(wt), len(data)))
        lines.append((sha256(wt), carried_path))

    header = f"""\
# UPSTREAM.sha256 -- complete SHA-256 record of the upstream bytes the spglib
# fork carries at its pin.
#
# ---------------------------------------------------------------------------
# THE PIN
# ---------------------------------------------------------------------------
#
#   repository   {REPO}
#   tag          {TAG}
#   commit       {PIN}
#   tree         {git('rev-parse', PIN + '^{tree}').strip()}
#
# `git rev-parse {TAG}^{{commit}}` resolves to the commit above, and the local
# clone's blob contents for all 732 tree entries were cross-checked against the
# {TAG} source tarball. That tarball was fetched for this record only; nothing
# in this repository is built from it and no digest below comes from it.
#
#   url      {TARBALL_URL}
#   size     {TARBALL_SIZE} bytes
#   sha256   {TARBALL_SHA256}
#
# The one file where tarball and clone legitimately differ is
# `.git_archival.txt`: upstream marks it `export-subst`, so `git archive`
# substitutes the commit, date and describe-name into it and a tarball built
# from the tag carries the substituted text, while the clone and the working
# tree carry the unsubstituted `$Format:...` placeholders. The digest recorded
# here is the unsubstituted blob at the pin. Every other entry matched
# byte for byte in both directions.
#
# ---------------------------------------------------------------------------
# HOW THESE DIGESTS WERE DERIVED
# ---------------------------------------------------------------------------
#
# Each digest is SHA-256 over raw bytes hashed in one call, with no
# normalisation of any kind: no text-mode conversion, no trailing-newline
# handling, no line-ending rewriting.
#
# Every upstream byte comes out of the object store at the pin, never out of
# this working tree:
#
#   * {len(lines) - len(fork_state)} records are the blob at the pin itself, read
#     with `git show <pin>:<path>`.
#   * 2 of them -- src/overlap.c and src/primitive.c -- are forked, and their
#     recorded digests are the result of applying the recorded patch to the
#     pinned blob, hashed. The working tree is not consulted, which is what
#     stops a drifted working tree from being written into the record as if it
#     were upstream.
#   * .gitignore is the one path this fork edited in place without recording a
#     patch, so its carried digest is read from the tree. Its upstream bytes
#     are still derived from the pin and are required to be an exact prefix of
#     the carried file, so upstream's own lines cannot be silently reordered,
#     removed or rewritten by the append.
#
# The record was produced on 2026-10-04 with
# tools/derive_upstream_sha256.py, which is the derivation itself; re-running
# it at the same pin reproduces this file byte for byte.
#
# The path set is derived from `git ls-tree -r {PIN[:12]}`, which lists all 732
# entries of the pinned tree, minus the seven paths this fork does not carry,
# with one rename applied. Symlinks are carried in the record by the digest of
# their link text, which is what the pin stores, not the digest of whatever
# they point at.
#
# ---------------------------------------------------------------------------
# THE PATH SET AND ITS COUNTS
# ---------------------------------------------------------------------------
#
# {len(lines)} records: {len(lines) - len(symlinks)} regular files and {len(symlinks)} symbolic links.
# That is the complete pinned tree minus the seven uncarried
# upstream workflows, with upstream's README recorded under this fork's name.
# Nothing is dropped for being uncompiled and nothing is dropped for size: the
# Fortran, Python and Ruby bindings, the packaging tests, the docs tree, the
# RPM spec and the CMake project files all travel, and upstream's 502
# `test/functional` fixtures travel with them.
#
#   regular  links   bytes      area
#   ---------------------------------------------------------
#     537       3    1400530    test/          upstream's own C and Python tests,
#                                        packaging tests and functional fixtures
#      49       0    8555981    src/           the C core, internal headers and
#                                        version.h.in; 3 are fork-state, below
#      34       0    1273365    docs/          Sphinx sources, api/ pages and
#                                        _static/ assets
#      25       0     518480    database/      the symmetry tables and the
#                                        Python generators that produce
#                                        src/spg_database.c and
#                                        src/sitesym_database.c
#      22       0     130832    python/        the CPython extension sources
#      17       0     104414    (repository root) licence, changelog, citation,
#                                        contributing guide, CMake project,
#                                        pyproject.toml, editor and CI config
#       8       0       4079    .distro/       the RPM spec, fmf test plans and
#                                        rpmlint config
#       7       0      71383    cmake/         package config templates and the
#                                        DynamicVersion helper
#       6       0      57940    fortran/       the Fortran binding sources
#       6       0      42555    ruby/          the Ruby binding sources
#       5       0       3186    .github/       issue templates, release config,
#                                        renovate and codecov config
#       1       3         496    example/       one C example; the other three
#                                        entries here are symlinks into
#                                        test/example/
#       2       0      26658    include/       the public C header and its
#                                        CMake fragment
#   ---------------------------------------------------------
#     {len(lines) - len(symlinks)}       {len(symlinks)}   {sum(len(pin_bytes[v[0]]) for v in carried.values())}
#
# The byte column counts the pinned bytes, which for the three fork-state paths
# is not what this repository ships; see the next section.
#
# ---------------------------------------------------------------------------
# THREE RECORDS THAT ARE NOT UPSTREAM BYTES
# ---------------------------------------------------------------------------
#
# These are the only records in this file whose digest is not the digest of the
# upstream blob at the pin. Each is a path this fork edits on purpose, and each
# is named here rather than left to look like an upstream byte:
#
"""

    for path, wt_d, pin_d, wt_n, pin_n in fork_state:
        if path in PATCHED:
            note = [f"the pin plus {PATCHED[path]}"]
        else:
            note = [f"upstream's {pin_n} bytes unchanged, with this fork's own",
                    f"entries appended below a '# Fork additions below' marker;",
                    f"nothing upstream is reordered or removed"]
        header += ("#\n"
                   f"#   {path}\n"
                   f"#     recorded  {wt_d}  ({wt_n} bytes)\n"
                   + "".join(f"#                {n}\n" for n in note)
                   + f"#     at the pin {pin_d}  ({pin_n} bytes)\n")

    header += f"""#
# Each "at the pin" digest above is repeated at the end of this file on a
# `#!pin` line. tools/check_provenance.sh re-derives those three digests from
# the pin with `git show` and requires them to match, which is what proves this
# record was derived from upstream rather than re-baselined onto the fork's own
# tree.
#
# The two patched files are additionally replayed from the pin by
# tools/check_provenance.sh: it applies {PATCHED['src/overlap.c']} and
# {PATCHED['src/primitive.c']}
# to the pinned sources and requires the result to equal the bytes recorded
# here, so the record and the patches cannot drift apart. The patches stay the
# patches: this record names the resulting state and never replaces them.
#
# ---------------------------------------------------------------------------
# ONE RENAMED PATH
# ---------------------------------------------------------------------------
#
# Upstream's `README.md` is carried here as `README.upstream.md`, byte for byte,
# because this fork's own `README.md` took over that name. The bytes are
# unchanged: the recorded digest is the digest of upstream's README.md at the
# pin, which is what a record naming the carried path must hold. The record uses
# the carried name, because a record has to name a path that exists.
#
# ---------------------------------------------------------------------------
# DELIBERATELY NOT CARRIED
# ---------------------------------------------------------------------------
#
# Seven upstream files exist at the pin and are not in this record because this
# fork does not carry them (CHANGELOG.md entry 7): they are upstream's own CI,
# and two of them publish to the upstream PyPI project and Codecov account, which
# this fork does not own.
#
"""

    for path in sorted(DROPPED):
        data = pin_bytes.get(path)
        if data is None:
            data = git("show", f"{PIN}:{path}", binary=True)
        header += f"#   {sha256(data)}  {path}\n"

    header += f"""#
# Their digests are recorded here so the omission is auditable: a future reader
# can confirm these are upstream's files and not files this fork lost. They
# remain in the upstream repository and in the imported git history.
#
# Not in this record because this fork wrote them, not because upstream lacks
# them: build.zig, build.zig.zon, UPSTREAM.sha256, zig/ (including
# zig/consumer/), runtime/, tools/, patches/, .github/workflows/zig-fork-ci.yaml,
# README.md, README.zig.md, CHANGELOG.md, FORK-NOTES.md, FORK-LICENSE.md,
# NOTICE.md, UPSTREAM.md, package.nix, flake.nix, devenv.nix, devenv.yaml and
# .envrc. UPSTREAM.md names each one and says what it is. Generated and cached
# trees (`.zig-cache/`, `zig-out/`) are not in it either: they are build output,
# not source.
#
# ---------------------------------------------------------------------------
# HOW TO CHECK
# ---------------------------------------------------------------------------
#
#   sha256sum -c UPSTREAM.sha256      # the {len(lines)} regular-file records
#   tools/check_provenance.sh         # everything, from the repository root
#
# `sha256sum -c` reports the regular-file records and ignores every `#` line, so
# the header, the `#!pin` lines and the `#!link` lines cost it nothing. It does
# not and cannot check the {len(symlinks)} symlinks: hashing them would follow the
# link and read the target, and four of the six point at a directory. That is
# why they are `#!link` lines rather than records -- tools/check_provenance.sh
# parses them and compares each link's text against the pin.
#
# The gate is a byte check, not a build. It compiles nothing, links nothing and
# runs no test; it fails when an upstream byte this repository carries changes.
#
# In a fetched package this record is deliberately a superset of what arrives:
# `build.zig.zon` `.paths` ships `src/`, `include/`, the symlinked
# `example/c_api`, the licence texts and this file, and not upstream's tests,
# docs, bindings or `database/`. There, `sha256sum -c UPSTREAM.sha256` reports
# the uncarried upstream paths as missing. That is expected and is not a
# failure of the record; the paths that must be present for the package to
# build -- `src/`, `include/`, `COPYING`, `README.upstream.md`, `example/c_api`
# -- do check. The gate itself needs the pinned commit in a local clone and so
# belongs to this repository rather than to a fetched package.
#
# ---------------------------------------------------------------------------
# STATUS
# ---------------------------------------------------------------------------
#
# SOURCE-CONFIRMED. Every digest here was computed from the pinned commit's
# objects, and the derivation was cross-checked against the {TAG} source tarball
# named above. No build, test, smoke run or Nix derivation is claimed by this
# file; README.md holds the matrix with each row's evidence status.
"""

    body = [f"{d}  {p}" for d, p in lines]
    body += [f"#!pin {d}  {p}" for p, _, d, _, _ in fork_state]
    body += [f"#!link {d}  {p}" for d, p in symlinks]

    with open(sys.argv[1], "w") as fh:
        fh.write(header)
        fh.write("\n")
        fh.write("\n".join(body))
        fh.write("\n")

    print(f"records {len(lines)} ({len(lines) - len(symlinks)} regular, "
          f"{len(symlinks)} links), pin lines {len(fork_state)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
