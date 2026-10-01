#!/bin/sh
# Licence and provenance integrity gate for the spglib fork.
#
# Run from the repository root. Exits non-zero on the first failed check, so CI
# shows which obligation broke rather than a list of them.
#
# The gate answers four questions:
#   1. Is the BSD 3-Clause licence text still present and unmodified?
#   2. Does every upstream C file still carry its SPDX identifier?
#   3. Do upstream sources match the pin plus the two recorded patches?
#   4. Do the provenance records agree with the build script and the manifest?

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

printf 'provenance: licence, SPDX, upstream sources and records agree on %s\n' "$pinned"