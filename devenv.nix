# Canonical development environment for this SDK: `devenv shell`, or direnv
# through `.envrc`.
#
# `packages` holds tools only. The SDK is a lazy `outputs` entry, so entering the
# shell never builds it; `devenv build outputs.static` (or `.shared`) is the
# packaging route, and it calls the same package.nix the flake calls.
#
# Every task below begins by changing directory to `sdkRoot`. devenv materialises
# a task as a generated program that inherits the *caller's* working directory,
# not this file's directory, so a task run from a scratch project would otherwise
# run `zig build` where there is no `build.zig`, and the provenance checker where
# there is no `tools/`. The root is named here, from this file, rather than read
# from `$DEVENV_ROOT`, which is the project directory and is exactly what fails.
#
# No host path, account, mount or store path is written in this file, and no
# variable the caller supplied is unset. Where the Zig caches go is decided by
# the task body, from what the caller exported: `ZIG_LOCAL_CACHE_DIR` for this
# build's own cache and `ZIG_GLOBAL_CACHE_DIR` for the shared package cache,
# each else `XDG_CACHE_HOME`, else `$TMPDIR`, and a named error when the caller
# exported none of them. Entering the shell decides nothing, because a task run
# through `devenv tasks run` never reads the hooks the shell was entered with.
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

  # This SDK's own directory, from the file that declares it. `builtins.toString`
  # rather than an interpolated `${./.}`: the interpolated form can pull the
  # whole tree into the read-only Nix store, and a store copy is not a tree
  # `zig build` may write a cache into. Every use goes through
  # `lib.escapeShellArg`, so a path containing a space is still one argument.
  sdkRoot = builtins.toString ./.;

  # One shell preamble, reused by every task body rather than restated in seven
  # places: it fills and exports both cache variables, then names the external
  # directories, all of it before the compiler starts. The caller's own export
  # wins - an exported `ZIG_LOCAL_CACHE_DIR` or `ZIG_GLOBAL_CACHE_DIR` is kept
  # exactly as it stands - then `XDG_CACHE_HOME`, then `$TMPDIR`, which fails
  # closed with the variable names if the caller exported none of them. Nothing
  # here can fall back to this checkout's `.zig-cache`.
  #
  # The package cache is filled and named too, because a `zig build` given no
  # `--global-cache-dir` resolves one of its own and this file does not know
  # where that is. `zig-global-cache` carries no `/spglib` subdirectory, unlike
  # the local cache below: that directory holds the fetched packages every
  # graph in this workspace shares, and `build.zig`'s `runConsumer` forwards
  # the global path verbatim for the same reason.
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
    # tools/check_provenance.sh replays the recorded patches and compares the
    # tree against the pinned commit, which needs both.
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
    # One `{ exec = ...; }` per task: devenv's `tasks` option is a flat
    # attribute set of task records, not a map of shell snippets.
    #
    # Every task below that reaches `zig build` names the flags the workspace
    # recipe asks for and the compiler needs: `--cache-dir` and
    # `--global-cache-dir`, with the external directories `cacheSetup` resolved
    # above, then a fixed `-j8`, then `--summary all`, and `"$@"` last, so a
    # caller's own flags stay the final word on the command line.
    # `sdk:provenance` runs no build and names none.
    #
    # `sdk:build` is the one task whose command installs: `zig build` runs the
    # default install step, which writes the delivered library, both headers,
    # `spglib.pc` and the licence material. Its prefix is therefore external to
    # this checkout: `$SPGLIB_INSTALL` when the caller exported it, else the
    # same base the cache resolved to, so the delivery lands beside the cache
    # and never inside the repository. There is no `/tmp` default and no fourth
    # variable, and nothing here sets or unsets one the caller supplied. A
    # caller that wants a different prefix names it in `SPGLIB_INSTALL` or
    # supplies its own `--prefix`: the default is written before `"$@"`, so
    # whatever the caller passes is still the final word on the command line.
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
    # The integrity gate. It needs the full clone: the pinned commit must be
    # reachable, and the checker derives its own repository root from `$0`
    # (tools/check_provenance.sh:21-22), so the change directory below and that
    # line resolve to this same tree rather than to the caller's directory.
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