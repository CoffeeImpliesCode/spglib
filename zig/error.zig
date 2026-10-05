// Zig facade for spglib: C status codes.
//
// include/spglib.h declares `SpglibError` with the values mirrored by
// `ErrorCode` below. Nothing here replaces an upstream failure with a success:
// every call that reports failure exposes the code spglib stored through
// `spg_get_error_code`.

const std = @import("std");

const c = @import("c");
const ffi = @import("ffi.zig");

/// The C type of `SpglibError` as produced by `addTranslateC`. It is an
/// integer alias on some toolchain versions and a Zig enum on others; every
/// conversion below goes through this alias so both shapes work.
///
/// `@TypeOf` of the call is already the return type, so no `@typeInfo` walk
/// is needed to recover it: the two shapes differ only in whether
/// `toRaw`/`fromRaw` use `@enumFromInt`, and that is decided per call site
/// with `@typeInfo(RawError)`.
pub const RawError = @TypeOf(c.spg_get_error_code());

/// Mirrors `SpglibError` from include/spglib.h, one tag per enumerator, in the
/// same order and with the same numeric values.
///
/// A recorded code is a per-thread, cleared-by-success value; `lastErrorCode`
/// owns that lifetime. It is a diagnostic behind the error a facade call
/// returned, not a second result channel.
pub const ErrorCode = enum(c_int) {
    /// The last call succeeded. Overwritten by every successful entry point,
    /// `getVersion` included.
    success = 0,
    spacegroupSearchFailed = 1,
    cellStandardizationFailed = 2,
    symmetryOperationSearchFailed = 3,
    atomsTooClose = 4,
    pointgroupNotFound = 5,
    niggliFailed = 6,
    delaunayFailed = 7,
    arraySizeShortage = 8,
    /// Recorded when a call signalled failure without naming a cause, and the
    /// value any code outside the table is reported as. `errorMessage` has no
    /// text for it: `spg_get_error_message` breaks on the `SPGERR_NONE`
    /// sentinel before it compares its argument (src/spglib.c:214-228).
    none = 9,
};

/// Failure codes returned by the spglib entry points, one error per
/// `ErrorCode` enumerator other than `success`. `None` is what spglib reports
/// when a call signals failure without recording a specific code, and is
/// deliberately not folded into success.
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

/// Failures detected before control reaches C. These never replace an spglib
/// status code; they exist because the C API takes `int num_atom`, raw pointers
/// and unchecked doubles, which a Zig slice cannot express.
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
    /// A k-point mesh entry is not a positive integer, or is too large for the
    /// `2 * mesh[i]` the doubled-mesh reduction computes (src/kgrid.c:125).
    MeshOutOfRange,
    /// A grid address component does not fit the `address[i] * 2` the
    /// doubled-mesh conversion computes (src/kgrid.c:39). This is not a bound on
    /// the mesh: an address outside the mesh names the point it folds onto.
    GridAddressOutOfRange,
    /// `symprec` is not positive; rejected before calling spglib.
    NonPositiveSymprec,
    /// A tensor rank is outside the 0..1 range spglib implements. `SiteTensorType`
    /// has only `NOSPIN`, `COLLINEAR` and `NONCOLLINEAR` (src/cell.h:10-14) and
    /// `cel_alloc_cell` allocates tensor storage for nothing else, so a higher
    /// rank would reach an uninitialised `cell->tensors`.
    TensorRankOutOfRange,
};

/// Reads the code spglib recorded for the most recent failing call on this
/// thread.
///
/// `spglib_error_code` is `static thread_local` (src/spglib.c:50) and every
/// successful entry point overwrites it with `SPGLIB_SUCCESS`, including the
/// six functions behind `getVersion`. The value is therefore meaningful only
/// immediately after a call that failed, it is per-thread, and a later
/// successful call in the same thread clears it. The error a facade call
/// returns is the reliable channel; this is the diagnostic behind it.
pub fn lastErrorCode() ErrorCode {
    return fromRaw(c.spg_get_error_code());
}

/// Converts the recorded code into a Zig error. `success` maps to `error.None`
/// so that a call which returned failure without recording a code is never
/// silently reported as success. It inherits `lastErrorCode`'s per-thread,
/// cleared-by-success lifetime.
pub fn lastError() Error {
    return toError(lastErrorCode());
}

/// The spglib message for `code`, borrowed from static storage owned by the
/// library and valid for the lifetime of the process.
///
/// Null when spglib has no message for the code. `spg_get_error_message`
/// (src/spglib.c:214-228) walks the table and breaks on the `{SPGERR_NONE,
/// ""}` sentinel at index 9 before it compares the argument, so `SPGERR_NONE`
/// and any code outside the table return NULL. `SPGERR_NONE` is a recorded
/// code, not a hypothetical: a magnetic dataset that cannot be assembled sets
/// it (src/spglib.c:1247-1252), and the facade maps an unrecognised recorded
/// code onto it.
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
    const value: std.meta.Int(.unsigned, @bitSizeOf(RawError)) = @intCast(@intFromEnum(code));
    // The translation yields an integer alias or a fieldless enum; only one of
    // the two branches is semantically analysed.
    if (@typeInfo(RawError) == .@"enum") return @enumFromInt(value);
    return @intCast(value);
}

/// Converts a C `int` count to a slice length. A negative count would mean the
/// library wrote an inconsistent dataset, which is a hard failure rather than
/// something to clamp: the check is a plain comparison rather than
/// `std.debug.assert`, because an assert is compiled out in ReleaseFast and
/// would leave `@intCast` to reinterpret a negative value as a huge length.
pub fn checkedCount(value: c_int) usize {
    if (value < 0) @panic("spglib reported a negative count");
    return @intCast(value);
}
