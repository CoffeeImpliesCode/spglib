// Zig facade for spglib: symmetry datasets and cell standardisation.
//
// `Dataset` owns memory that upstream allocated with `malloc`. Every borrow
// returned from it is valid until `deinit`, and `deinit` is the only way to
// release it; it calls `spg_free_dataset`, never a Zig allocator.

const std = @import("std");

const cell_mod = @import("cell.zig");
const err = @import("error.zig");
const symmetry = @import("symmetry.zig");

const Cell = cell_mod.Cell;
const OwnedCell = cell_mod.OwnedCell;
const Operations = symmetry.Operations;
const c = @import("c");
const ffi = @import("ffi.zig");

/// An owned `SpglibDataset`.
pub const Dataset = struct {
    raw: *c.SpglibDataset,

    /// Releases the dataset and every array inside it.
    pub fn deinit(self: Dataset) void {
        c.spg_free_dataset(self.raw);
    }

    pub fn spacegroupNumber(self: Dataset) c_int {
        return self.raw.spacegroup_number;
    }

    /// Hall number, 1 to 530, indexing the built-in database.
    pub fn hallNumber(self: Dataset) c_int {
        return self.raw.hall_number;
    }

    pub fn internationalSymbol(self: Dataset) []const u8 {
        return cString(self.raw.international_symbol[0..]);
    }

    pub fn hallSymbol(self: Dataset) []const u8 {
        return cString(self.raw.hall_symbol[0..]);
    }

    pub fn choice(self: Dataset) []const u8 {
        return cString(self.raw.choice[0..]);
    }

    pub fn pointgroupSymbol(self: Dataset) []const u8 {
        return cString(self.raw.pointgroup_symbol[0..]);
    }

    pub fn transformationMatrix(self: Dataset) [3][3]f64 {
        return self.raw.transformation_matrix;
    }

    pub fn originShift(self: Dataset) [3]f64 {
        return self.raw.origin_shift;
    }

    pub fn atomCount(self: Dataset) usize {
        return err.checkedCount(self.raw.n_atoms);
    }

    pub fn operationCount(self: Dataset) usize {
        return err.checkedCount(self.raw.n_operations);
    }

    /// Borrowed operations. Valid until `deinit`.
    pub fn operations(self: Dataset) Operations {
        const count = self.operationCount();
        return .{
            .rotations = ffi.borrow([3][3]c_int, self.raw.rotations, count),
            .translations = ffi.borrow([3]f64, self.raw.translations, count),
        };
    }

    /// Borrowed Wyckoff identifiers, one per input atom.
    pub fn wyckoffs(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.wyckoffs, self.atomCount());
    }

    /// Borrowed site-symmetry symbols, one per input atom, each NUL-terminated
    /// inside its own 7-character slot.
    pub fn siteSymmetrySymbols(self: Dataset) []const [7]u8 {
        return ffi.borrow([7]u8, self.raw.site_symmetry_symbols, self.atomCount());
    }

    /// Borrowed symmetry-equivalence classes, one per input atom.
    pub fn equivalentAtoms(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.equivalent_atoms, self.atomCount());
    }

    /// Borrowed crystallographic orbits, one per input atom.
    pub fn crystallographicOrbits(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.crystallographic_orbits, self.atomCount());
    }

    pub fn primitiveLattice(self: Dataset) [3][3]f64 {
        return self.raw.primitive_lattice;
    }

    /// Borrowed map from input atoms to primitive-cell atoms.
    pub fn mappingToPrimitive(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.mapping_to_primitive, self.atomCount());
    }

    pub fn standardAtomCount(self: Dataset) usize {
        return err.checkedCount(self.raw.n_std_atoms);
    }

    pub fn standardLattice(self: Dataset) [3][3]f64 {
        return self.raw.std_lattice;
    }

    pub fn standardRotationMatrix(self: Dataset) [3][3]f64 {
        return self.raw.std_rotation_matrix;
    }

    pub fn standardTypes(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.std_types, self.standardAtomCount());
    }

    pub fn standardPositions(self: Dataset) []const [3]f64 {
        return ffi.borrow([3]f64, self.raw.std_positions, self.standardAtomCount());
    }

    pub fn standardMappingToPrimitive(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.std_mapping_to_primitive, self.standardAtomCount());
    }
};

/// Upstream declares these fields as plain `char[N]` arrays, which
/// `addTranslateC` renders as `[N]u8` with no sentinel, so `std.mem.span`
/// does not apply to them.  They are NUL-terminated by C convention, so the
/// string ends at the first zero byte; an unterminated array is returned in
/// full rather than silently truncated at some other length.
fn cString(field: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, field, 0) orelse field.len;
    return field[0..end];
}

pub const StandardizeOptions = struct {
    /// True reduces to a primitive cell, false idealises to a conventional one.
    to_primitive: bool = true,
    /// Skip the idealisation step when producing a primitive cell.
    no_idealize: bool = false,
    symprec: f64,
};

