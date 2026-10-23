// SPDX-License-Identifier: BSD-3-Clause
//
//! Builds runtime-dispatch modules from the selected translation.
//! Do not link the native archive; routed symbols come from the loaded provider.

const std = @import("std");

/// C symbol prefix used by `runtime/sync.c`.
/// Keep it aligned with `runtime/library.zig`; another SDK needs its own prefix.
const sync_prefix = "spglib_rt";

/// Direct libc declarations exposed through mingw-w64's `<stddef.h>` include closure.
/// Other targets may not expose every name; `errno` and `_threadid` are macros, not symbols.
const libc_noise =
    \\__chk_fail,__debugbreak,__fastfail,__get_errno,__mingw_get_crt_info,
    \\__prefetch,__threadhandle,__threadid,_errno,_get_errno,_set_errno
;

/// Header declarations with no definitions in this tree; they remain optional at load.
/// A missing provider export panics only if a caller invokes its wrapper.
const provider_optional =
    \\spg_get_grid_points_by_rotations,spg_get_BZ_grid_points_by_rotations
;

/// No provider exports are excluded; only `provider_optional` is optional.
const provider_excluded = "";

/// Adds the loader core used by linked builds for `LoadSource` and `LoadError`.
/// Runtime builds use the dispatch's single core instance.
pub fn createCoreModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("runtime/loader.zig"),
        .target = target,
        .optimize = optimize,
        // The Unix backend calls `dlopen`, which is libc. Nothing in this module
        // is compiled into a linked build, so this costs nothing there.
        .link_libc = true,
    });
}

/// Creates the runtime-loaded `c` module from this build's translation step.
/// Generated declarations match the selected target and configuration.
pub fn createModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const core = createCoreModule(b, target, optimize);

    const library = b.createModule(.{
        .root_source_file = b.path("runtime/library.zig"),
        .target = target,
        .optimize = optimize,
    });
    library.addImport("rt", core);

    return createDispatchModule(b, translate, target, optimize, core, library);
}

/// The dispatch and patched translation written by one generator run.
const GeneratedSources = struct {
    native: std.Build.LazyPath,
    dispatch: std.Build.LazyPath,
};

fn createDispatchModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: *std.Build.Module,
    library: *std.Build.Module,
) *std.Build.Module {
    const sources = generateDispatch(b, translate, target);

    const dispatch = b.createModule(.{
        .root_source_file = sources.dispatch,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dispatch.addImport("rt", core);
    dispatch.addImport("library", library);

    // Keep translated types nominal in one module; nested declarations use routed wrappers.
    const native = b.createModule(.{
        .root_source_file = sources.native,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    native.addImport("c_routed", dispatch);
    dispatch.addImport("c_native", native);
    dispatch.addCSourceFiles(.{
        .files = &.{"runtime/sync.c"},
        .flags = &.{b.fmt("-DRT_SYNC_PREFIX={s}", .{sync_prefix})},
        .language = .c,
    });
    return dispatch;
}

/// Generates dispatch from the target-specific translation output.
fn generateDispatch(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
) GeneratedSources {
    const generator = b.addExecutable(.{
        .name = b.fmt("spglib-runtime-generate-{s}", .{
            target.result.zigTriple(b.allocator) catch @panic("unspellable target"),
        }),
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/generate.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    const run = b.addRunArtifact(generator);
    run.addArg("--library");
    run.addArg("spglib");
    run.addArg("--translate");
    run.addFileArg(translate.getOutput());
    if (libc_noise.len != 0) {
        run.addArg("--noise");
        run.addArg(libc_noise);
    }
    if (provider_optional.len != 0) {
        run.addArg("--optional");
        run.addArg(provider_optional);
    }
    if (provider_excluded.len != 0) {
        run.addArg("--exclude");
        run.addArg(provider_excluded);
    }
    run.addArg("--native-output");
    const native_source = run.addOutputFileArg("native.zig");
    run.addArg("--output");
    const dispatch_source = run.addOutputFileArg("dispatch.zig");
    return .{ .native = native_source, .dispatch = dispatch_source };
}
