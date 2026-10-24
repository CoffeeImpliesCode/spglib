// Behaviour tests for the spglib Zig facade need a usable native library
// before they can call anything.
//
// This file is that one step, shared by the three test roots. It is imported
// relatively rather than as a build-graph module, because a Zig module's root
// is its root source file's directory: `zig/examples/` cannot reach
// `zig/tests/`, and adding a build-graph module for it would be a change to a
// file this role does not own. The smoke example and the consumer package are
// separate programs with their own `main`, and each names its own provider from
// its own command line.
//
// A runtime-loading build has no library until `load` has been called, so every
// test calls `nativeReady()` first. That is a no-op at comptime in a linked
// build. In a runtime-loading build it is the one explicit load, and a build
// that was not told which file to load stops with the variable's name rather
// than reporting a test failure that says nothing about the reason.
//
// Nothing here looks in a default location and nothing falls back: a
// runtime-loading build that was not told which provider to use says so.

const std = @import("std");
const spglib = @import("spglib");

/// A shared object exporting the `SPG_API` entry points of `include/spglib.h`,
/// named by the environment in a runtime-loading build.
pub const provider_variable = "SPGLIB_TEST_PROVIDER";

/// Make the native library usable, once, before a test calls the facade.
///
/// In a linked build the facade is usable already and this is a no-op at
/// comptime. In a runtime-loading build every call into the module goes through
/// a table that `load` fills, so this is where the one explicit load happens.
/// It is safe to call from every test: the loader makes the same request
/// idempotent and keeps the handle to the end of the process.
pub fn nativeReady() void {
    if (comptime !spglib.runtime_loaded) return;
    if (spglib.loadedSource() != null) return;

    var buffer: [4096]u8 = undefined;
    const value = std.testing.environ.getAlloc(std.testing.allocator, provider_variable) catch
        missingProvider();
    defer std.testing.allocator.free(value);
    if (value.len == 0 or value.len > buffer.len) missingProvider();
    @memcpy(buffer[0..value.len], value);
    spglib.load(.{ .path = buffer[0..value.len] }) catch |err| {
        std.debug.print(
            "provider.zig: loading " ++ provider_variable ++ " = \"{s}\" failed: {t}\n",
            .{ buffer[0..value.len], err },
        );
        @panic("provider.zig: the provider named by " ++ provider_variable ++
            " did not load; nothing below this line ran");
    };
}

/// A build that was not told which provider to use.
///
/// The message names the variable and what a provider has to be, because "the
/// test failed" does not tell the next person where to look.
fn missingProvider() noreturn {
    @panic(
        "provider.zig: this is a runtime-loading build and " ++ provider_variable ++
            " is not set. Point it at a shared object exporting the entry points " ++
            "of include/spglib.h -- for example the one `zig build " ++
            "-Dlinkage=dynamic` installs -- and export it for the whole `zig " ++
            "build` invocation: a build script cannot inject a path into a run " ++
            "step's environment.",
    );
}