/// Symmetry search at the default angle tolerance.
pub fn getDataset(cell: Cell, symprec: f64) (err.Error || err.InputError)!Dataset {
    try cell.validate(symprec);
    return fromRaw(c.spg_get_dataset(
        cell.latticePtr(),
        cell.positionPtr(),
        cell.typePtr(),
        @intCast(cell.atomCount()),
        symprec,
    ));
}

/// Symmetry search pinned to a specific Hall number. A Hall number of 0 selects
/// the same default as `getDataset`.
pub fn getDatasetWithHallNumber(
    cell: Cell,
    hall_number: c_int,
    symprec: f64,
) (err.Error || err.InputError)!Dataset {
    try cell.validate(symprec);
    return fromRaw(c.spg_get_dataset_with_hall_number(
        cell.latticePtr(),
        cell.positionPtr(),
        cell.typePtr(),
        @intCast(cell.atomCount()),
        hall_number,
        symprec,
    ));
}

/// Symmetry search with an explicit angle tolerance.
pub fn getDatasetWithAngleTolerance(
    cell: Cell,
    symprec: f64,
    angle_tolerance: f64,
) (err.Error || err.InputError)!Dataset {
    try cell.validate(symprec);
    return fromRaw(c.spgat_get_dataset(
        cell.latticePtr(),
        cell.positionPtr(),
        cell.typePtr(),
        @intCast(cell.atomCount()),
        symprec,
        angle_tolerance,
    ));
}

/// Takes ownership of a dataset pointer, or reports the failure spglib
/// recorded. The three `spg_get_dataset` entry points return NULL on failure.
fn fromRaw(raw: anytype) (err.Error || err.InputError)!Dataset {
    if (ffi.isNull(raw)) return err.lastError();
    return .{ .raw = ffi.single(c.SpglibDataset, raw) };
}

/// Standardises a cell, replacing it with a primitive or conventional cell.
///
/// The result is allocated by the caller's allocator; the input is not
/// modified. spglib writes up to four times the input atom count, so the
/// buffers are sized accordingly and trimmed to the returned count.
pub fn standardizeCell(
    allocator: std.mem.Allocator,
    cell: Cell,
    options: StandardizeOptions,
) (err.Error || err.InputError || std.mem.Allocator.Error)!OwnedCell {
    try cell.validate(options.symprec);
    const capacity = cell.atomCount() * 4;
    var result = try cell_mod.allocateCell(allocator, capacity);
    errdefer result.deinit();

    result.lattice = cell.lattice;
    @memcpy(result.positions[0..cell.atomCount()], cell.positions);
    @memcpy(result.types[0..cell.atomCount()], cell.types);

    const count = c.spgat_standardize_cell(
        result.latticePtr(),
        result.positionPtr(),
        result.mutableTypePtr(),
        @intCast(cell.atomCount()),
        @intFromBool(options.to_primitive),
        @intFromBool(options.no_idealize),
        options.symprec,
        -1.0,
    );
    if (count == 0) return err.lastError();

    result.positions = trim([3]f64, allocator, result.positions, err.checkedCount(count));
    result.types = trim(c_int, allocator, result.types, err.checkedCount(count));
    return result;
}

/// Reduces a cell to its primitive cell.
pub fn findPrimitive(
    allocator: std.mem.Allocator,
    cell: Cell,
    symprec: f64,
) (err.Error || err.InputError || std.mem.Allocator.Error)!OwnedCell {
    return standardizeCell(allocator, cell, .{ .to_primitive = true, .symprec = symprec });
}

/// Symmetrises a cell into its Bravais lattice. The buffers are sized as
/// upstream requires, four times the input atom count.
pub fn refineCell(
    allocator: std.mem.Allocator,
    cell: Cell,
    symprec: f64,
) (err.Error || err.InputError || std.mem.Allocator.Error)!OwnedCell {
    try cell.validate(symprec);
    const capacity = cell.atomCount() * 4;
    var result = try cell_mod.allocateCell(allocator, capacity);
    errdefer result.deinit();

    result.lattice = cell.lattice;
    @memcpy(result.positions[0..cell.atomCount()], cell.positions);
    @memcpy(result.types[0..cell.atomCount()], cell.types);

    const count = c.spgat_refine_cell(
        result.latticePtr(),
        result.positionPtr(),
        result.mutableTypePtr(),
        @intCast(cell.atomCount()),
        symprec,
        -1.0,
    );
    if (count == 0) return err.lastError();

    result.positions = trim([3]f64, allocator, result.positions, err.checkedCount(count));
    result.types = trim(c_int, allocator, result.types, err.checkedCount(count));
    return result;
}

/// Reduces `lattice` in place. The lattice is only modified when the reduction
/// succeeds.
pub fn niggliReduce(lattice: *[3][3]f64, symprec: f64) (err.Error || err.InputError)!void {
    if (!(symprec > 0)) return error.NonPositiveSymprec;
    if (c.spg_niggli_reduce(lattice, symprec) == 0) return err.lastError();
}

/// Trims a buffer to its used length, keeping the original when the allocator
/// cannot shrink it. Ownership stays with the same allocator either way.
fn trim(comptime T: type, allocator: std.mem.Allocator, slice: []T, len: usize) []T {
    if (len == slice.len) return slice;
    return allocator.realloc(slice, len) catch slice;
}
