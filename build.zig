// SPDX-License-Identifier: BSD-3-Clause
//
// Fork-authored. `FORK-LICENSE.md` records the owner's authorization of that
// grant for this file and `COPYING` holds upstream's own BSD 3-Clause text.

const std = @import("std");

const manifest = @import("build.zig.zon");

/// The runtime-loading build half, owned by the API role.
///
/// `createModule` builds the generated dispatch that replaces
/// `translate.createModule()` under `-Druntime`; it also builds the loader-core
/// module and re-exports `LoadSource`/`LoadError` from it. `createCoreModule`
/// builds that same core module for the *linked* branch, where there is no
/// dispatch to carry those types, so the facade's `rt` import is where they
/// come from.
///
/// The two branches must never both call `createCoreModule`. `LoadSource` and
/// `LoadError` are this SDK's public types and have to be the *same* types in
/// one build; a second core instance would be a second, nominally distinct
/// `LoadSource`, and a caller would hand the facade's type to a `load` that
/// expects the other's. `addGraph` below is the only place that calls either.
const graph = @import("runtime/graph.zig");

/// Identity of the upstream release this fork carries. Mirrors UPSTREAM.md;
/// build.zig refuses to configure when build.zig.zon drifts away from it.
const upstream = struct {
    const canonical_url = "https://github.com/spglib/spglib.git";
    const tag = "v2.7.0";
    const commit = "12355c77fb7c505a55f52cae36341d73b781a065";
    const version: std.SemanticVersion = .{ .major = 2, .minor = 7, .patch = 0 };
};

/// The upstream C core, in the order used by src/CMakeLists.txt. The list is
/// explicit rather than globbed so a new upstream translation unit cannot slip
/// into the archive without a decision here.
const core_sources = [_][]const u8{
    "arithmetic.c",
    "cell.c",
    "debug.c",
    "delaunay.c",
    "determination.c",
    "hall_symbol.c",
    "kgrid.c",
    "kpoint.c",
    "magnetic_spacegroup.c",
    "mathfunc.c",
    "msg_database.c",
    "niggli.c",
    "overlap.c",
    "pointgroup.c",
    "primitive.c",
    "refinement.c",
    "site_symmetry.c",
    "sitesym_database.c",
    "spacegroup.c",
    "spg_database.c",
    "spglib.c",
    "spin.c",
    "symmetry.c",
};

/// Targets the fork promises to analyse. `zig build check-targets` compiles the
/// library, the public facade and the example for every one of them.
const check_targets = [_][]const u8{
    "x86_64-linux-gnu",
    "aarch64-linux-gnu",
    "aarch64-macos-none",
    "x86_64-windows-gnu",
    "riscv64-linux-gnu",
    "wasm32-wasi",
};

/// Test roots. They are compiled into native test runs and into the
/// compile-only analysis, so a facade entry point used only by the analysis
/// still has its body checked for every target.
const test_sources = [_][]const u8{
    "zig/tests/facade_test.zig",
    "zig/tests/c_api_test.zig",
    "zig/tests/api_surface.zig",
};

/// C sources are compiled with the language level upstream pins in CMake
/// (`CMAKE_C_STANDARD 11`, `CMAKE_C_EXTENSIONS OFF`) plus the hidden default
/// visibility upstream sets. SPGINFO/SPGWARNING match the upstream defaults;
/// they only print when SPGLIB_INFO or SPGLIB_WARNING is set in the environment.
const release_flags = [_][]const u8{
    "-std=c11",
    "-fvisibility=hidden",
    "-DSPGINFO",
    "-DSPGWARNING",
};

const debug_flags = [_][]const u8{
    "-std=c11",
    "-fvisibility=hidden",
    "-DSPGINFO",
    "-DSPGWARNING",
    "-DSPGDEBUG",
};

