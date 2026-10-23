const c = @import("c");
const ffi = @import("ffi.zig");

/// Translated return type of `spg_get_error_code`; may be an enum or integer alias.
/// Conversion helpers support both forms.
pub const RawError = @TypeOf(c.spg_get_error_code());

/// Mirrors spglib's status codes.
/// The recorded value is per-thread and cleared by a successful call.
pub const ErrorCode = enum(c_int) {
    /// A successful spglib call; every successful entry point clears this code.
    success = 0,
    spacegroupSearchFailed = 1,
    cellStandardizationFailed = 2,
    symmetryOperationSearchFailed = 3,
    atomsTooClose = 4,
    pointgroupNotFound = 5,
    niggliFailed = 6,
    delaunayFailed = 7,
    arraySizeShortage = 8,
    /// Used when a call fails without a known code; no message is available.
    none = 9,
};

/// Facade errors for spglib failures; `None` represents a failure without a specific code.
pub const Error = error{
    SpacegroupSearchFailed,
    CellStandardizationFailed,
    SymmetryOperationSearchFailed,
    AtomsTooClose,
    PointgroupNotFound,
    NiggliFailed,
    DelaunayFailed,
    ArraySizeShortage,
    None,
};

/// Input errors detected before calling spglib.
pub const InputError = error{
    /// The cell has no atoms.
    EmptyCell,
    /// `positions` and `types` describe different atom counts.
    AtomCountMismatch,
    /// The atom count does not fit in the `int num_atom` parameter.
    AtomCountOutOfRange,
    /// Per-atom data (spins or tensors) does not match the atom count.
    TensorCountMismatch,
    /// A symmetry-operation count does not fit in the `int max_size` parameter.
    OperationCountOutOfRange,
    /// A Hall number is outside the 1..530 range the database covers.
    HallNumberOutOfRange,
    /// A UNI number is outside the 1..1651 range the database covers.
    UniNumberOutOfRange,
    /// Mesh entry is non-positive or cannot be doubled safely by spglib.
    MeshOutOfRange,
    /// Grid address cannot be doubled safely; addresses outside the mesh may still fold.
    GridAddressOutOfRange,
    /// `symprec` is not positive; rejected before calling spglib.
    NonPositiveSymprec,
    /// Tensor rank is outside spglib's supported 0..1 range.
    TensorRankOutOfRange,
};

/// Returns the calling thread's recorded error; any successful call clears it.
/// Use after a facade failure; the returned Zig error is the primary channel.
pub fn lastErrorCode() ErrorCode {
    return fromRaw(c.spg_get_error_code());
}

/// Converts the recorded code to a Zig error; an unrecorded failure maps to `error.None`.
pub fn lastError() Error {
    return toError(lastErrorCode());
}

/// Borrows spglib's process-lifetime message, or returns null when none exists.
pub fn errorMessage(code: ErrorCode) ?[]const u8 {
    return ffi.spanOrNull(c.spg_get_error_message(toRaw(code)));
}

/// Maps a recorded code onto the Zig error set.
pub fn toError(code: ErrorCode) Error {
    return switch (code) {
        .success => error.None,
        .spacegroupSearchFailed => error.SpacegroupSearchFailed,
        .cellStandardizationFailed => error.CellStandardizationFailed,
        .symmetryOperationSearchFailed => error.SymmetryOperationSearchFailed,
        .atomsTooClose => error.AtomsTooClose,
        .pointgroupNotFound => error.PointgroupNotFound,
        .niggliFailed => error.NiggliFailed,
        .delaunayFailed => error.DelaunayFailed,
        .arraySizeShortage => error.ArraySizeShortage,
        .none => error.None,
    };
}

fn fromRaw(raw: RawError) ErrorCode {
    return switch (@as(c_int, @intCast(raw))) {
        0 => .success,
        1 => .spacegroupSearchFailed,
        2 => .cellStandardizationFailed,
        3 => .symmetryOperationSearchFailed,
        4 => .atomsTooClose,
        5 => .pointgroupNotFound,
        6 => .niggliFailed,
        7 => .delaunayFailed,
        8 => .arraySizeShortage,
        9 => .none,
        else => .none,
    };
}

fn toRaw(code: ErrorCode) RawError {
    const value: @Int(.unsigned, @bitSizeOf(RawError)) = @intCast(@backingInt(code));
    // Translate-c may represent the C error type as an enum or integer.
    if (@typeInfo(RawError) == .@"enum") return @fromBackingInt(@intCast(value));
    return @intCast(value);
}

/// Converts a non-negative C count to `usize`; panics if spglib returns a negative count.
pub fn checkedCount(value: c_int) usize {
    if (value < 0) @panic("spglib reported a negative count");
    return @intCast(value);
}
