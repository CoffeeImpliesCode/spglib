const std = @import("std");

const cell_mod = @import("cell.zig");
const err = @import("error.zig");
const symmetry = @import("symmetry.zig");

const Cell = cell_mod.Cell;
const OwnedCell = cell_mod.OwnedCell;
const Operations = symmetry.Operations;
const c = @import("c");
const ffi = @import("ffi.zig");

/// Owns a spglib-allocated dataset; release it once with `deinit` on the original value.
/// Accessor slices borrow its storage until release; `deinit` calls `spg_free_dataset`.
pub const Dataset = struct {
    /// Raw upstream handle; replacing it breaks accessors and changes what `deinit` frees.
    raw: *c.SpglibDataset,

    /// Frees the dataset with `spg_free_dataset`; call once on the owner.
    /// Accessor slices become invalid after release.
    pub fn deinit(self: Dataset) void {
        c.spg_free_dataset(self.raw);
    }

    /// International space-group number, 1 to 230.
    pub fn spacegroupNumber(self: Dataset) c_int {
        return self.raw.spacegroup_number;
    }

    /// Hall number, 1 to 530, indexing the built-in database.
    pub fn hallNumber(self: Dataset) c_int {
        return self.raw.hall_number;
    }

    /// Borrows the NUL-terminated International symbol; valid until `deinit`.
    pub fn internationalSymbol(self: Dataset) []const u8 {
        return cString(self.raw.international_symbol[0..]);
    }

    /// Borrows the Hall symbol until `deinit`.
    pub fn hallSymbol(self: Dataset) []const u8 {
        return cString(self.raw.hall_symbol[0..]);
    }

    /// Borrows the origin choice; empty when none is defined.
    pub fn choice(self: Dataset) []const u8 {
        return cString(self.raw.choice[0..]);
    }

    /// Borrows the point-group symbol until `deinit`.
    pub fn pointgroupSymbol(self: Dataset) []const u8 {
        return cString(self.raw.pointgroup_symbol[0..]);
    }

    /// Returns the input-to-standard-setting basis change by value.
    pub fn transformationMatrix(self: Dataset) [3][3]f64 {
        return self.raw.transformation_matrix;
    }

    /// Origin shift that goes with `transformationMatrix`, copied by value.
    pub fn originShift(self: Dataset) [3]f64 {
        return self.raw.origin_shift;
    }

    /// Number of input atoms, which indexes per-atom borrows.
    pub fn atomCount(self: Dataset) usize {
        return err.checkedCount(self.raw.n_atoms);
    }

    /// Number of symmetry operations, the length of `operations().rotations`.
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

    /// Borrows one Wyckoff identifier per input atom until `deinit`.
    pub fn wyckoffs(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.wyckoffs, self.atomCount());
    }

    /// Borrows one NUL-terminated, 7-byte site-symmetry slot per atom.
    pub fn siteSymmetrySymbols(self: Dataset) []const [7]u8 {
        return ffi.borrow([7]u8, self.raw.site_symmetry_symbols, self.atomCount());
    }

    /// Borrows one symmetry-equivalence class per input atom until `deinit`.
    pub fn equivalentAtoms(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.equivalent_atoms, self.atomCount());
    }

    /// Borrows one crystallographic orbit per input atom until `deinit`.
    pub fn crystallographicOrbits(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.crystallographic_orbits, self.atomCount());
    }

    /// Returns the primitive-cell lattice by value; `mappingToPrimitive` indexes it.
    pub fn primitiveLattice(self: Dataset) [3][3]f64 {
        return self.raw.primitive_lattice;
    }

    /// Borrows the input-to-primitive atom map until `deinit`.
    pub fn mappingToPrimitive(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.mapping_to_primitive, self.atomCount());
    }

    /// Number of atoms in the standardised cell; indexes its per-atom arrays.
    pub fn standardAtomCount(self: Dataset) usize {
        return err.checkedCount(self.raw.n_std_atoms);
    }

    /// Standardised conventional lattice, copied by value.
    pub fn standardLattice(self: Dataset) [3][3]f64 {
        return self.raw.std_lattice;
    }

    /// Returns the input-to-standardised-frame rotation by value.
    pub fn standardRotationMatrix(self: Dataset) [3][3]f64 {
        return self.raw.std_rotation_matrix;
    }

    /// Borrowed atom types of the standardised cell. Invalid after `deinit`.
    pub fn standardTypes(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.std_types, self.standardAtomCount());
    }

    /// Borrows standardised fractional positions until `deinit`.
    pub fn standardPositions(self: Dataset) []const [3]f64 {
        return ffi.borrow([3]f64, self.raw.std_positions, self.standardAtomCount());
    }

    /// Borrows the standardised-to-primitive atom map until `deinit`.
    pub fn standardMappingToPrimitive(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.std_mapping_to_primitive, self.standardAtomCount());
    }
};