/// Everything a consumer needs: the translated C declarations and the Zig
/// facade that sits on top of them.
const SpglibPackage = struct {
    module: *std.Build.Module,
    /// Null in `-fsys=spglib` mode, where the library comes from the system.
    artifact: ?*std.Build.Step.Compile,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Static stays the default: it is what this package has always delivered
    // and what `zig/consumer` proves. `dynamic` is the second delivered
    // variant, and the two differ in the install tree only by the library
    // files and the two lines of `spglib.pc` that name them; see
    // `installNative`. Both are built from these sources with no system
    // library anywhere, and neither is a wrapper around the other.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Deliver libspglib as a static archive (default) or as a shared library",
    ) orelse .static;
    const use_system_spglib = b.systemIntegrationOption("spglib", .{});

    // `-Druntime` is how the facade reaches spglib; `-Dlinkage` is which
    // artifact this build delivers. They are orthogonal, so every combination
    // of the two is legal and none of them skips delivery: under `-Druntime`
    // the archive or shared object is still built and still installed, and a
    // caller names the provider explicitly with `load(source)`, which may be
    // the one this tree built or another build's or another prefix's.
    //
    // It defaults to false, which is the configuration this package has always
    // built: `zig build`, `test`, `check`, `check-targets` and `zig/consumer`
    // all keep linking the library directly.
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve the native entry points at run time through the loader instead of linking them. " ++
            "The facade keeps the same translated header and the same public types; " ++
            "a caller names its provider explicitly with load(source). Orthogonal to -Dlinkage.",
    ) orelse false;
    // `-Druntime` and `-fsys=spglib` are refused together, out loud and in one
    // place only, in `addSpglib`, which is where the two modes meet. The reason
    // is in the headers rather than in this build's taste; the comment there
    // gives it.

    const package_version = std.SemanticVersion.parse(manifest.version) catch {
        @panic("build.zig.zon: .version is not a semantic version");
    };
    if (package_version.order(upstream.version) != .eq) {
        @panic("build.zig.zon .version no longer matches the pinned upstream release in UPSTREAM.md");
    }

    const c_flags: []const []const u8 = if (optimize == .Debug) &debug_flags else &release_flags;

    // `src/version.h.in` is configured, never hand-edited. The values come from
    // the manifest and the pinned commit so the header always matches UPSTREAM.md.
    const version_header = b.addWriteFiles().add("version.h", b.fmt(
        \\// Generated by build.zig from src/version.h.in. Do not edit.
        \\// Upstream: {s} ({s})
        \\#ifndef __version_H__
        \\#define __version_H__
        \\
        \\#define SPGLIB_MAJOR_VERSION {d}
        \\#define SPGLIB_MINOR_VERSION {d}
        \\#define SPGLIB_MICRO_VERSION {d}
        \\#define SPGLIB_VERSION "{f}"
        \\#define SPGLIB_VERSION_FULL "{f}"
        \\#define SPGLIB_COMMIT "{s}"
        \\
        \\#endif
        \\
    , .{
        upstream.tag,
        upstream.commit,
        package_version.major,
        package_version.minor,
        package_version.patch,
        package_version,
        package_version,
        upstream.commit,
    }));

    const spglib = addSpglib(b, .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .c_flags = c_flags,
        .use_system = use_system_spglib,
        .runtime_loaded = runtime_loaded,
        .version_header = version_header,
        .register_module = true,
    });

    if (spglib.artifact) |artifact| {
        installNative(b, artifact, .{
            .target = target,
            .linkage = linkage,
            .version = package_version,
            .version_header = version_header,
        });
    }

    // ---- Tests -------------------------------------------------------------

    const test_step = b.step("test", "Run the native behaviour tests");
    // Holder for the native target options; the test roots are created per file.
    const native_tests = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    for (test_sources) |test_file| {
        const unit_test = addTestArtifact(b, test_file, "test", spglib.module, native_tests);
        test_step.dependOn(&b.addRunArtifact(unit_test).step);
    }

    // ---- Runnable example -------------------------------------------------

    const smoke_step = b.step("smoke", "Run the deterministic spglib example");
    const smoke_exe = addExecutableArtifact(b, "zig/examples/smoke.zig", "spglib-smoke", spglib.module, native_tests);
    const run_smoke = b.addRunArtifact(smoke_exe);
    smoke_step.dependOn(&run_smoke.step);
    if (b.args) |args| run_smoke.addArgs(args);

    // ---- Analysis without running ----------------------------------------

    // `zig build check` never executes a target binary. It compiles the library,
    // every public facade entry point and the example, so a foreign target can
    // be analysed on any host.
    const check_step = b.step("check", "Compile the library, the public facade and the example without running them");
    check_step.dependOn(analyze(b, "analyze-native", spglib.module, native_tests));

    const check_targets_step = b.step("check-targets", "Compile the library, the public facade and the example for the six supported targets");
    for (check_targets) |triple| {
        const cross_target = b.resolveTargetQuery(parseTriple(b, triple));
        const cross_package = addSpglib(b, .{
            .target = cross_target,
            .optimize = optimize,
            .linkage = linkage,
            .c_flags = c_flags,
            // The system library path is meaningless for a foreign target, so
            // the cross matrix always builds from the in-tree sources.
            .use_system = false,
            // The cross matrix analyses whichever configuration was asked for,
            // so `-Druntime=true` gets the same six-target compile coverage a
            // linked build does. It is not forced off: a check that quietly
            // analysed the other mode would be a check of something nobody
            // asked for.
            .runtime_loaded = runtime_loaded,
            .version_header = version_header,
            .register_module = false,
        });
        const cross_host = b.createModule(.{
            .target = cross_target,
            .optimize = optimize,
            .link_libc = true,
        });
        check_targets_step.dependOn(analyze(b, b.fmt("analyze-{s}", .{triple}), cross_package.module, cross_host));
    }

    // ---- Consumer package proof ------------------------------------------

    // zig/consumer is a separate package with its own manifest. It depends on
    // this one by path, imports `dep.module("spglib")` and additionally links
    // `dep.artifact("spglib")`.
    // It does not link that artifact under `-Druntime` or `-fsys=spglib`, for
    // reasons that belong to the dependency and are read there from the same
    // values this build forwards below.
    //
    // It cannot be a dependency of this manifest: that would make the root
    // package depend on a package whose manifest depends on the root, which is
    // a cycle, and it would also constrain every other step of this build to
    // whatever the consumer asked for. So the consumer is built as its own
    // `zig build` in zig/consumer, with the resolved target, cpu,
    // optimization, runtime and linkage selections, the system mode, the
    // executor switches, the job count, both cache directories and the
    // caller's trailing arguments forwarded on the command line. It is run
    // when this host can execute the selected target and installed when it
    // cannot, which is `hostCanExecute` rather than a query predicate: a
    // cross-compiled consumer binary cannot run here, and a native one can
    // run under an enabled executor.
    const consumer_step = b.step("consumer", "Build or run the consumer package in zig/consumer against the exported module and artifact");
    consumer_step.dependOn(&runConsumer(b, target, optimize, runtime_loaded, linkage, use_system_spglib).step);

    // ---- Formatting -------------------------------------------------------

    // `runtime` is in scope: `runtime/graph.zig` is a build-runner import, so a
    // malformed one is a configure-time failure rather than a compile-time one,
    // and it is worth keeping formatted like everything else. The driver's four
    // common core files live there too and are formatted by the same step.
    const fmt_paths = [_][]const u8{ "build.zig", "build.zig.zon", "zig", "runtime" };
    const fmt_check = b.step("fmt-check", "Check Zig formatting");
    fmt_check.dependOn(&b.addFmt(.{ .paths = &fmt_paths, .check = true }).step);
    const fmt = b.step("fmt", "Format Zig sources in place");
    fmt.dependOn(&b.addFmt(.{ .paths = &fmt_paths }).step);
}

