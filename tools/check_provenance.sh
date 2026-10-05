#!/bin/sh
# Licence and provenance integrity gate for the spglib fork.
#
# Run from the repository root. Exits non-zero on the first failed check, so CI
# shows which obligation broke rather than a list of them.
#
# The gate answers six questions:
#   1. Is the BSD 3-Clause licence text still present and unmodified?
#   2. Does every upstream C file still carry its SPDX identifier?
#   3. Do upstream sources match the pin plus the two recorded patches?
#   4. Do the provenance records agree with the build script and the manifest?
#   5. Is the preserved upstream README still upstream's, byte for byte?
#   6. Does every upstream byte this repository carries still hash to what
#      UPSTREAM.sha256 records, and does that record still cover the whole
#      carried tree at the pin?
#
# Nothing here compiles, links or runs a test. It is a byte gate.

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

fail() {
    printf 'provenance: %s\n' "$1" >&2
    exit 1
}

# --- 1. Licence text -------------------------------------------------------

[ -f COPYING ] || fail "COPYING is missing"
grep -q 'Redistribution and use in source and binary forms' COPYING ||
    fail "COPYING no longer contains the BSD 3-Clause grant"
grep -q 'Neither the name of the' COPYING ||
    fail "COPYING no longer contains the third BSD condition"
grep -q 'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS' COPYING ||
    fail "COPYING no longer contains the BSD disclaimer"
[ -f NOTICE.md ] || fail "NOTICE.md is missing"
grep -q 'COPYING' NOTICE.md || fail "NOTICE.md does not point at COPYING"
[ -f FORK-LICENSE.md ] || fail "FORK-LICENSE.md is missing"

# --- 2. SPDX identifiers --------------------------------------------------

