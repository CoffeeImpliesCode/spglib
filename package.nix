# Source-only package for the spglib SDK. `flake.nix` and `devenv.nix` both
# call this one function; each entry point supplies the linkage variant.
#
# One build command, `zig build install`, so `build.zig` keeps ownership of the
# source list, the C flags, the generated version header and the installed
# files. This file adds no C flag and writes no installed file.
#
# The installed library is named `spglib`, because build.zig calls
# library `symspg` (CMakeLists.txt:108-113, cmake/spglib.pc.in:4), so link
# metadata derived from upstream's own `-lsymspg` would name a file this output
# does not contain.
#
# The build command names its target, derived from `stdenv.hostPlatform`, so
# the three non-host systems `flake.nix` advertises install a library built for
# themselves rather than a host-native one under a foreign store path. The
# derivation of that triple is `zigTarget` below; nothing here reads the
# evaluator's or the builder's platform.
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
  # Read the version from the manifest instead of repeating it, so a release
  # bump cannot leave a stale package name behind. `build.zig` panics at
  # configure time when the manifest and UPSTREAM.md drift apart; this is the
  # same rule on the packaging side.
  #
  # `lib.splitString` is the only lib call here: the pinned nixpkgs has no
  # `lib.filterStrings`, and `builtins.split` is not a line splitter either,
  # since it interleaves the regex's match lists into its result. `builtins.match`
  # has to span the whole string, which the leading and trailing `.*` are for,
  # so each line is matched on its own; it returns null when a line declares no
  # version and that line's capture groups otherwise, of which there is one.
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

  # The Zig triple this derivation builds for, derived from the platform Nix
  # already resolved rather than from the machine running the build.
  #
  # `zig build install` without `-Dtarget` compiles for the *builder*, so on a
  # cross builder it would install a host-native archive or shared object under
  # a foreign store path, and `installCheckPhase` below could not tell: it only
  # reads file names. `flake.nix` advertises four systems beside x86_64-linux,
  # so this derivation has to name its target rather than refuse the three it
  # does not build on.
  #
  # All three parts are spelled out, and none of them is Nix's own spelling:
  #
  #   * The OS is Zig's enum tag, not Nix's system name. `-Dtarget` parses the
  #     OS with `stringToEnum(Target.Os.Tag, ...)`, where the tag is `macos`;
  #     Nix calls that system `darwin`, and `x86_64-darwin` is
  #     `error.UnknownOperatingSystem` (lib/std/Target/Query.zig:546-554).
  #   * The ABI is not optional. `Target.Abi.default` resolves a bare
  #     `x86_64-linux` to *musl* (lib/std/Target/Query.zig:844-876), while this
  #     derivation's stdenv is glibc, so a triple that left the ABI out would
  #     compile the library against a different C library than the one Nix
  #     gives every other output. The question is therefore asked as
  #     `hostPlatform.isMusl`, which this nixpkgs derives from
  #     `hostPlatform.parsed.abi` and not from anything spelled out here:
  #     `lib/systems/default.nix:442` gives the elaborated platform every
  #     predicate by running `lib/systems/inspect.nix`'s patterns against
  #     `final.parsed`, and `isMusl` (`lib/systems/inspect.nix:429-437`) is the
  #     sum-of-products over `abis.musl`, `musleabi`, `musleabihf`, `muslabin32`
  #     and `muslabi64` (`lib/systems/parse.nix:736-744`). nixpkgs asks the
  #     same question the same way when it names the platform's own libc
  #     (`lib/systems/default.nix:186`).
  #
  #     There is no `linuxLibc` to read instead: the pinned revision defines no
  #     such attribute in `lib/systems/{parse,inspect,default}.nix`, and naming
  #     one fails evaluation with `attribute 'linuxLibc' missing` before any
  #     derivation is built. `isMusl` is false for every ABI nixpkgs parses off
  #     Linux - Darwin's is `abis.unknown`
  #     (`lib/systems/parse.nix:963-964`) - which is why the Darwin arm is
  #     asked first.
  #   * `macos` takes `none`: that is `Target.Abi.default` for every macOS
  #     architecture (lib/std/Target.zig:919-945), and it is the ABI this
  #     repository's own cross matrix already spells
  #     (`aarch64-macos-none`).
  #
  # `builtins.currentSystem` is deliberately not used anywhere: it makes
  # evaluation impure and would reintroduce exactly the evaluator-host
  # assumption this replaces.
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

  # The library file names the shared variant installs, per platform. Zig names
  # a versioned shared object `lib<name>.so.<version>` on ELF targets and
  # `lib<name>.<version>.dylib` on Mach-O, and installs an unversioned link
  # beside the real file (`std.zig.binNameAlloc` and `Step.Compile.create`,
  # lib/std/Build/Step/Compile.zig:488-515). A check that named only the ELF
  # spelling would fail a Darwin build that had just succeeded, so both names
  # are derived here with the platform and interpolated into the check. The
  # static variant is `libspglib.a` on every one of these formats.
  sharedLibrary =
    if stdenv.hostPlatform.isDarwin then "libspglib.dylib" else "libspglib.so";
  sharedLibraryVersioned =
    if stdenv.hostPlatform.isDarwin then "libspglib.${version}.dylib" else "libspglib.so.${version}";
in

stdenv.mkDerivation {
  pname = "spglib";
  version = version;

  # The whole source tree minus build, VCS and development state. Every
  # upstream dotfile and directory is kept: this is the SDK's own source.
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

  # The Zig setup hook registers configure/build/check/install phases. Only the
  # install phase is wanted: `zig build install` compiles the C core itself, and
  # a separate default-flag build would be a second, differently configured
  # build of the same library.
  dontConfigure = true;
  dontBuild = true;
  doCheck = false;
  # Without this the Zig setup hook substitutes its own `zig build test` for the
  # check phase, which is a second, differently-flagged build of the same tree.
  dontUseZigCheck = true;
  # Keep the hook from appending its own prefix, cpu and release flags to the
  # phase below, which passes them explicitly.
  dontAddPrefix = true;
  dontSetZigDefaultFlags = true;

  installPhase = ''
    runHook preInstall

    # Both Zig caches live under the sandbox's TMPDIR, not in the unpacked
    # source tree, so a build never writes into its own input and the cache
    # does not become part of a later layer.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global"
    mkdir -p "$ZIG_LOCAL_CACHE_DIR" "$ZIG_GLOBAL_CACHE_DIR"

    # `-Dtarget` is the platform this derivation is for, not the machine
    # running it: see `zigTarget` above. `-Dcpu=baseline` travels beside it
    # because a triple carries no CPU model.
    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Dtarget=${zigTarget} \
      -Dcpu=baseline \
      -Doptimize=ReleaseSafe \
      -Dlinkage=${linkage}

    runHook postInstall
  '';

  # Verification only. `build.zig` is the single writer of the library, both
  # headers, `spglib.pc` and `share/licenses/spglib/`, so a plain
  # `zig build install` and this derivation produce the same tree; these checks
  # fail the build if that stops being true.
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

    # A consumer that links the archive performs spglib's own maths calls, so
    # `-lm` belongs in the static variant's `Libs`; build.zig decides that per
    # target in needsLibM. Check the name, not the flags.
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