/// Licence and provenance records installed beside every delivered library.
///
/// A binary redistribution carries an obligation, and a repository being
/// private removes none of it, so the install tree carries the same records
/// the repository does: upstream's own `COPYING` verbatim, the per-file
/// inventory in `NOTICE.md`, the owner-authorised grant for the fork's own
/// additions in `FORK-LICENSE.md`, and the pinned upstream identity in
/// `UPSTREAM.md`. `CHANGELOG.md` and `FORK-NOTES.md` stay out: they are the
/// fork's development record, not something a dependent needs at link time.
const licence_material = [_][]const u8{
    "COPYING",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
};

const licence_dest_dir = "share/licenses/spglib";

/// Whether this target's libc leaves the C maths routines in a separate
/// library. libm is separate on the glibc and BSD targets and is part of libc
/// on macOS, Windows and wasi, where linking it would fail.
///
/// The C library link and the installed `spglib.pc` both ask this, so the
/// metadata cannot disagree with the archive it describes.
fn needsLibM(target: std.Build.ResolvedTarget) bool {
    return switch (target.result.os.tag) {
        .linux, .freebsd, .netbsd, .openbsd, .dragonfly, .illumos => true,
        else => false,
    };
}

const InstallOptions = struct {
    target: std.Build.ResolvedTarget,
    linkage: std.builtin.LinkMode,
    version: std.SemanticVersion,
    version_header: std.Build.LazyPath,
};

/// Installs the complete native delivery: the library, its public headers, the
/// link metadata a C or pkg-config consumer needs, and the licence material
/// that travels with it.
///
/// Both variants land in the same layout and differ only in the library files
/// and in the two lines of `spglib.pc` that describe them:
///
///   lib/libspglib.a                     `-Dlinkage=static`, the default
///   lib/libspglib.so, libspglib.so.2     `-Dlinkage=dynamic`
///   include/spglib.h                    upstream's only installed header
///   include/spglib/version.h            the generated version macros
///   lib/pkgconfig/spglib.pc             link and compile metadata
///   share/licenses/spglib/...           licence and provenance records
///
/// There is no data install: `src/spg_database.c`, `src/msg_database.c` and
/// `src/sitesym_database.c` carry the crystallographic tables as static
/// arrays (`src/spg_database.c:10`), so nothing under `database/` is read at
/// build or run time. Upstream installs no data either.
fn installNative(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    options: InstallOptions,
) void {
    b.installArtifact(artifact);
    // Installing the headers also puts them on the include path of every
    // compilation that links the artifact.
    artifact.installHeader(b.path("include/spglib.h"), "spglib.h");
    artifact.installHeader(options.version_header, "spglib/version.h");

    const pkg_config = b.addWriteFiles().add("spglib.pc", pkgConfigContents(b, options));
    const pkg_config_install = b.addInstallLibFile(pkg_config, "pkgconfig/spglib.pc");
    // `addWriteFiles` is a step of its own and `addInstallFileWithDir` adds no
    // edge to it, so both directions are explicit here: the install waits for
    // the generated file, and the install step is told about the install.
    // `b.installFile` (Build.zig:1675) and `b.installArtifact`
    // (Build.zig:1660) attach their own steps by hand for the same reason.
    pkg_config.addStepDependencies(&pkg_config_install.step);
    b.getInstallStep().dependOn(&pkg_config_install.step);

    for (licence_material) |file| {
        const installed = b.addInstallFile(b.path(file), b.fmt("{s}/{s}", .{ licence_dest_dir, file }));
        b.getInstallStep().dependOn(&installed.step);
    }
}

/// The installed `spglib.pc`.
///
/// Upstream's own template (cmake/spglib.pc.in) writes the absolute
/// `@CMAKE_INSTALL_FULL_LIBDIR@` and `@CMAKE_INSTALL_FULL_INCLUDEDIR@` paths
/// a distribution install bakes in. That is wrong for a relocatable prefix, so
/// this one derives `prefix` from the file's own location: the same tree then
/// works under `--prefix <dir>` and inside a Nix store path.
///
/// The names follow upstream. `Name: spglib` is the project name the template
/// substitutes (`Name: @PROJECT_NAME@`) and the file name upstream installs
/// (CMakeLists.txt:142-144). The library is `-lspglib`, not upstream's
/// `-lsymspg` (cmake/spglib.pc.in:4, CMakeLists.txt:108-113), because this
/// package's artifact is named `spglib` and `zig/consumer/build.zig` resolves
/// it as `dep.artifact("spglib")`.
///
/// Two lines carry a real decision rather than cosmetics:
///
///   * `Libs` lists `-lm` for the static archive, because a consumer that
///     links the archive performs spglib's own maths calls itself. The shared
///     library resolved libm when it was linked, so there `-lm` is
///     `Libs.private` and a plain `pkg-config --libs` stays correct. Which of
///     the two a target needs is the same `needsLibM` decision the library
///     link makes, not a guess.
///   * `Cflags` adds `-DSPG_STATIC_LIBRARY` for the static variant, mirroring
///     upstream's own rule at src/CMakeLists.txt:6-10 where
///     `SPG_STATIC_LIBRARY` is a PUBLIC definition whenever the library is
///     built static. Without it a Windows consumer of the archive sees
///     `__declspec(dllimport)` on every declaration and fails to link. The
///     dynamic variant leaves it undefined, which is what makes the same
///     header declare `dllimport` under MSVC.
fn pkgConfigContents(b: *std.Build, options: InstallOptions) []const u8 {
    const libm = needsLibM(options.target);
    const link_flags = if (options.linkage == .static)
        b.fmt("Libs: -L${{libdir}} -lspglib{s}\n", .{if (libm) " -lm" else ""})
    else if (libm)
        "Libs: -L${libdir} -lspglib\nLibs.private: -lm\n"
    else
        "Libs: -L${libdir} -lspglib\n";

    return b.fmt(
        \\prefix=${{pcfiledir}}/../..
        \\exec_prefix=${{prefix}}
        \\libdir=${{exec_prefix}}/lib
        \\includedir=${{prefix}}/include
        \\
        \\Name: spglib
        \\Description: The spglib library
        \\Version: {f}
        \\URL: {s}
        \\{s}Cflags: -I${{includedir}}{s}
        \\
    , .{
        options.version,
        upstream.canonical_url,
        link_flags,
        if (options.linkage == .static) " -DSPG_STATIC_LIBRARY" else "",
    });
}

