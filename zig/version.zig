// Zig facade for spglib: build and version identity.
//
// The version strings come from the generated src/version.h, which build.zig
// configures from src/version.h.in. They are static storage owned by the
// library, so they stay valid for the lifetime of the process.

const std = @import("std");

const c = @import("c");

/// Build and version identity, read from the library that is linked in.
///
/// Every field is a copy or a borrow of storage the library owns: the three
/// numbers are returned by value, the strings are read from library static
/// storage that lives for the lifetime of the process. There is nothing to
/// release, and a copy of the value is independent.
pub const Version = struct {
    /// Major component of `version`.
    major: c_int,
    /// Minor component of `version`.
    minor: c_int,
    /// Patch component of `version`.
    micro: c_int,
    /// `SPGLIB_VERSION`, for example "2.7.0".
    version: []const u8,
    /// `SPGLIB_VERSION_FULL`.
    versionFull: []const u8,
    /// Upstream commit the fork is pinned to.
    commit: []const u8,
};

/// The upstream release this fork is pinned to, read from the compiled library
/// rather than from build.zig, so it cannot drift from what is linked.
pub fn getVersion() Version {
    return .{
        .major = c.spg_get_major_version(),
        .minor = c.spg_get_minor_version(),
        .micro = c.spg_get_micro_version(),
        .version = std.mem.span(c.spg_get_version()),
        .versionFull = std.mem.span(c.spg_get_version_full()),
        .commit = std.mem.span(c.spg_get_commit()),
    };
}
