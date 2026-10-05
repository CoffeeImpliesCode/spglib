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

/// A symmetry dataset spglib allocated with `malloc`.
///
/// Every slice an accessor hands out borrows this dataset's storage and is
/// invalid once `deinit` runs. The value is single-owner: a copy duplicates the
/// handle to one allocation, so `deinit` runs exactly once, on one copy only,
/// and any other copy is a dangling handle from that moment. `deinit` calls
/// `spg_free_dataset`, never a Zig allocator, so a Zig leak checker cannot
/// observe these allocations.
pub const Dataset = struct {
    /// The upstream `SpglibDataset` every accessor reads. The field is
    /// reachable, so a caller may replace it; a value that did not come from a
    /// successful dataset call breaks every accessor, and `deinit` frees
    /// whatever it points at.
    raw: *c.SpglibDataset,

    /// Releases the dataset and every array inside it, and leaves `Dataset`
    /// unusable.
    ///
    /// Call this once, on the owner. A second call, or a call through a copy
    /// taken before the first, frees the same bytes twice, and every slice
    /// already handed out dangles afterwards.
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

    /// International Hermann-Mauguin symbol, borrowed from the dataset's own
    /// `international_symbol` field and ending at the first NUL byte. Invalid
    /// after `deinit`.
    pub fn internationalSymbol(self: Dataset) []const u8 {
        return cString(self.raw.international_symbol[0..]);
    }

    /// Hall symbol of the setting the search landed on, borrowed like
    /// `internationalSymbol`.
    pub fn hallSymbol(self: Dataset) []const u8 {
        return cString(self.raw.hall_symbol[0..]);
    }

    /// Origin choice of that setting, borrowed like `internationalSymbol`.
    /// Empty when the setting has no choice.
    pub fn choice(self: Dataset) []const u8 {
        return cString(self.raw.choice[0..]);
    }

    /// Point-group symbol of the crystal class, borrowed like
    /// `internationalSymbol`.
    pub fn pointgroupSymbol(self: Dataset) []const u8 {
        return cString(self.raw.pointgroup_symbol[0..]);
    }

    /// Change of basis from the input cell to the conventional setting, copied
    /// by value from the dataset and therefore independent of `deinit`.
    pub fn transformationMatrix(self: Dataset) [3][3]f64 {
        return self.raw.transformation_matrix;
    }

    /// Origin shift that goes with `transformationMatrix`, copied by value.
    pub fn originShift(self: Dataset) [3]f64 {
        return self.raw.origin_shift;
    }

    /// Number of atoms in the input cell, which is what every per-atom borrow
    /// below is indexed by.
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

    /// Borrowed Wyckoff identifiers, one per input atom. Invalid after
    /// `deinit`.
    pub fn wyckoffs(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.wyckoffs, self.atomCount());
    }

    /// Borrowed site-symmetry symbols, one per input atom, each NUL-terminated
    /// inside its own 7-character slot. Invalid after `deinit`.
    pub fn siteSymmetrySymbols(self: Dataset) []const [7]u8 {
        return ffi.borrow([7]u8, self.raw.site_symmetry_symbols, self.atomCount());
    }

    /// Borrowed symmetry-equivalence classes, one per input atom. Invalid
    /// after `deinit`.
    pub fn equivalentAtoms(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.equivalent_atoms, self.atomCount());
    }

    /// Borrowed crystallographic orbits, one per input atom. Invalid after
    /// `deinit`.
    pub fn crystallographicOrbits(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.crystallographic_orbits, self.atomCount());
    }

    /// Lattice of the primitive cell the input cell maps onto, copied by value.
    /// `mappingToPrimitive` indexes that cell, not this struct.
    pub fn primitiveLattice(self: Dataset) [3][3]f64 {
        return self.raw.primitive_lattice;
    }

    /// Borrowed map from input atoms to primitive-cell atoms, one per input
    /// atom. Invalid after `deinit`.
    pub fn mappingToPrimitive(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.mapping_to_primitive, self.atomCount());
    }

    /// Number of atoms in the standardised cell, which is what
    /// `standardTypes`, `standardPositions` and `standardMappingToPrimitive`
    /// are indexed by.
    pub fn standardAtomCount(self: Dataset) usize {
        return err.checkedCount(self.raw.n_std_atoms);
    }

    /// Standardised conventional lattice, copied by value.
    pub fn standardLattice(self: Dataset) [3][3]f64 {
        return self.raw.std_lattice;
    }

    /// Rotation that takes the input frame to the standardised frame, copied
    /// by value.
    pub fn standardRotationMatrix(self: Dataset) [3][3]f64 {
        return self.raw.std_rotation_matrix;
    }

    /// Borrowed atom types of the standardised cell. Invalid after `deinit`.
    pub fn standardTypes(self: Dataset) []const c_int {
        return ffi.borrow(c_int, self.raw.std_types, self.standardAtomCount());
    }

    /// Borrowed fractional positions of the standardised cell. Invalid after
    /// `deinit`.
    pub fn standardPositions(self: Dataset) []const [3]f64 {
        return ffi.borrow([3]f64, self.raw.std_positions, self.standardAtomCount());
    }

    /// Borrowed map from standardised-cell atoms to primitive-cell atoms.
    /// Invalid after `deinit`.
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