# base.h carries no SPDX line upstream; the exception is listed rather than
# silently skipped.
spdx_exceptions='src/base.h'
for source in src/*.c src/*.h src/*.h.in include/*.h; do
    case "$source" in src/base.h) continue ;; esac
    grep -q 'SPDX-License-Identifier: BSD-3-Clause' "$source" ||
        fail "$source lost its BSD-3-Clause SPDX identifier"
done
for exception in $spdx_exceptions; do
    [ -f "$exception" ] || fail "SPDX exception $exception does not exist"
done

# --- 3. Upstream sources plus the recorded patch --------------------------

pinned=$(sed -n 's/^| Pinned commit | `\(.*\)` |$/\1/p' UPSTREAM.md)
[ -n "$pinned" ] || fail "UPSTREAM.md has no pinned commit row"

if git rev-parse --verify --quiet "$pinned^{commit}" >/dev/null; then
    if ! git diff --quiet "$pinned" -- src ':(exclude)src/overlap.c' ':(exclude)src/primitive.c' include database; then
        fail "upstream sources differ outside the two recorded patches"
    fi
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM
    for patch_file in patches/0001-align-overlap-buffers.patch patches/0002-guard-null-pure-translation.patch; do
        [ -f "$patch_file" ] || fail "$patch_file is missing"
        patched=$(sed -n 's|^+++ b/\(.*\)$|\1|p' "$patch_file" | head -1)
        [ -n "$patched" ] || fail "$patch_file names no patched file"
        rm -rf "${tmpdir:?}/src"
        git archive "$pinned" "$patched" | tar -xf - -C "$tmpdir"
        patch -s -d "$tmpdir" -p1 < "$patch_file"
        cmp -s "$tmpdir/$patched" "$patched" ||
            fail "$patched differs from the pin plus $patch_file"
    done
else
    fail "pinned commit $pinned is absent; source integrity cannot be checked"
fi

# --- 4. Records agree with the build --------------------------------------

[ -f UPSTREAM.md ] || fail "UPSTREAM.md is missing"
[ -f CHANGELOG.md ] || fail "CHANGELOG.md is missing"
[ -f README.zig.md ] || fail "README.zig.md is missing"
[ -f build.zig ] || fail "build.zig is missing"
[ -f build.zig.zon ] || fail "build.zig.zon is missing"

build_pinned=$(sed -n 's/^    const commit = "\(.*\)";$/\1/p' build.zig)
[ "$build_pinned" = "$pinned" ] ||
    fail "build.zig pins $build_pinned but UPSTREAM.md pins $pinned"

manifest_version=$(sed -n 's/^    \.version = "\(.*\)",$/\1/p' build.zig.zon)
upstream_tag=$(sed -n 's/^| Pinned release | `\(.*\)` |$/\1/p' UPSTREAM.md)
tag_version=${upstream_tag#v}
[ "$manifest_version" = "$tag_version" ] ||
    fail "build.zig.zon declares $manifest_version but the pinned release is $upstream_tag"

minimum_zig=$(sed -n 's/^    \.minimum_zig_version = "\(.*\)",$/\1/p' build.zig.zon)
[ "$minimum_zig" = "0.16.0" ] ||
    fail "build.zig.zon requires Zig $minimum_zig, expected 0.16.0"

# --- 5. The preserved upstream README --------------------------------------

# Compared against the pinned commit rather than a remembered digest, so this
# fails if the pin moves and the preserved copy does not move with it.
[ -f README.upstream.md ] || fail "README.upstream.md is missing"

rm -rf "${tmpdir:?}"
mkdir -p "$tmpdir"
git archive "$pinned" README.md | tar -xf - -C "$tmpdir"
cmp -s "$tmpdir/README.md" README.upstream.md ||
    fail "README.upstream.md is not upstream's README.md at $pinned, byte for byte"
cmp -s "$tmpdir/README.md" README.md &&
    fail "README.md is a copy of upstream's README, not this fork's own document"

# --- 6. The complete upstream byte record ----------------------------------

# UPSTREAM.sha256 covers every upstream byte this repository carries at the
# pin: the C core and its headers, the public header, the generated-table
# inputs, the data tables, upstream's whole test suite and its functional
# fixtures, the Fortran/Python/Ruby bindings, the docs tree, the CMake project,
# the packaging tests, the RPM spec, the licence text and the uncompiled build
# and tooling files. Section 3 only ever looked at src/, include/ and database/,
# so it could not see a changed byte anywhere else; this section can.
#
# The record names the pin, the carried path set, the count per area and how
# every digest was derived. It was produced by
# tools/derive_upstream_sha256.py from the pinned commit's git objects, never
# from the working tree, so re-running that script at the same pin reproduces
# the file byte for byte.
[ -f UPSTREAM.sha256 ] || fail "UPSTREAM.sha256 is missing"

record_count=$(grep -c '^[0-9a-f][0-9a-f]*  ' UPSTREAM.sha256 || true)
[ "$record_count" -ge 700 ] ||
    fail "UPSTREAM.sha256 holds $record_count records, far too few to be the whole carried tree"

# 6a. Every carried regular file still hashes to what the record names.
if ! sha256sum -c --quiet UPSTREAM.sha256; then
    fail "a carried upstream byte no longer matches UPSTREAM.sha256"
fi

# 6b. The three fork-state records are labelled as such, and their recorded
# upstream digests are re-derived from the pin. This is what proves the record
# was derived from upstream rather than re-baselined onto the fork's own tree:
# re-baselining would move the record's digests and leave these lines stale.
sed -n 's/^#!pin \([0-9a-f][0-9a-f]*\)  \(.*\)$/\1 \2/p' UPSTREAM.sha256 > "$tmpdir/fork-pins.txt"
[ -s "$tmpdir/fork-pins.txt" ] || fail "UPSTREAM.sha256 records no fork-state paths to re-derive"
fork_count=0
while read -r recorded_digest fork_path; do
    at_pin=$(git show "$pinned:$fork_path" | sha256sum | cut -d' ' -f1)
    [ "$at_pin" = "$recorded_digest" ] ||
        fail "$fork_path at the pin hashes to $at_pin, not the $recorded_digest UPSTREAM.sha256 records as upstream's bytes"
    fork_count=$((fork_count + 1))
done < "$tmpdir/fork-pins.txt"
[ "$fork_count" -eq 3 ] ||
    fail "UPSTREAM.sha256 names $fork_count fork-state paths, expected 3"

# 6c. The symbolic links. sha256sum -c cannot check these -- hashing them would
# follow the link, and four of the six point at a directory -- so they are
# compared here, both against the pin and against the link text in the tree.
sed -n 's/^#!link \([0-9a-f][0-9a-f]*\)  \(.*\)$/\1 \2/p' UPSTREAM.sha256 > "$tmpdir/links.txt"
link_count=0
while read -r link_digest link_path; do
    [ -L "$link_path" ] || fail "$link_path is recorded as a symlink and is not one"
    at_pin=$(git show "$pinned:$link_path" | sha256sum | cut -d' ' -f1)
    [ "$at_pin" = "$link_digest" ] ||
        fail "$link_path at the pin holds different link text than UPSTREAM.sha256 records"
    in_tree=$(printf '%s' "$(readlink "$link_path")" | sha256sum | cut -d' ' -f1)
    [ "$in_tree" = "$link_digest" ] ||
        fail "$link_path points somewhere other than what UPSTREAM.sha256 records"
    link_count=$((link_count + 1))
done < "$tmpdir/links.txt"
[ "$link_count" -eq 6 ] ||
    fail "UPSTREAM.sha256 records $link_count symlinks, expected 6"

# 6d. Completeness in the other direction. The record must name every carried
# path and nothing else, so neither a dropped upstream file nor a file added
# into an upstream area passes unnoticed. The seven uncarried upstream workflows
# are the only exclusion; section 5 already proves the README rename.
git ls-tree -r --name-only "$pinned" \
    | grep -v -x -F \
        -e .github/workflows/ci.yaml \
        -e .github/workflows/release.yaml \
        -e .github/workflows/step_build-wheel.yaml \
        -e .github/workflows/step_coverage.yaml \
        -e .github/workflows/step_pre-commit.yaml \
        -e .github/workflows/step_test-docs.yaml \
        -e .github/workflows/step_test.yaml \
    | sed 's|^README\.md$|README.upstream.md|' \
    | LC_ALL=C sort > "$tmpdir/expected-paths.txt"
{ grep '^[0-9a-f][0-9a-f]*  ' UPSTREAM.sha256 | cut -c67-
  sed -n 's/^#!link \([0-9a-f][0-9a-f]*\)  \(.*\)$/\2/p' UPSTREAM.sha256; } \
    | LC_ALL=C sort > "$tmpdir/recorded-paths.txt"
if ! cmp -s "$tmpdir/expected-paths.txt" "$tmpdir/recorded-paths.txt"; then
    missing=$(comm -23 "$tmpdir/expected-paths.txt" "$tmpdir/recorded-paths.txt" | tr '\n' ' ')
    extra=$(comm -13 "$tmpdir/expected-paths.txt" "$tmpdir/recorded-paths.txt" | tr '\n' ' ')
    [ -z "$missing" ] || fail "UPSTREAM.sha256 does not cover: $missing"
    fail "UPSTREAM.sha256 covers paths the pin does not have: $extra"
fi

# 6e. The same completeness from the tree's side: nothing may sit inside a
# carried upstream area without being in the record. The pin-to-record
# comparison above cannot see this, because a file the pin never had is not in
# either list. The one fork-owned path that legitimately lives inside an
# upstream area is named rather than pattern-matched away.
find src include database test example fortran python ruby docs cmake .github .distro \
    \( -type f -o -type l \) -print \
    | sed 's|^\./||' \
    | grep -v -x -F -e .github/workflows/zig-fork-ci.yaml \
    > "$tmpdir/tree-paths.txt"

# The root-level upstream files travel beside those directories rather than
# inside one, so the walk has to name them too.
grep '^[0-9a-f][0-9a-f]*  ' UPSTREAM.sha256 \
    | cut -c67- \
    | grep -v / >> "$tmpdir/tree-paths.txt"
LC_ALL=C sort -o "$tmpdir/tree-paths.txt" "$tmpdir/tree-paths.txt"
if ! cmp -s "$tmpdir/tree-paths.txt" "$tmpdir/recorded-paths.txt"; then
    stray=$(comm -13 "$tmpdir/expected-paths.txt" "$tmpdir/tree-paths.txt" | tr '\n' ' ')
    gone=$(comm -23 "$tmpdir/expected-paths.txt" "$tmpdir/tree-paths.txt" | tr '\n' ' ')
    [ -z "$stray" ] || fail "files inside a carried upstream area are not in UPSTREAM.sha256: $stray"
    [ -z "$gone" ] || fail "carried upstream files are missing from the tree: $gone"
fi

printf 'provenance: licence, SPDX, upstream sources, records, the preserved README and %s UPSTREAM.sha256 records (%d symlinks) agree on %s\n' \
    "$record_count" "$link_count" "$pinned"
