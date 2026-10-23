// SPDX-License-Identifier: BSD-3-Clause
//
//! spglib's runtime-loader descriptor for synchronization and provider checks.
//! Providers must match struct layout, return convention, scalar widths, and allocator ownership.
//! Validation checks versions and P1, but not dataset layout or cell allocation.

const std = @import("std");

const rt = @import("rt");

/// Synchronization symbols compiled with `spglib_rt` in `runtime/sync.c` and `runtime/graph.zig`.
/// Each SDK instance needs a matching, unique prefix.
pub const Sync = struct {
    extern fn spglib_rt_lock() void;
    extern fn spglib_rt_unlock() void;
    extern fn spglib_rt_wait() void;
    extern fn spglib_rt_broadcast() void;
    // C `unsigned long long` maps to `u64` on supported targets.
    extern fn spglib_rt_thread_self() u64;

    pub fn lock() void {
        spglib_rt_lock();
    }
    pub fn unlock() void {
        spglib_rt_unlock();
    }
    pub fn wait() void {
        spglib_rt_wait();
    }
    pub fn broadcast() void {
        spglib_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return spglib_rt_thread_self();
    }
};

/// Binds this SDK's generated dispatch table to the generic loader.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Name used in pre-load diagnostics.
        pub const library_name = "spglib";

        /// Table type declared by the generated dispatch.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// Namespaced synchronization binding for this SDK.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        /// Stores an optional symbol address in its nullable table field.
        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Checks version data and space group 1's by-value `P1` result before publication.
        /// It allocates no dataset and does not validate dataset-struct layout.
        pub fn validate(dst: *const table) ?[]const u8 {
            const major = dst.spg_get_major_version();
            if (major != dispatch.SPGLIB_MAJOR_VERSION) {
                return validationMessage(
                    "spg_get_major_version() reported {d}, not the {d} this header was " ++
                        "translated from, so this provider was built from a different " ++
                        "source tree than the one these declarations describe",
                    .{ major, @as(c_int, dispatch.SPGLIB_MAJOR_VERSION) },
                );
            }
            const minor = dst.spg_get_minor_version();
            if (minor != dispatch.SPGLIB_MINOR_VERSION) {
                return validationMessage(
                    "spg_get_minor_version() reported {d}, not the {d} this header was " ++
                        "translated from, so this provider was built from a different " ++
                        "source tree than the one these declarations describe",
                    .{ minor, @as(c_int, dispatch.SPGLIB_MINOR_VERSION) },
                );
            }
            const micro = dst.spg_get_micro_version();
            if (micro != dispatch.SPGLIB_MICRO_VERSION) {
                return validationMessage(
                    "spg_get_micro_version() reported {d}, not the {d} this header was " ++
                        "translated from, so this provider was built from a different " ++
                        "source tree than the one these declarations describe",
                    .{ micro, @as(c_int, dispatch.SPGLIB_MICRO_VERSION) },
                );
            }

            if (!matchesCString(dst.spg_get_version(), dispatch.SPGLIB_VERSION)) {
                return "spg_get_version() did not return the version string this header " ++
                    "was translated from, so the provider's own build identity and " ++
                    "these declarations do not come from the same source tree";
            }

            // Hall number 1 is the known P1 result; this checks the by-value ABI.
            const spgtype = dst.spg_get_spacegroup_type(1);
            if (spgtype.number != 1 or spgtype.hall_number != 1) {
                return validationMessage(
                    "spg_get_spacegroup_type(1) answered space group {d} at Hall number " ++
                        "{d} rather than space group 1 at Hall number 1, so either the " ++
                        "by-value struct return or the field offsets of " ++
                        "SpglibSpacegroupType do not line up with this header",
                    .{ spgtype.number, spgtype.hall_number },
                );
            }
            if (!std.mem.eql(u8, boundedBytes(&spgtype.international_short), "P1")) {
                return validationMessage(
                    "spg_get_spacegroup_type(1) answered the symbol {s} rather than P1, " ++
                        "which is what Hall number 1 is in the International Tables, so " ++
                        "the character arrays inside SpglibSpacegroupType are not at " ++
                        "the offsets this header declares",
                    .{boundedBytes(&spgtype.international_short)},
                );
            }
            return null;
        }
    };
}

/// Compares at most `expected.len + 1` bytes and rejects a missing NUL.
fn matchesCString(actual: [*c]const u8, expected: []const u8) bool {
    if (actual == null) return false;
    var index: usize = 0;
    while (index < expected.len) : (index += 1) {
        if (actual[index] != expected[index]) return false;
    }
    return actual[expected.len] == 0;
}

/// Returns a fixed-width `char` array up to NUL, or the whole array if unterminated.
fn boundedBytes(field: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, field, 0) orelse field.len;
    return field[0..end];
}

/// Shared buffer for validation messages returned during a load attempt.
var message_buffer: [256]u8 = undefined;

/// Formats a load-time refusal in `message_buffer`.
/// Callers' arguments fit; the fallback exposes an unexpected format overflow.
fn validationMessage(comptime format: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(&message_buffer, format, args) catch
        "spglib: a load-time check failed and its value could not be printed";
}
