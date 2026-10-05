// Consumer package for the spglib fork.
//
// It proves that a downstream package needs nothing but `dep.module("spglib")`
// and, when it wants the C artifact for its own compilation, `dep.artifact`.
// `src/main.zig` exercises both halves: the typed facade on a cubic
// perovskite, and one direct call into the translated C API exported as
// `spglib.c`, whose answer is fixed by the database upstream ships.
// Run it with `zig build run` from this directory.
//
// `-Druntime=true` builds the dependency for its runtime-loaded route. This
// package then stops linking `dep.artifact("spglib")` into the executable,
// because a module that imports the generated dispatch must not also reference
// the archive: the linker would resolve the same symbols statically and the
// loaded route would quietly be a linked one.
//
// `-Dlinkage=static|dynamic` is the SDK's own delivery option, forwarded
// verbatim and independently of `-Druntime`: it says which artifact the
// dependency builds and installs, while `-Druntime` says how the facade
// reaches it. `-Dlinkage` is given no default here: a null user-input option
// is not passed on at all (`lib/std/Build.zig:435`, `:569-581`), so a caller
// who names neither leaves the SDK's own defaults in charge. Both options are
// read at the SDK's own `build.zig:121-124` and `:138-142`, so there is one
// definition of each value rather than a second one here.
//
// `-fsys=spglib` reaches this package the way it reaches the SDK. It is not a
// `-D` option: `zig build` records it on the build graph before the build
// script runs (`lib/compiler/build_runner.zig:169-171`), and a dependency
// child shares that graph (`lib/std/Build.zig:352`). So the flag the root
// `runConsumer` step forwarded is the same flag `b.systemIntegrationOption`
// reads here and the same one the SDK's own `build.zig:125` reads, whatever
// build either of them was configured from. This package asks that question
// and does not default the answer.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Which delivery of libspglib the dependency builds: a static archive or " ++
            "a shared library. Forwarded to the SDK's own -Dlinkage. Left unset, " ++
            "the option is not passed on and the SDK's own default decides.",
    );
    // `-Druntime` selects whether this dependent reaches spglib through a link
    // line or through the loader. It is spelled here exactly as the SDK spells
    // it, and the root `runConsumer` step forwards it either way, so this
    // package's default and the SDK's default cannot drift apart silently.
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Build the dependency for the runtime-loaded route. Orthogonal to the SDK's own -Dlinkage.",
    ) orelse false;

    // Read, never defaulted: `b.systemIntegrationOption` returns the graph's
    // own value, which `-fsys=spglib` and `zig build --system` have already
    // set and which a plain `zig build run` leaves false. Under it the
    // dependency links the installed library the selected `spglib.pc` names,
    // through the exported module, and builds no artifact of its own, which is
    // what decides the artifact resolution below.
    const use_system_spglib = b.systemIntegrationOption("spglib", .{});

    const spglib_dep = b.dependency("spglib", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        // A `bool` dependency option reaches the dependency's own
        // `b.option(bool, "runtime", ...)` as the scalar "true"/"false"
        // (lib/std/Build.zig:503-509), so the SDK sees the value this package
        // was asked for rather than a fresh default.
        .runtime = runtime_loaded,
    });

    const executable = b.addExecutable(.{
        .name = "consumer",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/main.zig"),
            .imports = &.{.{ .name = "spglib", .module = spglib_dep.module("spglib") }},
        }),
    });

    // The exported module already carries the library in the linked
    // configuration, so linking the artifact is only needed for code that
    // compiles C against the public header. This package does both, which is
    // the arrangement downstream users hit.
    //
    // Two configurations do not link it, and each says why where the decision
    // belongs rather than here:
    //
    //   * `-Druntime`: the facade reaches the library through the dispatch,
    //     and a second, static path to the same symbols in one binary is
    //     exactly what would turn the loaded route back into a linked one with
    //     nothing reporting it.
    //
    //   * `-fsys=spglib`: there is no artifact to resolve. The dependency
    //     builds one only in the branch that compiles `src/`, and in system
    //     mode it links the installed library through the module instead, so
    //     `dep.artifact("spglib")` panics with "unable to find artifact
    //     'spglib'" (`lib/std/Build.zig:1952-1958`). That panic is the
    //     correct answer to a dependent that insists on a native artifact
    //     this configuration does not produce; a consumer proof that tripped
    //     it would be proving an arrangement that does not exist rather than
    //     the one it was asked for.
    if (!runtime_loaded and !use_system_spglib) {
        executable.root_module.linkLibrary(spglib_dep.artifact("spglib"));
    }

    // `zig build run` is the proof: it builds the exported module against the
    // dependency and executes real symmetry searches against the fork. Under
    // `-Druntime` the same step runs the loaded route, and `src/main.zig` is
    // written for it rather than merely compiling under it: it names a
    // provider with `--provider <path>` or `SPGLIB_TEST_PROVIDER` and loads it
    // once before its first call (`src/main.zig:44-49`). No other file is
    // tried, and nothing is constructed or loaded on this build's behalf.
    const run = b.addRunArtifact(executable);
    // `zig build run -- --provider <path>` has to reach the program: the
    // comment above calls this step the proof, and in a `-Druntime` build the
    // program has no provider without that flag or `SPGLIB_TEST_PROVIDER`
    // (`src/main.zig:11-12`). Dropping it leaves the program printing that it
    // wants a flag the caller just passed.
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the consumer against the spglib fork").dependOn(&run.step);

    b.installArtifact(executable);
}
