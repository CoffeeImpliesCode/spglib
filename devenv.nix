# Canonical devenv shell; tasks run from the package root and use external caches.
# Tasks inherit the caller's directory, so each build changes to `sdkRoot`.
# Preserve caller cache settings; fall back to XDG_CACHE_HOME then TMPDIR and fail if unset.
{ pkgs, lib, ... }:

let
  static = pkgs.callPackage ./package.nix {
    zig = pkgs.zig_0_16;
    linkage = "static";
  };
  shared = pkgs.callPackage ./package.nix {
    zig = pkgs.zig_0_16;
    linkage = "dynamic";
  };

  # Resolve the package root without copying the source tree into the Nix store.
  sdkRoot = builtins.toString ./.;

  # Preserve caller cache paths, else use XDG_CACHE_HOME then TMPDIR; never write into the checkout.
  # The local cache is per SDK; the shared package cache serves both build graphs.
  cacheSetup = ''
        ZIG_LOCAL_CACHE_DIR="''${ZIG_LOCAL_CACHE_DIR:-''${XDG_CACHE_HOME:-''${TMPDIR:?set ZIG_LOCAL_CACHE_DIR, XDG_CACHE_HOME or TMPDIR to name an external build cache}}}"
        ZIG_GLOBAL_CACHE_DIR="''${ZIG_GLOBAL_CACHE_DIR:-''${XDG_CACHE_HOME:-''${TMPDIR:?set ZIG_GLOBAL_CACHE_DIR, XDG_CACHE_HOME or TMPDIR to name an external package cache}}/zig-global-cache}"
        export ZIG_LOCAL_CACHE_DIR ZIG_GLOBAL_CACHE_DIR
        cache="$ZIG_LOCAL_CACHE_DIR/spglib/zig-cache"; mkdir -p "$cache" "$ZIG_GLOBAL_CACHE_DIR"
  '';
in

{
  packages = [
    pkgs.zig_0_16
    # Provenance checks require `patch` and `git`.
    pkgs.patch
    pkgs.git
  ];

  assertions = [
    {
      assertion = pkgs.zig_0_16.version == "0.16.0";
      message = ''
        The spglib SDK is built with Zig 0.16.0; the shell provides
        ${pkgs.zig_0_16.version}. Fix devenv.yaml rather than building with a
        different compiler.
      '';
    }
  ];

  outputs = {
    inherit static shared;
    # The SDK's native default is a static linkage.
    default = static;
  };

  tasks = {
    # Task records use external caches, `-j8`, and `--summary all`.
    # `sdk:build` installs outside the checkout; caller arguments remain last.
    # `sdk:provenance` checks the tree without building it.
    "sdk:build" = {
      description = "Compile the native library and the example into $SPGLIB_INSTALL, else the external build cache's spglib/zig-out";
      exec = ''
        cd ${lib.escapeShellArg sdkRoot}
        ${cacheSetup}
        prefix="''${SPGLIB_INSTALL:-"$ZIG_LOCAL_CACHE_DIR"}/spglib/zig-out"
        mkdir -p "$prefix"
        zig build --prefix "$prefix" --cache-dir "$cache" --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" -j8 --summary all "$@"
      '';
    };
    "sdk:test" = {
      description = "Run the behavioural test suite";
      exec = ''
        cd ${lib.escapeShellArg sdkRoot}
        ${cacheSetup}
        zig build test --cache-dir "$cache" --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" -j8 --summary all "$@"
      '';
    };
    "sdk:smoke" = {
      description = "Run the deterministic smoke program";
      exec = ''
        cd ${lib.escapeShellArg sdkRoot}
        ${cacheSetup}
        zig build smoke --cache-dir "$cache" --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" -j8 --summary all "$@"
      '';
    };
    "sdk:check" = {
      description = "Compile the six-target matrix without running anything";
      exec = ''
        cd ${lib.escapeShellArg sdkRoot}
        ${cacheSetup}
        zig build check --cache-dir "$cache" --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" -j8 --summary all "$@"
      '';
    };
    "sdk:check-targets" = {
      description = "The compile-only matrix over every selected target";
      exec = ''
        cd ${lib.escapeShellArg sdkRoot}
        ${cacheSetup}
        zig build check-targets --cache-dir "$cache" --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" -j8 --summary all "$@"
      '';
    };
    "sdk:consumer" = {
      description = "Build and run the separate consumer package";
      exec = ''
        cd ${lib.escapeShellArg sdkRoot}
        ${cacheSetup}
        zig build consumer --cache-dir "$cache" --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" -j8 --summary all "$@"
      '';
    };
    "sdk:fmt-check" = {
      description = "Check the formatting of this fork's own Zig sources";
      exec = ''
        cd ${lib.escapeShellArg sdkRoot}
        ${cacheSetup}
        zig build fmt-check --cache-dir "$cache" --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" -j8 --summary all "$@"
      '';
    };
    # Run the provenance check from the full clone's root.
    "sdk:provenance" = {
      description = "Replay the recorded patches and compare the tree with the pinned commit";
      exec = ''
        cd ${lib.escapeShellArg sdkRoot}
        ./tools/check_provenance.sh
      '';
    };
  };

  enterShell = ''
    echo "spglib 2.7.0 Zig SDK, zig $(zig version)"
    echo "  devenv tasks run sdk:test -- -Doptimize=Debug"
    echo "  devenv build outputs.static   # or outputs.shared"
    echo "  sdk:build                     # --prefix $SPGLIB_INSTALL, else the resolved external build cache"
    echo "  README.zig.md: interface.  README.md: deviations and matrix."
  '';
}