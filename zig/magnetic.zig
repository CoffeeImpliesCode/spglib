// Zig facade for spglib: magnetic symmetry datasets.
//
// Magnetic symmetry is optional upstream API, not an extension of the plain
// dataset: it takes site tensors and returns time-reversal flags. It is exposed
// here explicitly rather than folded into `Dataset`, so nothing about the
// magnetic contract is hidden behind the ordinary path.

const std = @import("std");

const cell_mod = @import("cell.zig");
const err = @import("error.zig");
const symmetry = @import("symmetry.zig");

const Cell = cell_mod.Cell;
const Operations = symmetry.Operations;

const c = @import("c");
const ffi = @import("ffi.zig");

/// A magnetic symmetry dataset spglib allocated with `malloc`.
///
/// Like `Dataset`, every slice an accessor hands out borrows this dataset's
/// storage and is invalid once `deinit` runs, and `deinit` releases through
/// `spg_free_magnetic_dataset` rather than a Zig allocator, so a Zig leak
/// checker cannot observe the allocation. The value is single-owner: a copy
/// duplicates the handle to one allocation, so `deinit` runs exactly once, on
/// one copy only.
pub const MagneticDataset = struct {
    /// The upstream `SpglibMagneticDataset` every accessor reads. The field is
    /// reachable, so a caller may replace it; a value that did not come from a
    /// successful magnetic dataset call breaks every accessor, and `deinit`
    /// frees whatever it points at.
    raw: *c.SpglibMagneticDataset,

    /// Releases the dataset and every array inside it, and leaves
    /// `MagneticDataset` unusable.
    ///
    /// Call this once, on the owner. A second call, or a call through a copy
    /// taken before the first, frees the same bytes twice.
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

    /// Rank of the site tensors the search ran with: 0 for collinear spins, 1
    /// for a vector per atom. `standardTensors` is sized from it.
    pub fn tensorRank(self: MagneticDataset) c_int {
        return self.raw.tensor_rank;
    }

    /// Number of magnetic symmetry operations, the length of
    /// `timeReversals` and of `operations().rotations`.
    pub fn operationCount(self: MagneticDataset) usize {
        return err.checkedCount(self.raw.n_operations);
    }

    /// Number of atoms in the input cell, which is what `equivalentAtoms` is
    /// indexed by.
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

    /// Borrowed time-reversal flags: 0 for an ordinary operation, 1 for one
    /// carrying time reversal. Never -1. `spin.c:493` sets
    /// `timerev = (1 - spin_flip) / 2` with `spin_flip` in {+1,-1}, and
    /// `spglib.c:508` inverts that as `spin_flip = 1 - 2 * timerev`, so the
    /// stored flag is 0 or 1. `docs/magnetic_dataset.md:82-85` states the same
    /// contract, and `python/spglib/msg.py:481` reads it back as
    /// "0 and 1 indicate ordinary and anti-time-reversal operations".
    /// The ±1 convention belongs to `spin_flips`, the separate output of
    /// `spg_get_symmetry_with_site_tensors` ("1 for non time reversal and -1 for
    /// time reversal for each symmetry operation",
    /// include/spglib.h:286-288), not to this array.
    /// Invalid after `deinit`.
    pub fn timeReversals(self: MagneticDataset) []const c_int {
        return ffi.borrow(c_int, self.raw.time_reversals, self.operationCount());
    }

    /// Borrowed symmetry-equivalence classes, one per input atom. Invalid
    /// after `deinit`.
    pub fn equivalentAtoms(self: MagneticDataset) []const c_int {
        return ffi.borrow(c_int, self.raw.equivalent_atoms, self.atomCount());
    }

    /// Change of basis from the input cell to the standardised setting, copied
    /// by value and therefore independent of `deinit`.
    pub fn transformationMatrix(self: MagneticDataset) [3][3]f64 {
        return self.raw.transformation_matrix;
    }

    /// Origin shift that goes with `transformationMatrix`, copied by value.
    pub fn originShift(self: MagneticDataset) [3]f64 {
        return self.raw.origin_shift;
    }

    /// Number of atoms in the standardised cell, which is what
    /// `standardTypes`, `standardPositions` and `standardTensors` are indexed
    /// by.
    pub fn standardAtomCount(self: MagneticDataset) usize {
        return err.checkedCount(self.raw.n_std_atoms);
    }

    /// Standardised conventional lattice, copied by value.
    pub fn standardLattice(self: MagneticDataset) [3][3]f64 {
        return self.raw.std_lattice;
    }

    /// Rotation that takes the input frame to the standardised frame, copied
    /// by value.
    pub fn standardRotationMatrix(self: MagneticDataset) [3][3]f64 {
        return self.raw.std_rotation_matrix;
    }

    /// Borrowed atom types of the standardised cell. Invalid after `deinit`.
    pub fn standardTypes(self: MagneticDataset) []const c_int {
        return ffi.borrow(c_int, self.raw.std_types, self.standardAtomCount());
    }

    /// Borrowed fractional positions of the standardised cell. Invalid after
    /// `deinit`.
    pub fn standardPositions(self: MagneticDataset) []const [3]f64 {
        return ffi.borrow([3]f64, self.raw.std_positions, self.standardAtomCount());
    }

    /// Borrowed tensors of the standardised structure: one double per atom for
    /// a rank-0 search, three per atom for a rank-1 one. Upstream copies them
    /// as `tensors[i]` for a scalar and `tensors[i * 3 + s]` for a vector
    /// (src/spglib.c:1635-1641) into a buffer of
    /// `spn_alloc_site_tensors(n_std_atoms, tensor_rank)`. Invalid after
    /// `deinit`.
    ///
    /// The length follows `tensorRank` clamped to 0..1, so a dataset whose rank
    /// is neither 0 nor 1 reports rank 1's three doubles per atom rather than
    /// none. That case is not reachable through this module: both constructors
    /// reject a rank above 1 with `error.TensorRankOutOfRange` before the C
    /// call, so `tensorRank` is 0 or 1 on every dataset these entry points
    /// produce. It arises only on a value assembled by hand from `raw`.
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

/// Choices `getMagneticDatasetWithTensors` passes to
/// `spgms_get_magnetic_dataset`. Read once, at the start of the call.
pub const TensorOptions = struct {
    /// 0 for collinear spins, 1 for a vector per atom. spglib implements no
    /// other rank; `SiteTensorType` stops at `NONCOLLINEAR` and
    /// `spn_alloc_site_tensors` returns NULL above it.
    rank: u8,
    /// Symmetry tolerance in Cartesian coordinates.
    symprec: f64,
    /// True for axial tensors (spins and magnetic moments).
    is_axial: bool = false,
    /// -1.0 selects the spglib default.
    angle_tolerance: f64 = -1.0,
    /// -1.0 selects the spglib default.
    mag_symprec: f64 = -1.0,
};

/// Magnetic symmetry search for collinear spins, `spgms_get_magnetic_dataset`
/// at rank 0. `spins` holds one double per atom and is read for the duration
/// of the call only. The dataset is owned by the caller and released with
/// `MagneticDataset.deinit`.
pub fn getMagneticDataset(
    cell: Cell,
    spins: []const f64,
    symprec: f64,
) (err.Error || err.InputError)!MagneticDataset {
    return getMagneticDatasetWithTensors(cell, spins, .{ .rank = 0, .symprec = symprec });
}

/// Magnetic symmetry search for arbitrary site tensors,
/// `spgms_get_magnetic_dataset`.
///
/// `tensors` must hold exactly `cell.atomCount() * tensorVolume(rank)` doubles,
/// one per atom at rank 0 and three at rank 1; any other length is
/// `error.TensorCountMismatch` and a rank above 1 is
/// `error.TensorRankOutOfRange`, both before the C call. The slice is read for
/// the duration of the call only. The dataset is owned by the caller and
/// released with `MagneticDataset.deinit`.
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

/// Number of doubles that describe one atom's tensor: one scalar for rank 0,
/// three components for rank 1, and nothing for any other rank. Upstream
/// allocates exactly these counts (`src/cell.c:67-79` and `src/spin.c:279-293`)
/// and states them in the struct contract at `src/cell.h:31-32`.
fn tensorVolume(rank: u8) usize {
    return switch (rank) {
        0 => 1,
        1 => 3,
        else => 0,
    };
}