/// Compiles, but never runs, everything that makes up the public surface.
fn analyze(
    b: *std.Build,
    step_name: []const u8,
    spglib_module: *std.Build.Module,
    test_host: *std.Build.Module,
) *std.Build.Step {
    const step = b.step(
        step_name,
        "Compile-only analysis of the library, the public facade and the example",
    );

    for (test_sources) |test_file| {
        const unit_test = addTestArtifact(b, test_file, b.fmt("{s}-", .{step_name}), spglib_module, test_host);
        step.dependOn(&unit_test.step);
    }

    const smoke = addExecutableArtifact(
        b,
        "zig/examples/smoke.zig",
        b.fmt("{s}-smoke", .{step_name}),
        spglib_module,
        test_host,
    );
    step.dependOn(&smoke.step);

    return step;
}

/// Resolves a target triple written the way `zig build -Dtarget=` writes it.
///
/// A triple is parsed into `std.Target.Query` through `Query.ParseOptions`,
/// whose `arch_os_abi` field (lib/std/Target/Query.zig:165) holds the string.
/// `Query` itself (Query.zig:15-54) holds the resolved `cpu_arch`, `os_tag`,
/// `abi` and the rest. `std.Build.parseTargetQuery` (Build.zig:1423) is the
/// entry point `standardTargetOptionsQueryOnly` uses at Build.zig:1500, so
/// this and `-Dtarget=` agree on what a triple means.
fn parseTriple(b: *std.Build, triple: []const u8) std.Target.Query {
    return std.Build.parseTargetQuery(.{ .arch_os_abi = triple }) catch |err| {
        @panic(b.fmt("build.zig: {s} is not a target triple: {s}", .{ triple, @errorName(err) }));
    };
}

