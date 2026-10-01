// Zig facade for spglib: the shapes `addTranslateC` produces.
//
// The public C header is a plain C API, and its pointer results say nothing
// about null in their types. This toolchain's translation emits a C pointer as
// `[*c]T`, which carries no null and cannot be unwrapped with `?` or `orelse`
// (see `lib/compiler/translate-c/Translator.zig:1215-1237`, which only makes an
// optional pointer when the child type is opaque, and
// `lib/compiler/translate-c/ast.zig:1625-1636`, which renders the rest as
// `[*c]`), while a different toolchain generation may well emit `?T` for the
// same declaration. `std.mem.span` states the same contract from the other
// side: "`[*c]` pointers are assumed to be non-null and 0-terminated".
//
// Every null test and every borrow therefore goes through this file, once, so
// the rest of the facade reads like ordinary Zig and the shape assumption is
// stated in exactly one place.

const std = @import("std");

/// True when a translated C pointer is null.
///
/// A C pointer is a non-null type that may still hold a null address, so the
/// address is what is compared. An optional pointer from a different
/// translation shape is unwrapped first, and the untaken branch is not
/// analysed.
pub fn isNull(pointer: anytype) bool {
    if (@typeInfo(@TypeOf(pointer)) == .optional) return pointer == null;
    return @intFromPtr(pointer) == 0;
}

/// The non-optional form of a translated C pointer. The branch is decided at
/// compile time, exactly as `error.zig` does for the translated enum.
fn unwrap(pointer: anytype) (if (@typeInfo(@TypeOf(pointer)) == .optional) @typeInfo(@TypeOf(pointer)).optional.child else @TypeOf(pointer)) {
    if (@typeInfo(@TypeOf(pointer)) == .optional) return pointer.?;
    return pointer;
}

/// Borrows `count` elements of type `T` from a C array pointer.
///
/// The pointee gains a `const` qualifier, which `@ptrCast` allows; removing one
/// would need `@constCast`. The slice borrows upstream memory and is valid
/// only as long as the owner that supplied the pointer.
pub fn borrow(comptime T: type, pointer: anytype, count: usize) []const T {
    const base: [*]const T = @ptrCast(unwrap(pointer));
    return base[0..count];
}

/// The single-pointer form of a C pointer, for an owner handle the caller keeps.
pub fn single(comptime T: type, pointer: anytype) *T {
    return @ptrCast(unwrap(pointer));
}

/// A C string as an optional slice, or null when the library returned no
/// string. `spg_get_error_message` documents NULL for "no entry", so the
/// distinction is kept rather than replaced by an empty string.
pub fn spanOrNull(pointer: anytype) ?[]const u8 {
    if (isNull(pointer)) return null;
    return std.mem.span(unwrap(pointer));
}