/// Reads a translated fixed-width C char array to its first NUL, or returns it whole.
fn cString(field: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, field, 0) orelse field.len;
    return field[0..end];
}

/// Options for `standardizeCell`; the facade always uses spglib's default angle tolerance.
pub const StandardizeOptions = struct {
    /// True reduces to a primitive cell, false idealises to a conventional one.
    to_primitive: bool = true,
    /// Skip the idealisation step when producing a primitive cell.
    no_idealize: bool = false,
    /// Positive Cartesian symmetry tolerance; invalid values return `NonPositiveSymprec`.
    symprec: f64,
};

/// Searches the default setting and returns an owned dataset; release it with `Dataset.deinit`.
/// Borrows cell slices for the call; failure returns spglib's recorded error.
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

/// Searches a Hall setting; 0 selects the default search, other values go to spglib unchanged.
/// Returns an owned dataset; invalid settings return spglib's recorded error.
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

/// Searches with an angle tolerance in degrees; `-1.0` selects spglib's default.
/// Returns an owned dataset; cell slices are borrowed for the call and failures return spglib's error.
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

/// Takes a successful dataset pointer or returns spglib's recorded error.
fn fromRaw(raw: anytype) (err.Error || err.InputError)!Dataset {
    if (ffi.isNull(raw)) return err.lastError();
    return .{ .raw = ffi.single(c.SpglibDataset, raw) };
}

/// Standardises a copy of `cell` into allocator-owned buffers; release the result with `OwnedCell.deinit`.
/// Uses up to four slots per input atom; failure frees both buffers and returns an error.
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

/// Returns a primitive cell via `standardizeCell`, with idealisation enabled.
/// Ownership, buffer bound, and errors match that function.
pub fn findPrimitive(
    allocator: std.mem.Allocator,
    cell: Cell,
    symprec: f64,
) (err.Error || err.InputError || std.mem.Allocator.Error)!OwnedCell {
    return standardizeCell(allocator, cell, .{ .to_primitive = true, .symprec = symprec });
}

/// Refines the cell to its Bravais lattice with the default angle tolerance.
/// Returns allocator-owned buffers; uses four slots per input atom and frees them on failure.
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

/// Reduces `lattice` in place; `symprec` must be positive.
/// Leaves the lattice unchanged on invalid input or spglib failure.
pub fn niggliReduce(lattice: *[3][3]f64, symprec: f64) (err.Error || err.InputError)!void {
    if (!(symprec > 0)) return error.NonPositiveSymprec;
    if (c.spg_niggli_reduce(lattice, symprec) == 0) return err.lastError();
}

/// Shrinks to the used length when possible; the slice remains allocator-owned either way.
fn trim(comptime T: type, allocator: std.mem.Allocator, slice: []T, len: usize) []T {
    if (len == slice.len) return slice;
    return allocator.realloc(slice, len) catch slice;
}