/// Choices `standardizeCell` passes to `spgat_standardize_cell`. Read once, at
/// the start of the call; changing the struct afterwards changes nothing.
///
/// The angle tolerance is not one of them because the facade always passes
/// `-1.0`, the sentinel the upstream `spg_standardize_cell` wrapper passes and
/// therefore the library's own default (src/spglib.c:795-801).
pub const StandardizeOptions = struct {
    /// True reduces to a primitive cell, false idealises to a conventional one.
    to_primitive: bool = true,
    /// Skip the idealisation step when producing a primitive cell.
    no_idealize: bool = false,
    /// Symmetry tolerance in Cartesian coordinates. Must be positive;
    /// anything else is `error.NonPositiveSymprec` before the C call.
    symprec: f64,
};

/// Symmetry search at the default angle tolerance, `spg_get_dataset`.
///
/// Returns a dataset the caller owns and releases with `Dataset.deinit`; on
/// failure nothing is allocated and `lastErrorCode` carries the status spglib
/// recorded. `cell` is read for the duration of the call only: spglib copies
/// what it needs, so the cell may be released as soon as the call returns.
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

/// Symmetry search pinned to a specific Hall number,
/// `spg_get_dataset_with_hall_number`.
///
/// A Hall number of 0 selects the same search `getDataset` runs: upstream
/// documents it as "hall_number = 0 gives the same as spg_get_dataset"
/// (include/spglib.h:232-236), so 0 is a valid argument here rather than an
/// out-of-range one. Every other number is passed through unchanged and
/// upstream decides whether it names a setting; a Hall number outside the
/// database comes back as the search failure spglib recorded, not as a
/// facade-level range check.
///
/// Owns its result exactly as `getDataset` does.
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

/// Symmetry search with an explicit angle tolerance, `spgat_get_dataset`.
///
/// `angle_tolerance` is a distance between lattice directions in degrees, not
/// a Cartesian tolerance; `-1.0` is the sentinel the `spg_get_dataset`
/// wrapper passes and therefore the library default. Owns its result exactly as
/// `getDataset` does.
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

/// Standardises a cell into a primitive or conventional cell,
/// `spgat_standardize_cell`.
///
/// The result is allocated from `allocator`, which is stored on it and must
/// stay valid until `OwnedCell.deinit`. `cell` is read and never modified:
/// its slices are copied into fresh buffers first, so they may be released as
/// soon as the call returns.
///
/// The buffers are sized at four times the input atom count, the growth bound
/// upstream grows to, and trimmed to the count spglib returns; when the
/// allocator cannot shrink a buffer the oversized allocation is kept, so
/// `deinit` is correct either way. spglib is given no capacity to check, so
/// this wrapper owns that bound. On failure nothing is returned and both
/// buffers are released.
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

/// Reduces a cell to its primitive cell: `standardizeCell` with
/// `to_primitive` set and idealisation left on, which is the same
/// `spgat_standardize_cell` call rather than `spgat_find_primitive`. Ownership,
/// the four-times bound and the failure behaviour are `standardizeCell`'s.
pub fn findPrimitive(
    allocator: std.mem.Allocator,
    cell: Cell,
    symprec: f64,
) (err.Error || err.InputError || std.mem.Allocator.Error)!OwnedCell {
    return standardizeCell(allocator, cell, .{ .to_primitive = true, .symprec = symprec });
}

/// Symmetrises a cell into its Bravais lattice, `spgat_refine_cell` with the
/// default angle tolerance.
///
/// The buffers are sized as upstream requires, four times the input atom count
/// (include/spglib.h:463-471 is the only place the library states it), and are
/// trimmed to the returned count. Ownership and the failure behaviour are
/// `standardizeCell`'s.
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

/// Reduces `lattice` in place, `spg_niggli_reduce`.
///
/// The lattice is modified only when the reduction succeeds; on
/// `error.NonPositiveSymprec` or a spglib failure it is left as the caller
/// passed it. A degenerate lattice has no reduced form, so that is the
/// failure to expect from one whose vectors are coplanar.
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
