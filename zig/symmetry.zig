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

/// Symmetry operations borrowed from whoever produced them.
///
/// Neither slice is owned here. `Dataset.operations` and
/// `MagneticDataset.operations` borrow spglib's own storage and are invalid
/// once that dataset is deinitialised; `Symmetry.operations` borrows the
/// `Symmetry`'s own buffers and is invalid once that is deinitialised. An
/// operation maps `x_new = rotation * x + translation`.
pub const Operations = struct {
    /// One `int[3][3]` rotation per operation. The row/column order is
    /// upstream's, unchanged from `include/spglib.h`.
    rotations: []const [3][3]c_int,
    /// One fractional translation per operation, the same length as
    /// `rotations`.
    translations: []const [3]f64,

    /// Number of operations, which is the length of both slices.
    pub fn count(self: Operations) usize {
        return self.rotations.len;
    }
};

/// Symmetry operations owned by a Zig allocator.
///
/// The two buffers come from the allocator `getSymmetry` or
/// `getSymmetryFromDatabase` was given, which is stored here and must stay
/// valid until `deinit`. The value is single-owner: a copy names the same two
/// allocations, so `deinit` runs exactly once, on one copy only. No
/// upstream-allocated memory is held, so no `spg_free_*` call is involved.
pub const Symmetry = struct {
    /// The allocator that received `rotations` and `translations`. `deinit`
    /// frees into it.
    allocator: std.mem.Allocator,
    /// One `int[3][3]` rotation per operation, owned by `allocator`.
    rotations: []const [3][3]c_int,
    /// One fractional translation per operation, owned by `allocator`.
    translations: []const [3]f64,

    /// Releases both buffers with `allocator` and leaves `Symmetry` unusable.
    ///
    /// Call this once, on the owner; a second call, or a call through a copy,
    /// frees the same bytes twice.
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

/// Point group derived from a set of rotations, `spg_get_pointgroup`.
///
/// The value owns its characters: `symbol_buffer` and `trans_mat` are the
/// arrays the C entry point filled, copied into the returned struct, so
/// nothing here borrows library storage and there is nothing to release. A
/// copy is independent and needs no teardown.
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
    /// The `char symbol[6]` buffer the C entry point filled. Read it through
    /// `symbol`, which stops at the first NUL byte.
    symbol_buffer: [6]u8,
    /// Transformation matrix from the point group into the basis the rotations
    /// were given in, copied from `ptg_get_pointgroup`.
    trans_mat: [3][3]c_int,

    /// The point-group symbol, borrowed from `symbol_buffer` and ending at the
    /// first NUL byte.
    pub fn symbol(self: *const PointGroup) []const u8 {
        return std.mem.sliceTo(&self.symbol_buffer, 0);
    }
};