/// Invokes the consumer package as its own `zig build` in zig/consumer.
///
/// The consumer is a separate package on purpose: a manifest dependency would
/// close a cycle, because its manifest points back at this package by path.
/// Running it as a separate build keeps that proof real, the module and
/// artifact exports honest, and every other step of this build free of the
/// consumer's constraints.
///
/// `-Druntime` is forwarded explicitly in both directions of its own value, so
/// the nested build can never quietly fall back to the package default: a
/// consumer run under `-Druntime=true` proves the loaded route, and one under
/// `-Druntime=false` proves the linked route. The nested package reads it with
/// its own `b.option` and hands it to `b.dependency("spglib", ...)` as a
/// dependency option, which the SDK's `b.option(bool, "runtime", ...)` reads
/// back (`addUserInputOptionFromArg` carries a `bool` as the scalar `"true"` or
/// `"false"`, Build.zig:503-509).
///
/// `-Dlinkage` is forwarded the same way, and independently of it: `static`
/// and `dynamic` are two real deliveries of the same sources, so a consumer
/// run has to say which one it is proving. The nested package reads it with
/// its own `b.option(std.builtin.LinkMode, "linkage", ...)` and hands it to
/// `b.dependency("spglib", ...)` unchanged, so each side has one definition
/// of the value rather than two defaults kept in step by hand.
///
/// `-fsys=spglib` and `-fno-sys=spglib` are forwarded, and they are the one
/// forwarded argument that is not a `-D` option. `zig build` parses
/// `-fsys=<name>` and `-fno-sys=<name>` before the build script runs and
/// records each on the graph (`lib/compiler/build_runner.zig:169` and `:172`),
/// so there is no `b.option` to read here and no value to hand a dependency:
/// the flag *is* the interface. It reaches the dependency inside the nested
/// build because a dependency child shares the parent's `graph` struct
/// (`Build.createChild`, `lib/std/Build.zig:352`), so the flag the nested
/// build script was given is the same flag `b.systemIntegrationOption` reads
/// there. Both spellings go down for the same reason as `-Druntime` and
/// `-Dlinkage` above: a nested build given only the positive form falls back
/// to its own default for a caller that asked for the in-tree mode, and a
/// nested build given neither reports success for a configuration nobody
/// named. There is no `-D` alternative on either side.
///
/// `run` or `install` is decided by `hostCanExecute` below, which asks the
/// same question `std.Build.Step.Run` asks about the artifact it is about to
/// spawn, so a nested build this host can execute is run rather than installed
/// and one it cannot is compiled and installed instead. The executor switches,
/// the job count, both cache directories, the install prefix and the caller's
/// own trailing arguments follow the same rule: every resolved choice of this
/// graph is handed to the nested one, so the consumer that proves this package
/// is the consumer of the configuration that was asked for.
fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    runtime_loaded: bool,
    linkage: std.builtin.LinkMode,
    use_system_spglib: bool,
) *std.Build.Step.Run {
    const query = target.query;
    // `addArg` copies each argument, so these temporaries can go right after.
    const triple = query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    const cpu = query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    // `b.graph.zig_exe` is the compiler running this build script, so the
    // nested build is the same toolchain rather than whatever is on PATH.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path("zig/consumer"));
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    // One `-Dkey=value` argument each, which is the form the build runner
    // parses.
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    // The nested build is its own graph with its own `standardOptimizeOption`,
    // and it configures the dependency, so forwarding the requested mode here
    // would put the facade module back at `-O Debug` and reintroduce the
    // extern-call ABI defect for the consumer. See `zigCallerOptimize`.
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(zigCallerOptimize(optimize) orelse optimize)}));
    // Written out whether it is true or false. Passing `-Druntime=true` only
    // when it is set would leave the nested build's own default in charge of
    // the false case, and the two could then disagree the moment either
    // default changed.
    run.addArg(b.fmt("-Druntime={s}", .{if (runtime_loaded) "true" else "false"}));
    // The delivery, written out in both directions for the same reason as
    // `-Druntime` above and independently of it. The nested package gives
    // `-Dlinkage` no default, so leaving it out would leave the dependency's
    // own default in charge (`std/Build.zig:435`, `:569-581` record a
    // dependency argument only when it carries a value), and a run that meant
    // to prove the shared object would have linked the static archive.
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(linkage)}));
    // The system selection, written out in both directions. Both are recorded
    // on the graph before any build script runs
    // (`lib/compiler/build_runner.zig:169`, `:172`), so this file reads no
    // option to forward and has no value to hand a dependency. The negative
    // form is what says "the caller chose the in-tree mode" rather than
    // leaving that to a default this file does not own.
    run.addArg(if (use_system_spglib) "-fsys=spglib" else "-fno-sys=spglib");
    // The executor switches this build resolved, so the nested build runs under
    // the same one `hostCanExecute` decided with: `-fwasmtime` is how a WASI
    // consumer executes here, and `--libc-runtimes`
    // (`lib/compiler/build_runner.zig:323-325`) is the QEMU integration's
    // dynamic-linker support, which the `qemu_fixes_dl` field there also
    // depends on. Written only when enabled: `-fno-…` is the build runner's
    // own default for each of them, and naming it would pin a default this
    // build did not resolve.
    if (b.enable_darling) run.addArg("-fdarling");
    if (b.enable_qemu) run.addArg("-fqemu");
    if (b.enable_rosetta) run.addArg("-frosetta");
    if (b.enable_wasmtime) run.addArg("-fwasmtime");
    if (b.enable_wine) run.addArg("-fwine");
    if (b.libc_runtimes_dir) |runtimes| run.addArgs(&.{ "--libc-runtimes", runtimes });
    // The nested build carries this workspace's job count in its own command
    // line, for the reason every `zig build` entry in `devenv.nix` writes one:
    // nothing can append a `-j` to a `Run` step's command, so a nested build
    // left to derive its own width takes `cpu_count - 1`
    // (`std/Io/Threaded.zig:1639`) instead, and the consumer this step proves
    // then compiles at a different width from the build that asked for it --
    // and at a different width again on whichever machine runs the gate.
    // `--summary all` is the step list `AGENTS.md:157-159` reads every gate
    // against, and it is the two-token spelling the runner documents
    // (`lib/compiler/build_runner.zig:262`, `:1639-1640`).
    run.addArg("-j8");
    run.addArgs(&.{ "--summary", "all" });
    // When the outer build was given an explicit cache directory, the nested
    // one gets a subdirectory of it rather than sharing it: two build graphs
    // must not write the same manifest directory. A null `path` means "the
    // current directory", and the working directory above is already the
    // consumer package, so the default is right. Two arguments, not one
    // `--cache-dir=...`: that is the form the build system emits to the
    // compiler itself (lib/std/Build/Step/Compile.zig:1475-1476).
    if (b.cache_root.path) |cache| {
        run.addArg("--cache-dir");
        run.addArg(b.fmt("{s}/consumer", .{cache}));
    }
    // The global cache is forwarded as it stands, with no `/consumer`
    // subdirectory: it holds fetched packages, which every graph in this
    // workspace shares by design, and a subdirectory would make the nested
    // build refetch what the outer build already fetched. Same read, same
    // two-token spelling the build system itself emits
    // (`lib/std/Build/Step/Compile.zig:1478-1479`). Without it a global cache
    // the caller selected on the outer command line is invisible to the
    // nested build, which then resolves one of its own.
    if (b.graph.global_cache_root.path) |global_cache| {
        run.addArg("--global-cache-dir");
        run.addArg(global_cache);
    }
    // The install prefix this invocation resolved, handed on when the caller
    // named one. A nested `zig build` with no `--prefix` installs into
    // `zig/consumer/zig-out`, a build artefact inside the consumer package,
    // instead of the directory the caller asked for. A relative `--prefix`
    // would resolve against the working directory set above, `zig/consumer`,
    // rather than against this build's root, so it is made absolute first;
    // `DESTDIR` needs no forwarding, because the nested build inherits the
    // environment this one ran with.
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch @panic("OOM");
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) {
        const prefix = if (std.fs.path.isAbsolute(b.install_prefix))
            b.install_prefix
        else
            b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix });
        run.addArg("--prefix");
        run.addArg(prefix);
    }
    // The caller's own arguments, last and behind `--`. `zig build consumer --
    // …` collects them in `b.args`, the nested build's `run` step hands
    // `b.args` to the program (`zig/consumer/build.zig:125`), and that program
    // is the consumer check: under `-Druntime=true` it names a provider with
    // `--provider <path>` (`zig/consumer/src/main.zig:125-133`) and refuses to
    // invent one, printing that it wants a flag the caller just passed
    // (`:138-143`). Every argument above is this package's own bookkeeping
    // with the nested build; an argument the caller typed is forwarded
    // verbatim or not at all, and this `--` has to follow all of them because
    // it ends the nested build's option parsing.
    if (b.args) |args| {
        run.addArg("--");
        run.addArgs(args);
    }
    // The nested build is the step's only observable effect.
    run.has_side_effects = true;
    return run;
}

