const std = @import("std");

const c = @import("c");

/// Version and upstream commit read from the linked library.
/// Strings borrow library storage and remain valid for the process lifetime.
pub const Version = struct {
    major: c_int,
    minor: c_int,
    micro: c_int,
    /// `SPGLIB_VERSION`, for example "2.7.0".
    version: []const u8,
    /// `SPGLIB_VERSION_FULL`.
    versionFull: []const u8,
    /// Upstream commit the fork is pinned to.
    commit: []const u8,
};

/// Returns version and commit data from the linked library.
/// String fields borrow process-lifetime library storage.
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
