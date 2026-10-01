// Consumer package for the spglib fork.
//
// It proves that a downstream package needs nothing but `dep.module("spglib")`
// and, when it wants the C artifact for its own compilation, `dep.artifact`.
// `src/main.zig` exercises both halves: the typed facade on a cubic
// perovskite, and one direct call into the translated C API exported as
// `spglib.c`, whose answer is fixed by the database upstream ships.
// Run it with `zig build run` from this directory.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const spglib_dep = b.dependency("spglib", .{
        .target = target,
        .optimize = optimize,
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

    // The exported module already carries the library, so linking the artifact
    // is only needed for code that compiles C against the public header. This
    // package does both, which is the arrangement downstream users hit.
    executable.root_module.linkLibrary(spglib_dep.artifact("spglib"));
    // `zig build run` is the proof: it links the exported artifact and executes
    // real symmetry searches against the fork.
    const run = b.addRunArtifact(executable);
    b.step("run", "Run the consumer against the spglib fork").dependOn(&run.step);

    b.installArtifact(executable);
}