/// Space-group type for a Hall number, copied from `SpglibSpacegroupType`.
///
/// The C struct is copied field by field, so the value owns its characters,
/// needs no pointer into library storage and has nothing to release; a copy is
/// independent. The accessors slice that copy in place, which is why they take
/// `*const`.
pub const SpacegroupType = struct {
    /// International space-group number the Hall number belongs to.
    number: c_int,
    /// The Hall number this record is, the index into the built-in database.
    hallNumber: c_int,
    /// Number of the arithmetic crystal class, as `arth_get_number` assigned it.
    arithmeticCrystalClassNumber: c_int,
    /// The character arrays of the C struct, copied verbatim.
    storage: Storage,

    /// Fixed-width symbol buffers. Each is NUL-terminated inside its own
    /// array; the accessors slice them at the first NUL byte.
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

    /// Full Hermann-Mauguin symbol with the spacing of the International
    /// Tables, for example "P 4_2/m 2_1/n 2/m".
    pub fn internationalFull(self: *const SpacegroupType) []const u8 {
        return std.mem.sliceTo(&self.storage.international_full, 0);
    }

    /// Hermann-Mauguin symbol in the spaced form used by the Schoenflies
    /// listings, for example "P4_2/m n m".
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

/// Magnetic space-group type for a UNI number, copied from
/// `SpglibMagneticSpacegroupType`.
///
/// Copied field by field like `SpacegroupType`, so it owns its characters and
/// has nothing to release, and a copy is independent.
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

/// Finds the symmetry operations of `cell` into buffers the caller bounds by
/// `max_operations`, `spgat_get_symmetry` with the default angle tolerance.
///
/// spglib fails with `array size shortage` rather than truncating, so the limit
/// is a real constraint and never a silent truncation. A zero or
/// non-representable `max_operations` is `error.OperationCountOutOfRange`
/// before the call. `cell` is read for the duration of the call only. The
/// angle tolerance is not a parameter: the facade passes `-1.0`, the sentinel
/// the deprecated `spg_get_symmetry` wrapper passes and therefore the library's
/// own default (src/spglib.c:368-374).
///
/// Upstream deprecates this route, not the capability: both
/// `spg_get_symmetry` and `spgat_get_symmetry` carry
/// `SPG_DEPRECATED("Use the variables from SpglibDataset (rotations,
/// translations)")` (include/spglib.h:247-258). The replacement the message
/// names is `getDataset`, whose `Dataset.operations` is the same list in the
/// same convention with no bound to choose; the trade is that the dataset
/// allocates through spglib and is released by `Dataset.deinit`, while this
/// route writes into buffers the caller sizes and releases through the
/// allocator passed here. Reach for the dataset unless that allocator
/// ownership is the reason to be here.
///
/// The result is owned by the caller: `Symmetry.deinit` frees both buffers
/// with `allocator`, which must stay valid until then. On failure nothing is
/// returned and both buffers are released.
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

/// Looks up the built-in operations for a Hall number (1 to 530),
/// `spg_get_symmetry_from_database`.
///
/// `include/spglib.h:404-407` fixes the database entry size at 192
/// operations, so the buffers are sized for that and trimmed to the count
/// spglib returns. A Hall number the database does not carry is the search
/// failure spglib recorded, not a facade-level range check. This entry point
/// takes no tolerance at all, so there is no sentinel to pass; ownership is
/// `getSymmetry`'s.
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
/// The result owns its symbol and transformation matrix, so nothing borrows
/// `rotations` and nothing has to be released.
///
/// An empty rotation list is `error.OperationCountOutOfRange` rather than a
/// call with a zero length, and `rotations` is read for the duration of the
/// call only.
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

/// Largest `int` magnitude whose doubling still fits a `c_int`. Upstream
/// doubles each address component (src/kgrid.c:39) and each mesh entry
/// (src/kgrid.c:125) in `int`, so one past this overflows.
const max_doubled_component: c_int = std.math.maxInt(c_int) / 2;

/// Maps a grid address onto the index spglib uses for the mesh point,
/// `spg_get_dense_grid_point_from_address`, whose result is a `size_t`.
///
/// The address is not bounded by the mesh. Upstream folds whatever it is
/// given: it doubles each component (`src/kgrid.c:39`), subtracts `2 * mesh[i]`
/// once from every doubled component that exceeds the mesh
/// (`src/kgrid.c:125`), halves, and takes the remainder against the mesh
/// (`src/kgrid.c:96-106`). An address outside the mesh therefore names the same
/// mesh point as the address inside it that it folds onto: in a 2x2x2 mesh
/// {3,0,0}, {1,0,0} and {5,0,0} are all index 1.
///
/// Two inputs are refused, both because that arithmetic is `int` in C: a mesh
/// entry that is not positive, which `modulo_i3` divides by
/// (`src/kgrid.c:100`), or too large to double; and a component too large to
/// double. No address the mesh does not bound is turned away.
pub fn gridPointFromAddress(address: [3]c_int, mesh: [3]c_int) err.InputError!usize {
    for (0..3) |axis| {
        if (mesh[axis] <= 0 or mesh[axis] > max_doubled_component) return error.MeshOutOfRange;
        if (address[axis] > max_doubled_component or address[axis] < -max_doubled_component) {
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
