// Zig facade for spglib: symmetry operations, point groups and space-group
// types.
//
// Operation convention, unchanged from include/spglib.h: an operation maps
// `x_new = rotation * x + translation`, the rotation is stored as three rows of
// integers and the translation as three fractional coordinates.

const std = @import("std");

const err = @import("error.zig");
const Cell = @import("cell.zig").Cell;

const c = @import("c");

/// Symmetry operations borrowed from an owner. The slices never outlive it.
pub const Operations = struct {
    rotations: []const [3][3]c_int,
    translations: []const [3]f64,

    pub fn count(self: Operations) usize {
        return self.rotations.len;
    }
};

/// Symmetry operations owned by a Zig allocator.
pub const Symmetry = struct {
    allocator: std.mem.Allocator,
    rotations: []const [3][3]c_int,
    translations: []const [3]f64,

    /// Releases both buffers. The lattice-free operation list owns no upstream
    /// memory, so no C free call is involved.
    pub fn deinit(self: Symmetry) void {
        self.allocator.free(self.rotations);
        self.allocator.free(self.translations);
    }

    pub fn count(self: Symmetry) usize {
        return self.rotations.len;
    }

    pub fn operations(self: Symmetry) Operations {
        return .{ .rotations = self.rotations, .translations = self.translations };
    }
};

/// Result of `spg_get_pointgroup`. The symbol buffer is inline so the result
/// owns its characters without an allocation.
pub const PointGroup = struct {
    /// spglib's own point-group number, 1 to 32, and 0 when none was found.
    ///
    /// This is *not* the number of rotations. `spg_get_pointgroup` returns
    /// `pointgroup.number` (src/spglib.c:671-686), and that field holds the
    /// index its answer came from, not a cardinality:
    /// `ptg_get_transformation_matrix` assigns it from
    /// `get_pointgroup_number_by_rotations` and `ptg_get_pointgroup` copies it
    /// into the result (src/pointgroup.c:364-376 and :381-389). It is a row of
    /// `pointgroup_data` (src/pointgroup.c:26-289), whose rows are the 32
    /// point groups: 15 is "4/mmm" (src/pointgroup.c:146-153) and 32 is
    /// "m-3m" (src/pointgroup.c:282-289).
    number: c_int,
    symbol_buffer: [6]u8,
    trans_mat: [3][3]c_int,

    pub fn symbol(self: *const PointGroup) []const u8 {
        return std.mem.sliceTo(&self.symbol_buffer, 0);
    }
};

/// Value copy of `SpglibSpacegroupType`.
///
/// The C struct is copied field by field so the result owns its characters and
/// needs no pointer into library storage. Accessors slice the copy in place,
/// which is why they take `*const`.
pub const SpacegroupType = struct {
    number: c_int,
    hallNumber: c_int,
    arithmeticCrystalClassNumber: c_int,
    storage: Storage,

    pub const Storage = struct {
        international_short: [11]u8,
        international_full: [20]u8,
        international: [32]u8,
        schoenflies: [7]u8,
        hall_symbol: [17]u8,
        choice: [6]u8,
        pointgroup_international: [6]u8,
        pointgroup_schoenflies: [4]u8,
        arithmetic_crystal_class_symbol: [7]u8,
    };

    pub fn internationalShort(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.international_short, 0);
    }

    pub fn internationalFull(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.international_full, 0);
    }

    pub fn international(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.international, 0);
    }

    pub fn schoenflies(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.schoenflies, 0);
    }

    pub fn hallSymbol(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.hall_symbol, 0);
    }

    pub fn choice(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.choice, 0);
    }

    pub fn pointgroupInternational(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.pointgroup_international, 0);
    }

    pub fn pointgroupSchoenflies(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.pointgroup_schoenflies, 0);
    }

    pub fn arithmeticCrystalClassSymbol(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.arithmetic_crystal_class_symbol, 0);
    }
};

/// Value copy of `SpglibMagneticSpacegroupType`.
pub const MagneticSpacegroupType = struct {
    uniNumber: c_int,
    litvinNumber: c_int,
    number: c_int,
    /// Magnetic space-group type, 1 to 4.
    magneticType: c_int,
    storage: Storage,

    pub const Storage = struct {
        bns_number: [8]u8,
        og_number: [12]u8,
    };

    pub fn bnsNumber(self: *const MagneticSpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.bns_number, 0);
    }

    pub fn ogNumber(self: *const MagneticSpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.og_number, 0);
    }
};

/// Finds symmetry operations for `cell` into buffers the caller bounds by
/// `max_operations`.
///
/// spglib fails with `array size shortage` rather than truncating, so the limit
/// is a real constraint and never a silent truncation.
pub fn getSymmetry(
    allocator: std.mem.Allocator,
    cell: Cell,
    symprec: f64,
    max_operations: usize,
) (err.Error || err.InputError || std.mem.Allocator.Error)!Symmetry {
    try cell.validate(symprec);
    if (max_operations == 0) return error.OperationCountOutOfRange;
    if (max_operations > std.math.maxInt(c_int)) return error.OperationCountOutOfRange;

    const capacity: c_int = @intCast(max_operations);
    const rotations = try allocator.alloc([3][3]c_int, max_operations);
    errdefer allocator.free(rotations);
    const translations = try allocator.alloc([3]f64, max_operations);
    errdefer allocator.free(translations);

    const count = c.spgat_get_symmetry(
        @ptrCast(rotations.ptr),
        @ptrCast(translations.ptr),
        capacity,
        cell.latticePtr(),
        cell.positionPtr(),
        cell.typePtr(),
        @intCast(cell.atomCount()),
        symprec,
        // Same sentinel the upstream spg_get_symmetry wrapper passes.
        -1.0,
    );
    if (count == 0) return err.lastError();

    const used = err.checkedCount(count);
    return .{
        .allocator = allocator,
        .rotations = shrink([3][3]c_int, allocator, rotations, used),
        .translations = shrink([3]f64, allocator, translations, used),
    };
}