/// True when this build can execute `target`'s binaries.
///
/// `std.zig.system.getExternalExecutor` (`lib/std/zig/system.zig:42`) is the
/// predicate `std.Build.Step.Run` asks about the artifact it is about to spawn
/// (`lib/std/Build/Step/Run.zig:1268`). That replaces a predicate which could
/// not answer it: `Target.Query.isNative()`
/// (`lib/std/Target/Query.zig:392-398`) is `isNativeTriple() and ofmt == null`,
/// and `isNativeTriple()` demands `cpu_arch`, `os_tag` and `abi` all be null,
/// so `-Dtarget=x86_64-linux-gnu` was never "native" on an x86_64 Linux host:
/// `consumer` installed the nested build instead of running it, on the one
/// target this repository's own cross matrix lists first. This one asks about
/// the *resolved* target, which is the same fact `Run` is given.
///
/// Both options `Run` fills in from the artifact are filled in here from the
/// same facts: the consumer executable links libc because
/// `zig/consumer/build.zig` builds it with `link_libc = true`, and QEMU
/// reaches a foreign dynamic linker only with `--libc-runtimes`. Its
/// `need_cross_libc` (`lib/std/Build/Step/Run.zig:1264-1266`) additionally
/// asks for `exe.linkage == .dynamic` on the musl half, and that executable is
/// built with `b.addExecutable` and no linkage, so that field is null there
/// and the half never contributes.
///
/// An external executor counts as available only when the build runner was
/// told it may use one: `-fwasmtime`, `-fqemu`, `-fwine` and `-fdarling` are
/// the build runner's own switches for that
/// (`lib/compiler/build_runner.zig:388-407`, exposed as `b.enable_wasmtime`
/// and friends, `lib/std/Build.zig:71-79`), and each names a separate program
/// whose presence on `PATH` this script cannot know. `-frosetta` names no
/// program and `std.Build` never reads `enable_rosetta` for a decision — the
/// only other mention is `createChild` copying it (`:403`) — so it is
/// forwarded for fidelity and never gates the decision. A target that still
/// has no executor builds and installs, which is compile evidence and nothing
/// more.
fn hostCanExecute(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const host = &b.graph.host.result;
    const candidate = &target.result;
    const options: std.zig.system.GetExternalExecutorOptions = .{
        .allow_darling = b.enable_darling,
        .allow_qemu = b.enable_qemu,
        .allow_wasmtime = b.enable_wasmtime,
        .allow_wine = b.enable_wine,
        .qemu_fixes_dl = candidate.isGnuLibC() and b.libc_runtimes_dir != null,
        .link_libc = true,
    };
    return switch (std.zig.system.getExternalExecutor(b.graph.io, host, candidate, options)) {
        .native, .rosetta => true,
        // `Run`'s QEMU arm (`lib/std/Build/Step/Run.zig:1290-1314`) appends
        // `-L <runtime triple>` for a cross libc target and, with
        // `b.libc_runtimes_dir` unset, `failForeign` on `--libc-runtimes`
        // (`:1310`) instead of skipping the run. So on this target the missing
        // directory is not a skip but a failure, and the answer has to be no.
        //
        // `qemu_fixes_dl` above cannot carry that: `getExternalExecutor` enters
        // the QEMU arm for a foreign CPU on `!cpu_ok` alone
        // (`lib/std/zig/system.zig:95`), whatever that option says, so the
        // returned executor is `.qemu` in exactly the case the option stops
        // describing. `isGnuLibC` is the whole of `Run`'s `need_cross_libc`
        // here, and the two now test the same fact.
        .qemu => !candidate.isGnuLibC() or b.libc_runtimes_dir != null,
        // Reachable only for an executor the switches above enabled, each of
        // which `Run` gates on the same switch and nothing else.
        .wine, .wasmtime, .darling => true,
        // Same OS and CPU with no dynamic linker to load, or an architecture
        // and system this build has no enabled executor for.
        .bad_dl, .bad_os_or_cpu => false,
    };
}

fn addTestArtifact(
    b: *std.Build,
    test_file: []const u8,
    name_prefix: []const u8,
    spglib_module: *std.Build.Module,
    test_host: *std.Build.Module,
) *std.Build.Step.Compile {
    return b.addTest(.{
        .name = b.fmt("{s}{s}", .{ name_prefix, std.fs.path.stem(test_file) }),
        .root_module = b.createModule(.{
            .target = test_host.resolved_target,
            .optimize = zigCallerOptimize(test_host.optimize),
            .link_libc = true,
            .root_source_file = b.path(test_file),
            .imports = &.{.{ .name = "spglib", .module = spglib_module }},
        }),
    });
}

fn addExecutableArtifact(
    b: *std.Build,
    source_file: []const u8,
    name: []const u8,
    spglib_module: *std.Build.Module,
    test_host: *std.Build.Module,
) *std.Build.Step.Compile {
    // A Zig module's root is its root source file's directory, so an example
    // under `zig/examples/` cannot reach `zig/tests/` with a relative import.
    // The fixtures arrive as a named module instead.
    const fixtures = b.createModule(.{
        .root_source_file = b.path("zig/tests/fixtures.zig"),
        .target = test_host.resolved_target,
        .optimize = zigCallerOptimize(test_host.optimize),
        .link_libc = true,
        // `fixtures.zig` publishes `pub const Cell = spglib.Cell`, so it needs
        // the facade module itself, exactly as the test roots already have it.
        .imports = &.{.{ .name = "spglib", .module = spglib_module }},
    });
    return b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .target = test_host.resolved_target,
            .optimize = zigCallerOptimize(test_host.optimize),
            .link_libc = true,
            .root_source_file = b.path(source_file),
            .imports = &.{
                .{ .name = "spglib", .module = spglib_module },
                .{ .name = "fixtures", .module = fixtures },
            },
        }),
    });
}

/// The optimisation mode for the Zig side of a native test or example.
///
/// Zig 0.16.0 at `-O Debug` mis-assigns the SSE registers of an `extern "C"`
/// call that has seven or more integer-class arguments: the constants land in
/// xmm6 and xmm7 while the callee reads xmm0 and xmm1. Only the floating-point
/// arguments are wrong; spilled integers arrive correctly. Every spglib entry
/// point with more than six integer-class arguments takes a `double`, so every
/// one of them receives a garbage tolerance and fails inside `get_dataset`.
/// A standalone C caller against the same archive is correct in both modes,
/// which is what makes this a compiler defect rather than a binding defect.
///
/// The C library is untouched: it keeps the requested optimisation and the
/// `-DSPGDEBUG` the Debug flags carry, so what the tests exercise is still the
/// debug build of the C. Only the Zig marshalling, which the compiler gets
/// wrong, is built optimised.
fn zigCallerOptimize(host: ?std.builtin.OptimizeMode) ?std.builtin.OptimizeMode {
    return if (host != null and host.? == .Debug) .ReleaseSafe else host;
}

const SpglibOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    c_flags: []const []const u8,
    use_system: bool,
    /// `-Druntime`. Selects the dispatch; orthogonal to `linkage`.
    runtime_loaded: bool,
    version_header: std.Build.LazyPath,
    register_module: bool,
};

fn addSpglib(b: *std.Build, options: SpglibOptions) SpglibPackage {
    // `-fsys=spglib` and `-Druntime=true` are refused together, out loud.
    //
    // The reason is in the headers, not in policy. This package's aggregate
    // translation unit is `#include "spglib.h"` plus `#include "version.h"`,
    // and the version macros live only in the header generated from
    // `src/version.h.in`; upstream's installed `spglib.h` includes nothing but
    // `<stddef.h>` (`include/spglib.h:51`) and defines no version macro of its
    // own. A system-mode translation therefore has no `SPGLIB_MAJOR_VERSION`,
    // and the runtime dispatch validates a loaded provider against
    // `dispatch.SPGLIB_MAJOR_VERSION` by calling `spg_get_major_version()`.
    //
    // The alternative would be to put this repository's generated `version.h`
    // back on the translation line in system mode, which is the exact
    // arrangement the comment above rules out: binding a header from one source
    // to a library from another and calling it a system build.
    if (options.use_system and options.runtime_loaded) {
        @panic("-fsys=spglib cannot be combined with -Druntime=true: the installed spglib.h carries no version macros, and the runtime dispatch validates a provider against them. Build spglib from these sources to use the runtime route.");
    }

    // The translation unit for the public API. The aggregate header pulls in
    // the complete public header plus the generated version macros so the Zig
    // bindings cover the whole C surface, not a hand-written subset.
    //
    // In `-fsys=spglib` mode the aggregate includes the bare <spglib.h> and
    // adds no in-tree include path, so the translation sees the header that
    // is actually installed next to the library it links. That is the name
    // upstream installs: include/CMakeLists.txt attaches spglib.h to a
    // FILE_SET HEADERS whose INSTALL_INTERFACE is ${CMAKE_INSTALL_INCLUDEDIR}
    // with no BASE_DIRS override, cmake/spglib.pc.in declares
    // `Cflags: -I@CMAKE_INSTALL_FULL_INCLUDEDIR@`, .distro/spglib.spec
    // packages %{_includedir}/spglib.h, and ruby/extconf.rb probes for the
    // bare "spglib.h". The include directory reaches the translation line
    // from the `spglib.pc` this build asks for below, because a Step.TranslateC
    // keeps its own system-library list and a module's `linkSystemLibrary`
    // never reaches it. A `spglib/` prefix would only ever be a guess about a
    // distribution this package has not verified. Translating this
    // repository's 2.7.0 header against an older system library would
    // silently bind the wrong ABI.
    const aggregate = b.addWriteFiles().add(if (options.use_system)
        "spglib_system.h"
    else
        "spglib_aggregate.h", if (options.use_system)
        \\#ifndef SPGLIB_SYSTEM_AGGREGATE_H
        \\#define SPGLIB_SYSTEM_AGGREGATE_H
        \\#include <spglib.h>
        \\#endif
    else
        \\#ifndef SPGLIB_AGGREGATE_H
        \\#define SPGLIB_AGGREGATE_H
        \\#include "spglib.h"
        \\#include "version.h"
        \\#endif
    );

    const translate_c = b.addTranslateC(.{
        .root_source_file = aggregate,
        .target = options.target,
        .optimize = options.optimize,
        .link_libc = true,
    });
    if (!options.use_system) {
        // The translation sees the same real headers the library is compiled
        // from: this repository's `include/spglib.h` and the generated
        // `version.h`. An installed header is not on a compile line, so both
        // directories are on both the translation line and the C library line
        // below, and the aggregate's bare `#include "version.h"` needs the
        // generated directory on the path rather than the file beside it.
        translate_c.addIncludePath(b.path("include"));
        translate_c.addIncludePath(options.version_header.dirname());
        if (options.linkage == .static) {
            // Upstream's rule, at src/CMakeLists.txt:6-10: `SPG_BUILD` is a
            // PRIVATE definition of the library, and `SPG_STATIC_LIBRARY`
            // becomes PUBLIC - that is, it reaches every consumer - whenever
            // the library is built static. Without it the header's
            // `#elif defined(_MSC_VER) && !defined(SPG_STATIC_LIBRARY)` arm
            // (include/spglib.h:21-23) declares every entry point
            // `__declspec(dllimport)`, which does not match a static archive.
            //
            // `SPG_BUILD` is deliberately absent here. The translation is a
            // consumer of the header, not the builder, and defining it would
            // mark the translated declarations `dllexport`. In `-fsys=spglib`
            // mode nothing is defined at all: the real selected system header
            // is translated as an installed consumer sees it, and this build
            // cannot know whether that system library is static, so guessing
            // `SPG_STATIC_LIBRARY` there would bind a header to a library it
            // may not match.
            translate_c.defineCMacro("SPG_STATIC_LIBRARY", "1");
        }
    }

    // The module carries the target and optimize mode of the build that
    // created it. `Module.linkSystemLibrary` calls `requireKnownTarget`
    // (lib/std/Build/Module.zig:370, :661-665), so a module created with only
    // a root source file panics at configure time the moment `-fsys=spglib`
    // links a system library through it.
    //
    // One optimise mode for the facade, its `c` import and its `rt` import, so
    // every type crossing between them is one type. `zigCallerOptimize` is
    // explained where it is defined; here it matters twice over, because the
    // runtime dispatch's wrappers are themselves `extern "C"` calls.
    const facade_optimize = zigCallerOptimize(options.optimize);
    const module = if (options.register_module)
        b.addModule("spglib", .{
            .root_source_file = b.path("zig/root.zig"),
            .target = options.target,
            .optimize = facade_optimize,
        })
    else
        b.createModule(.{
            .root_source_file = b.path("zig/root.zig"),
            .target = options.target,
            .optimize = facade_optimize,
        });

    // The runtime seam, and the only place either half of `runtime/graph.zig`
    // is called.
    //
    // `-Druntime` says how the facade reaches spglib: through the link line, or
    // through a table that an explicit `load(source)` fills. `-Dlinkage` says
    // which artifact this build delivers and installs. They are orthogonal, and
    // both configurations build and install an artifact.
    //
    // `options.target` and `facade_optimize` are the very values the `module`
    // above is created with. The optimise mode is not cosmetic: the dispatch
    // re-exports its types straight from the translation and a caller names
    // them through this facade, so a dispatch built at a different mode would
    // be a second set of nominally distinct types. It also keeps the Debug
    // extern-call workaround in force for the wrappers themselves, not only for
    // the facade around them.
    if (options.runtime_loaded) {
        // The generated dispatch, built from this build's own translation step,
        // so it describes the header this configuration actually selected. It
        // carries `rt` and `library` itself and compiles `runtime/sync.c` in;
        // nothing is linked here, so the symbols arrive through the platform
        // loader once the caller names a provider.
        module.addImport("c", graph.createModule(b, translate_c, options.target, facade_optimize orelse options.optimize));
    } else {
        // The translated header, imported and never registered. `addModule("c")`
        // would make `dep.module("c")` resolve and hand a dependent the same
        // module under a second name.
        module.addImport("c", translate_c.createModule());
        // The loader core, for the two public types `LoadSource` and
        // `LoadError`. They are this SDK's types and have to be the same types
        // a caller names in either configuration, and a linked build has no
        // dispatch to carry them. It costs a linked build two declarations and
        // no code, because nothing else in `runtime/loader.zig` is referenced
        // until a configuration actually instantiates the loader.
        module.addImport("rt", graph.createCoreModule(b, options.target, facade_optimize orelse options.optimize));
    }

    var artifact: ?*std.Build.Step.Compile = null;
    if (options.use_system) {
        // Which library this links, and the `-L` that finds it, both come from
        // the selected installation's own `spglib.pc`, which declares
        // `-lspglib` (`pkgConfigContents` below): naming `symspg` here asked
        // for a stem this prefix has not and published no `-L`. Asked on the
        // translation step too: its own list (`TranslateC.zig:204`).
        module.linkSystemLibrary("spglib", .{ .use_pkg_config = .force });
        translate_c.linkSystemLibrary("spglib", .{ .use_pkg_config = .force });
    } else {
        const core = b.createModule(.{
            .target = options.target,
            .optimize = options.optimize,
            .link_libc = true,
            // Zig sanitizes C sources in Debug by default.  That is not
            // compatible with `zigCallerOptimize`, which builds the Zig caller
            // optimised so the extern-call marshalling is correct: an
            // instrumented archive linked into a non-instrumented program
            // fails to link on `__ubsan_*`.  It is also the wrong default for a
            // numerical library, whose kernels rely on wraparound and on
            // narrowing conversions that ISO C leaves undefined.
            .sanitize_c = .off,
        });
        core.addIncludePath(b.path("include"));
        core.addIncludePath(b.path("src"));
        core.addIncludePath(options.version_header.dirname());
        // Upstream's own configuration, at src/CMakeLists.txt:6-10: `SPG_BUILD`
        // is PRIVATE to the library and `SPG_STATIC_LIBRARY` accompanies it
        // whenever the library is built static. Together they are what makes
        // `SPG_API` (include/spglib.h:12-27) declare `dllexport` while the
        // library is being built and nothing at all once a static archive is
        // consumed. `SPG_STATIC_LIBRARY` is defined for every static target,
        // not only Windows ones: it is inert where `SPG_API` is empty, and
        // keeping one rule for every target is what lets the translation, the
        // installed `spglib.pc` and this compile line agree.
        core.addCMacro("SPG_BUILD", "1");
        if (options.linkage == .static) core.addCMacro("SPG_STATIC_LIBRARY", "1");
        core.addCSourceFiles(.{
            .root = b.path("src"),
            .files = &core_sources,
            .flags = options.c_flags,
        });
        // libm is a separate library on the BSDs and glibc targets; it is part
        // of libc on macOS, Windows and wasi. The installed pkg-config file
        // asks the same question, so the two cannot drift.
        if (needsLibM(options.target)) core.linkSystemLibrary("m", .{});

        // PIC is deliberately left unset. `Module.pic` is `?bool`
        // (lib/std/Build/Module.zig:252) and only emits a flag when it is
        // non-null (`Module.zig:554`), so leaving it null hands the decision to
        // the compiler: `-fPIC` for the `.dynamic` link this variant produces,
        // and no PIC for the `.static` archive. Setting it here would pin one
        // of the two for both.
        //
        // Windows exports are upstream's own contract and are honoured
        // unchanged rather than replaced: `SPG_BUILD` above makes `SPG_API`
        // expand to `__declspec(dllexport)` under `_MSC_VER` and to
        // `__attribute__((visibility("default")))` everywhere else
        // (include/spglib.h:12-20), and `-fvisibility=hidden` in
        // `release_flags`/`debug_flags` hides everything upstream does not mark.
        // Upstream sets no `WINDOWS_EXPORT_ALL_SYMBOLS` and defines no `.def`,
        // so a MinGW shared build exports exactly what its header marks; this
        // build adds no export list of its own and therefore cannot widen it.

        artifact = b.addLibrary(.{
            .name = "spglib",
            .linkage = options.linkage,
            .version = upstream.version,
            .root_module = core,
        });
        // Delivery and dispatch are separate questions. Under `-Druntime` the
        // artifact is still built and still installed, because a caller may
        // equally name the provider this tree did build as the one it did not,
        // but it is not linked into the module: linking it would make the
        // linker resolve the same symbols statically and the runtime route
        // would quietly be a linked one.
        if (!options.runtime_loaded) module.linkLibrary(artifact.?);
    }

    return .{ .module = module, .artifact = artifact };
}
