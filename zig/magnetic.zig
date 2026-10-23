const std = @import("std");

const cell_mod = @import("cell.zig");
const err = @import("error.zig");
const symmetry = @import("symmetry.zig");

const Cell = cell_mod.Cell;
const Operations = symmetry.Operations;

const c = @import("c");
const ffi = @import("ffi.zig");

/// Owns a spglib-allocated magnetic dataset; release it once with `deinit`.
/// Accessor slices borrow its storage until release; `deinit` calls `spg_free_magnetic_dataset`.
pub const MagneticDataset = struct {
    /// Raw upstream handle; replacing it breaks accessors and changes what `deinit` frees.
    raw: *c.SpglibMagneticDataset,

    /// Frees the dataset and its arrays with `spg_free_magnetic_dataset`.
    /// Call once on the owner; borrowed slices become invalid.
    pub fn deinit(self: MagneticDataset) void {
        c.spg_free_magnetic_dataset(self.raw);
    }

    /// UNI serial number of the magnetic space-group type, 1 to 1651.
    pub fn uniNumber(self: MagneticDataset) c_int {
        return self.raw.uni_number;
    }

    /// 1 = type-I, 2 = type-II (gray), 3 = type-III, 4 = type-IV.
    pub fn magneticType(self: MagneticDataset) c_int {
        return self.raw.msg_type;
    }

    /// Hall number of the family or maximal space group, depending on the type.
    pub fn hallNumber(self: MagneticDataset) c_int {
        return self.raw.hall_number;
    }

    /// Tensor rank: 0 for scalar spins or 1 for vectors; sizes `standardTensors`.
    pub fn tensorRank(self: MagneticDataset) c_int {
        return self.raw.tensor_rank;
    }

    /// Number of operations, the length of `timeReversals` and `operations().rotations`.
    pub fn operationCount(self: MagneticDataset) usize {
        return err.checkedCount(self.raw.n_operations);
    }

    /// Number of input atoms, which indexes `equivalentAtoms`.
    pub fn atomCount(self: MagneticDataset) usize {
        return err.checkedCount(self.raw.n_atoms);
    }

    /// Borrowed magnetic symmetry operations. Invalid after `deinit`.
    pub fn operations(self: MagneticDataset) Operations {
        const count = self.operationCount();
        return .{
            .rotations = ffi.borrow([3][3]c_int, self.raw.rotations, count),
            .translations = ffi.borrow([3]f64, self.raw.translations, count),
        };
    }

    /// Borrows 0/1 ordinary/time-reversal flags until `deinit`; values are never -1.
    pub fn timeReversals(self: MagneticDataset) []const c_int {
        return ffi.borrow(c_int, self.raw.time_reversals, self.operationCount());
    }

    /// Borrows one symmetry-equivalence class per input atom until `deinit`.
    pub fn equivalentAtoms(self: MagneticDataset) []const c_int {
        return ffi.borrow(c_int, self.raw.equivalent_atoms, self.atomCount());
    }

    /// Returns the input-to-standard-setting basis change by value.
    pub fn transformationMatrix(self: MagneticDataset) [3][3]f64 {
        return self.raw.transformation_matrix;
    }

    /// Origin shift that goes with `transformationMatrix`, copied by value.
    pub fn originShift(self: MagneticDataset) [3]f64 {
        return self.raw.origin_shift;
    }

    /// Number of atoms in the standardised cell; indexes its per-atom arrays.
    pub fn standardAtomCount(self: MagneticDataset) usize {
        return err.checkedCount(self.raw.n_std_atoms);
    }

    /// Standardised conventional lattice, copied by value.
    pub fn standardLattice(self: MagneticDataset) [3][3]f64 {
        return self.raw.std_lattice;
    }

    /// Returns the input-to-standardised-frame rotation by value.
    pub fn standardRotationMatrix(self: MagneticDataset) [3][3]f64 {
        return self.raw.std_rotation_matrix;
    }

    /// Borrowed atom types of the standardised cell. Invalid after `deinit`.
    pub fn standardTypes(self: MagneticDataset) []const c_int {
        return ffi.borrow(c_int, self.raw.std_types, self.standardAtomCount());
    }

    /// Borrows standardised fractional positions until `deinit`.
    pub fn standardPositions(self: MagneticDataset) []const [3]f64 {
        return ffi.borrow([3]f64, self.raw.std_positions, self.standardAtomCount());
    }

    /// Borrows one scalar per atom at rank 0 or three components at rank 1, until `deinit`.
    /// Constructors reject ranks above 1 with `TensorRankOutOfRange`.
    pub fn standardTensors(self: MagneticDataset) []const f64 {
        const rank: u8 = @intCast(std.math.clamp(self.tensorRank(), 0, 1));
        const count = self.standardAtomCount() * tensorVolume(rank);
        return ffi.borrow(f64, self.raw.std_tensors, count);
    }

    /// Lattice of the primitive cell the input cell maps onto, copied by value.
    pub fn primitiveLattice(self: MagneticDataset) [3][3]f64 {
        return self.raw.primitive_lattice;
    }
};

/// Options for `getMagneticDatasetWithTensors`.
pub const TensorOptions = struct {
    /// Tensor rank: 0 for scalar spins or 1 for vectors; other values are rejected.
    rank: u8,
    /// Positive Cartesian tolerance; non-positive or NaN values return `NonPositiveSymprec`.
    symprec: f64,
    /// True for axial tensors (spins and magnetic moments).
    is_axial: bool = false,
    /// -1.0 selects the spglib default.
    angle_tolerance: f64 = -1.0,
    /// -1.0 selects the spglib default.
    mag_symprec: f64 = -1.0,
};

/// Searches rank-0 magnetic symmetry with one spin per atom; input is borrowed for the call.
/// Wrong length returns `TensorCountMismatch`; result is caller-owned (`deinit`), and spglib failures return `Error`.
pub fn getMagneticDataset(
    cell: Cell,
    spins: []const f64,
    symprec: f64,
) (err.Error || err.InputError)!MagneticDataset {
    return getMagneticDatasetWithTensors(cell, spins, .{ .rank = 0, .symprec = symprec });
}

/// Requires one value per atom at rank 0 or three at rank 1; other ranks return `TensorRankOutOfRange`.
/// Borrows input for the call; length mismatch returns `TensorCountMismatch`; result is caller-owned (`deinit`).
pub fn getMagneticDatasetWithTensors(
    cell: Cell,
    tensors: []const f64,
    options: TensorOptions,
) (err.Error || err.InputError)!MagneticDataset {
    if (options.rank > 1) return error.TensorRankOutOfRange;
    try cell.validate(options.symprec);
    const expected = cell.atomCount() * tensorVolume(options.rank);
    if (tensors.len != expected) return error.TensorCountMismatch;

    const raw = c.spgms_get_magnetic_dataset(
        cell.latticePtr(),
        cell.positionPtr(),
        cell.typePtr(),
        tensors.ptr,
        @intCast(options.rank),
        @intCast(cell.atomCount()),
        @intFromBool(options.is_axial),
        options.symprec,
        options.angle_tolerance,
        options.mag_symprec,
    );
    if (ffi.isNull(raw)) return err.lastError();
    return .{ .raw = ffi.single(c.SpglibMagneticDataset, raw) };
}

/// Number of doubles per atom for supported tensor ranks.
fn tensorVolume(rank: u8) usize {
    return switch (rank) {
        0 => 1,
        1 => 3,
        else => 0,
    };
}
