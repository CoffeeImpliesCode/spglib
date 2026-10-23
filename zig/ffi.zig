// Translate-c pointer and borrow helpers.

const std = @import("std");

/// True when a translated C pointer has a null address.
pub fn isNull(pointer: anytype) bool {
    if (@typeInfo(@TypeOf(pointer)) == .optional) return pointer == null;
    return @intFromPtr(pointer) == 0;
}

/// Unwraps the pointer form emitted by translate-c.
fn unwrap(pointer: anytype) (if (@typeInfo(@TypeOf(pointer)) == .optional) @typeInfo(@TypeOf(pointer)).optional.child else @TypeOf(pointer)) {
    if (@typeInfo(@TypeOf(pointer)) == .optional) return pointer.?;
    return pointer;
}

/// Borrows `count` C-array elements; valid only while the owner lives.
pub fn borrow(comptime T: type, pointer: anytype, count: usize) []const T {
    const base: [*]const T = @ptrCast(unwrap(pointer));
    return base[0..count];
}

/// The single-pointer form of a C pointer, for an owner handle the caller keeps.
pub fn single(comptime T: type, pointer: anytype) *T {
    return @ptrCast(unwrap(pointer));
}

/// Borrows a NUL-terminated C string, or returns null for a null pointer.
pub fn spanOrNull(pointer: anytype) ?[]const u8 {
    if (isNull(pointer)) return null;
    return std.mem.span(unwrap(pointer));
}
