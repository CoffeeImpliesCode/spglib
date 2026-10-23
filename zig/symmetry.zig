const std = @import("std");

const err = @import("error.zig");
const Cell = @import("cell.zig").Cell;

const c = @import("c");

/// Rotation and translation slices borrowed from a dataset or owned `Symmetry`.
/// Operations map `x_new = rotation * x + translation`; borrows expire with their owner.
pub const Operations = struct {
    /// One upstream-row-layout `int[3][3]` rotation per operation.
    rotations: []const [3][3]c_int,
    /// One fractional translation per rotation.
    translations: []const [3]f64,

    /// Number of operations, which is the length of both slices.
    pub fn count(self: Operations) usize {
        return self.rotations.len;
    }
};

/// Owns the two operation buffers allocated by its allocator; `deinit` frees them.
/// Single-owner value; copies share the same storage.
pub const Symmetry = struct {
    /// Allocator used to free `rotations` and `translations`.
    allocator: std.mem.Allocator,
    /// One `int[3][3]` rotation per operation, owned by `allocator`.
    rotations: []const [3][3]c_int,
    /// One fractional translation per operation, owned by `allocator`.
    translations: []const [3]f64,

    /// Frees both buffers with `allocator`; call once on the owning value.
    pub fn deinit(self: Symmetry) void {
        self.allocator.free(self.rotations);
        self.allocator.free(self.translations);
    }

    /// Number of operations, which is the length of both buffers.
    pub fn count(self: Symmetry) usize {
        return self.rotations.len;
    }

    /// Borrows the two buffers as an `Operations` view, valid until `deinit`.
    pub fn operations(self: Symmetry) Operations {
        return .{ .rotations = self.rotations, .translations = self.translations };
    }
};

/// Point group returned by `spg_get_pointgroup`; its symbol and matrix are copied into the value.
/// The result is independent and needs no release.
pub const PointGroup = struct {
    /// Point-group index, 1..32; 0 means no group, not a rotation count.
    number: c_int,
    /// Fixed-width C symbol buffer, NUL-terminated within the array.
    symbol_buffer: [6]u8,
    /// Transformation matrix from the group basis to the input rotation basis.
    trans_mat: [3][3]c_int,

    /// Borrows the symbol up to its first NUL byte.
    pub fn symbol(self: *const PointGroup) []const u8 {
        return std.mem.sliceTo(&self.symbol_buffer, 0);
    }
};

/// Space-group type copied from spglib; the value owns its fixed-width symbols.
/// Accessors borrow the copy; no release is needed.
pub const SpacegroupType = struct {
    /// International space-group number the Hall number belongs to.
    number: c_int,
    /// The Hall number this record is, the index into the built-in database.
    hallNumber: c_int,
    /// Number of the arithmetic crystal class, as `arth_get_number` assigned it.
    arithmeticCrystalClassNumber: c_int,
    /// The character arrays of the C struct, copied verbatim.
    storage: Storage,

    /// Fixed-width, NUL-terminated symbol buffers.
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

    /// Compact Hermann-Mauguin symbol, for example "P4_2/mnm".
    pub fn internationalShort(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.international_short, 0);
    }

    /// Full Hermann-Mauguin symbol with International Tables spacing.
    pub fn internationalFull(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.international_full, 0);
    }

    /// Hermann-Mauguin symbol in the spaced Schoenflies-listing form.
    pub fn international(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.international, 0);
    }

    /// Schoenflies symbol, for example "D4h^14".
    pub fn schoenflies(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.schoenflies, 0);
    }

    /// Hall symbol, for example "-P 4n 2n".
    pub fn hallSymbol(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.hall_symbol, 0);
    }

    /// Origin choice, empty when this setting has none.
    pub fn choice(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.choice, 0);
    }

    /// International symbol of the point group, for example "4/mmm".
    pub fn pointgroupInternational(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.pointgroup_international, 0);
    }

    /// Schoenflies symbol of the point group, for example "D4h".
    pub fn pointgroupSchoenflies(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.pointgroup_schoenflies, 0);
    }

    /// Symbol of the arithmetic crystal class, for example "4/mmmP".
    pub fn arithmeticCrystalClassSymbol(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.arithmetic_crystal_class_symbol, 0);
    }
};

/// Magnetic space-group type copied from spglib; the value owns its symbols.
/// Accessors borrow the copy; no release is needed.
pub const MagneticSpacegroupType = struct {
    /// UNI number the record was looked up by, 1 to 1651.
    uniNumber: c_int,
    /// Litvin number of the same type.
    litvinNumber: c_int,
    /// Space-group number of the type, not the UNI number.
    number: c_int,
    /// Magnetic space-group type, 1 to 4.
    magneticType: c_int,
    /// The character arrays of the C struct, copied verbatim.
    storage: Storage,

    /// Fixed-width symbol buffers, each NUL-terminated inside its own array.
    pub const Storage = struct {
        bns_number: [8]u8,
        og_number: [12]u8,
    };

    /// Belov-Neron-Smirnova number of the type, for example "136.496".
    pub fn bnsNumber(self: *const MagneticSpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.bns_number, 0);
    }

    /// Ogawa number of the type, for example "136.2.1153".
    pub fn ogNumber(self: *const MagneticSpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.og_number, 0);
    }
};

/// Gets bounded operations with default tolerance; invalid limits return `OperationCountOutOfRange`, short capacity returns `ArraySizeShortage`.
/// Borrows `cell` for the call; returns allocator-owned `Symmetry` (`deinit`) and frees buffers on failure. Prefer `getDataset` unless caller allocator ownership matters; upstream deprecates this route.
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

/// Looks up operations for Hall number 1..530 using the fixed 192-operation database bound.
/// Returns allocator-owned `Symmetry` (deinit); spglib failures return its recorded error.
pub fn getSymmetryFromDatabase(
    allocator: std.mem.Allocator,
    hall_number: c_int,
) (err.Error || std.mem.Allocator.Error)!Symmetry {
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

/// Derives from rotations borrowed for the call; empty or oversized input returns `OperationCountOutOfRange`.
/// Returns a copied value; `number` is a group index, and no match returns `error.None`.
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

/// Looks up Hall numbers 1..530; invalid input or spglib failure returns an error, not a zeroed value.
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

/// Looks up UNI numbers 1..1651; invalid input or spglib failure returns an error, not a zeroed value.
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

/// Largest absolute value whose doubling fits in `c_int`.
const max_doubled_component: c_int = std.math.maxInt(c_int) / 2;

/// Maps a grid address to its mesh index; out-of-mesh addresses fold to an equivalent point.
/// Non-positive or unsafe-to-double mesh/address values return `MeshOutOfRange` or `GridAddressOutOfRange`.
pub fn gridPointFromAddress(address: [3]c_int, mesh: [3]c_int) err.InputError!usize {
    for (0..3) |axis| {
        if (mesh[axis] <= 0 or mesh[axis] > max_doubled_component) return error.MeshOutOfRange;
        if (address[axis] > max_doubled_component or address[axis] < -max_doubled_component) {
            return error.GridAddressOutOfRange;
        }
    }
    return c.spg_get_dense_grid_point_from_address(&address, &mesh);
}

/// Shrinks to used length when possible; either result stays owned by `allocator`.
fn shrink(comptime T: type, allocator: std.mem.Allocator, slice: []T, len: usize) []T {
    if (len == slice.len) return slice;
    return allocator.realloc(slice, len) catch slice;
}
