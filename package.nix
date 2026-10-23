  # Source-only package shared by the flake and devenv.
  # build.zig owns sources, flags, version header, and installed files.
  # The artifact is `spglib`; upstream's `symspg` name does not match it.
  # Derive the target from stdenv.hostPlatform for cross builds.
{ lib
, stdenv
, zig
, linkage ? "static"
}:

assert lib.assertMsg (linkage == "static" || linkage == "dynamic")
  "spglib: linkage must be \"static\" or \"dynamic\", got ${builtins.toString linkage}";
assert lib.assertMsg (zig.version == "0.16.0")
  "spglib: built with Zig 0.16.0, got ${zig.version}";

let
  # Read the package version from the manifest; build.zig checks the upstream pin.
  manifestVersion =
    let
      pattern = ''.*\.version = "([^"]*)".*'';
      lines = lib.splitString "\n" (builtins.readFile ./build.zig.zon);
      candidates =
        builtins.filter (line: builtins.match pattern line != null) lines;
      matched = if candidates == [ ] then null
        else builtins.match pattern (builtins.head candidates);
    in
    if matched == null then null else builtins.head matched;

  version =
    if manifestVersion == null || manifestVersion == "" then
      throw "spglib: build.zig.zon declares no .version"
    else manifestVersion;

  # Derive Zig's target triple from nixpkgs hostPlatform, not the builder.
  # Map Nix `darwin` to Zig `macos` and preserve the host's libc ABI.
  # Avoid `builtins.currentSystem`, which describes the evaluator.
  zigArch =
    if stdenv.hostPlatform.isx86_64 then "x86_64"
    else if stdenv.hostPlatform.isaarch64 then "aarch64"
    else throw "spglib: no Zig target for hostPlatform.system ${stdenv.hostPlatform.system}";

  zigOs =
    if stdenv.hostPlatform.isLinux then "linux"
    else if stdenv.hostPlatform.isDarwin then "macos"
    else throw "spglib: no Zig target for hostPlatform.system ${stdenv.hostPlatform.system}";

  zigAbi =
    if stdenv.hostPlatform.isDarwin then "none"
    else if stdenv.hostPlatform.isMusl then "musl"
    else "gnu";

  zigTarget = "${zigArch}-${zigOs}-${zigAbi}";

  # Check platform-specific shared-library names on ELF and Mach-O.
  sharedLibrary =
    if stdenv.hostPlatform.isDarwin then "libspglib.dylib" else "libspglib.so";
  sharedLibraryVersioned =
    if stdenv.hostPlatform.isDarwin then "libspglib.${version}.dylib" else "libspglib.so.${version}";
in

stdenv.mkDerivation {
  pname = "spglib";
  version = version;

  # Package the source tree without VCS or build state.
  src = builtins.path {
    path = ./.;
    name = "spglib-source";
    filter = path: type:
      let base = baseNameOf (toString path);
      in !(builtins.elem base [
        ".git"
        ".jj"
        ".direnv"
        ".devenv"
        ".devenv.flake.nix"
        ".zig-cache"
        "zig-cache"
        "zig-out"
        "zig-pkg"
        "devenv"
        "result"
      ] || builtins.match "result-.*" base != null);
  };

  strictDeps = true;
  nativeBuildInputs = [ zig ];

  # Use only the explicit install command; it builds the C core once.
  dontConfigure = true;
  dontBuild = true;
  doCheck = false;
  # Do not let the Zig hook add a second, differently configured test build.
  dontUseZigCheck = true;
  # The install command supplies its own prefix, CPU, and release flags.
  dontAddPrefix = true;
  dontSetZigDefaultFlags = true;

  installPhase = ''
    runHook preInstall

    # Keep Zig caches under TMPDIR, outside the source tree.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global"
    mkdir -p "$ZIG_LOCAL_CACHE_DIR" "$ZIG_GLOBAL_CACHE_DIR"

    # Pass the nixpkgs-derived target and baseline CPU explicitly.
    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Dtarget=${zigTarget} \
      -Dcpu=baseline \
      -Doptimize=ReleaseSafe \
      -Dlinkage=${linkage}

    runHook postInstall
  '';

  # Verify that `zig build install` produced the promised install closure.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    fail() {
      echo "spglib: $1" >&2
      exit 1
    }

    for header in "$out/include/spglib.h" "$out/include/spglib/version.h"; do
      [ -f "$header" ] || fail "$header is not installed"
    done

    for record in COPYING NOTICE.md FORK-LICENSE.md UPSTREAM.md; do
      [ -s "$out/share/licenses/spglib/$record" ] ||
        fail "share/licenses/spglib/$record is not installed"
    done

    if [ "${linkage}" = "static" ]; then
      [ -f "$out/lib/libspglib.a" ] || fail "no libspglib.a"
    else
      [ -e "$out/lib/${sharedLibrary}" ] || [ -e "$out/lib/${sharedLibraryVersioned}" ] ||
        fail "no ${sharedLibrary}"
    fi

    # Check that pkg-config links the delivered `spglib` artifact.
    [ -s "$out/lib/pkgconfig/spglib.pc" ] || fail "no lib/pkgconfig/spglib.pc"
    grep -q -- '-lspglib' "$out/lib/pkgconfig/spglib.pc" ||
      fail "lib/pkgconfig/spglib.pc does not link -lspglib"

    runHook postInstallCheck
  '';

  passthru = {
    inherit linkage zigTarget;
  };

  meta = {
    description = "spglib, a crystal symmetry library, built from this repository's source";
    longDescription = ''
      spglib ${version} as a Zig 0.16 SDK: the 23 upstream C translation units
      from src/, the public header include/spglib.h, the generated
      spglib/version.h, link metadata in lib/pkgconfig/spglib.pc, and BSD
      3-Clause licence material under share/licenses/spglib. README.md has the
      support matrix and its evidence status, README.zig.md the Zig interface,
      UPSTREAM.md the provenance.
    '';
    license = lib.licenses.bsd3;
    homepage = "https://github.com/spglib/spglib";
  };
}