/// Looks up the built-in operations for a Hall number (1 to 530).
pub fn getSymmetryFromDatabase(
    allocator: std.mem.Allocator,
    hall_number: c_int,
) (err.Error || std.mem.Allocator.Error)!Symmetry {
    // include/spglib.h fixes the database entry size at 192 operations.
    const capacity = 192;
    const rotations = try allocator.alloc([3][3]c_int, capacity);
    errdefer allocator.free(rotations);
    const translations = try allocator.alloc([3]f64, capacity);
    errdefer allocator.free(translations);

    const count = c.spg_get_symmetry_from_database(
        @ptrCast(rotations.ptr),
        @ptrCast(translations.ptr),
        hall_number,
    );
    if (count == 0) return err.lastError();

    const used = err.checkedCount(count);
    return .{
        .allocator = allocator,
        .rotations = shrink([3][3]c_int, allocator, rotations, used),
        .translations = shrink([3]f64, allocator, translations, used),
    };
}

/// Derives the point group from a set of rotations.
///
/// `number` is spglib's point-group number, not a count of rotations; read
/// `symbol` for the group it names. No point group found is `error.None`,
/// because `spg_get_pointgroup` records `SPGERR_POINTGROUP_NOT_FOUND` and
/// returns 0 (src/spglib.c:678-681).
pub fn getPointGroup(rotations: []const [3][3]c_int) (err.Error || err.InputError)!PointGroup {
    if (rotations.len == 0) return error.OperationCountOutOfRange;
    if (rotations.len > std.math.maxInt(c_int)) return error.OperationCountOutOfRange;

    var result: PointGroup = .{
        .number = 0,
        .symbol_buffer = @splat(0),
        .trans_mat = @splat(@splat(0)),
    };
    const number = c.spg_get_pointgroup(
        &result.symbol_buffer,
        &result.trans_mat,
        @ptrCast(@constCast(rotations.ptr)),
        @intCast(rotations.len),
    );
    if (number == 0) return err.lastError();
    result.number = number;
    return result;
}

/// Space-group type for a Hall number (1 to 530).
///
/// Out of range is rejected here. `spg_get_spacegroup_type` would record
/// `SPGERR_SPACEGROUP_SEARCH_FAILED` and hand back a zeroed struct, which as a
/// plain value would look like a successful answer with empty strings.
pub fn getSpacegroupType(hall_number: c_int) (err.Error || err.InputError)!SpacegroupType {
    if (hall_number < 1 or hall_number > 530) return error.HallNumberOutOfRange;
    const raw = c.spg_get_spacegroup_type(hall_number);
    const storage: SpacegroupType.Storage = .{
        .international_short = raw.international_short,
        .international_full = raw.international_full,
        .international = raw.international,
        .schoenflies = raw.schoenflies,
        .hall_symbol = raw.hall_symbol,
        .choice = raw.choice,
        .pointgroup_international = raw.pointgroup_international,
        .pointgroup_schoenflies = raw.pointgroup_schoenflies,
        .arithmetic_crystal_class_symbol = raw.arithmetic_crystal_class_symbol,
    };
    return .{
        .number = raw.number,
        .hallNumber = raw.hall_number,
        .arithmeticCrystalClassNumber = raw.arithmetic_crystal_class_number,
        .storage = storage,
    };
}

/// Magnetic space-group type for a UNI number (1 to 1651).
///
/// Out of range is rejected here, for the same reason as `getSpacegroupType`:
/// `spg_get_magnetic_spacegroup_type` records a failure and returns zeroed
/// strings and a zero number.
pub fn getMagneticSpacegroupType(uni_number: c_int) (err.Error || err.InputError)!MagneticSpacegroupType {
    if (uni_number < 1 or uni_number > 1651) return error.UniNumberOutOfRange;
    const raw = c.spg_get_magnetic_spacegroup_type(uni_number);
    const storage: MagneticSpacegroupType.Storage = .{
        .bns_number = raw.bns_number,
        .og_number = raw.og_number,
    };
    return .{
        .uniNumber = raw.uni_number,
        .litvinNumber = raw.litvin_number,
        .number = raw.number,
        .magneticType = raw.type,
        .storage = storage,
    };
}

/// Maps a grid address onto the index spglib uses for the mesh point.
///
/// The mesh entries must be positive and the address must lie inside the mesh,
/// because spglib reads `mesh[i]` as a divisor and would otherwise divide by
/// zero.
pub fn gridPointFromAddress(address: [3]c_int, mesh: [3]c_int) err.InputError!usize {
    for (0..3) |axis| {
        if (mesh[axis] <= 0) return error.MeshOutOfRange;
        if (address[axis] < -mesh[axis] or address[axis] > mesh[axis]) {
            return error.GridAddressOutOfRange;
        }
    }
    return c.spg_get_dense_grid_point_from_address(&address, &mesh);
}

/// Returns the buffer capacity, or the exact length when shrinking is not
/// possible. An oversized buffer stays owned by the same allocator, so
/// `Symmetry.deinit` stays correct either way.
fn shrink(comptime T: type, allocator: std.mem.Allocator, slice: []T, len: usize) []T {
    if (len == slice.len) return slice;
    return allocator.realloc(slice, len) catch slice;
}
