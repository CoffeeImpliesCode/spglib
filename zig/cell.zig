// Zig facade for spglib: crystal cells.
//
// Layout follows include/spglib.h exactly: the lattice is `[[a_x, b_x, c_x],
// [a_y, b_y, c_y], [a_z, b_z, c_z]]`, so a, b and c are its *columns*, and
// `positions` are fractional coordinates. `src/spin.c:322-325` confirms it:
// `rot_cart = lattice @ rot @ lattice^-1` is a Cartesian rotation only when the
// columns are the basis vectors, and the Python binding transposes on the way
// out for the same reason. Swapping the layout silently produces wrong
// symmetry on every non-orthogonal cell, so the types below keep the C layout
// and document it rather than transposing.

const std = @import("std");

const err = @import("error.zig");

/// A borrowed crystal cell.
///
/// The slices must outlive every spglib call that reads them; spglib copies what
/// it needs and never retains the pointers.
pub const Cell = struct {
    /// Lattice vectors as columns in Cartesian components.
    ///
    /// `lattice[0][0], lattice[1][0], lattice[2][0]` is a = (a_x, a_y, a_z);
    /// column 1 is b and column 2 is c. This is the layout `include/spglib.h`
    /// documents and spglib computes with, not the transposed row convention.
    lattice: [3][3]f64,
    /// Atomic positions in fractional coordinates, one row per atom.
    positions: []const [3]f64,
    /// Atom types, compared by equality only.
    types: []const c_int,

    pub fn atomCount(self: Cell) usize {
        return self.positions.len;
    }

    /// Checks the invariants the C API cannot check itself: matching atom
    /// counts, at least one atom, a count that fits in `int num_atom` and a
    /// positive symmetry tolerance.
    pub fn validate(self: Cell, symprec: f64) err.InputError!void {
        if (self.positions.len == 0) return error.EmptyCell;
        if (self.types.len != self.positions.len) return error.AtomCountMismatch;
        if (self.positions.len > std.math.maxInt(c_int)) return error.AtomCountOutOfRange;
        if (!(symprec > 0)) return error.NonPositiveSymprec;
    }

    /// Cell volume `|a . (b x c)|` in the units of the lattice vectors.
    pub fn volume(self: Cell) f64 {
        const a = self.column(0);
        const b = self.column(1);
        const c = self.column(2);
        const cross = .{
            b[1] * c[2] - b[2] * c[1],
            b[2] * c[0] - b[0] * c[2],
            b[0] * c[1] - b[1] * c[0],
        };
        return @abs(a[0] * cross[0] + a[1] * cross[1] + a[2] * cross[2]);
    }

    /// Length of lattice vector `index` (0 = a, 1 = b, 2 = c).
    pub fn length(self: Cell, index: usize) f64 {
        const vector = self.column(index);
        return @sqrt(vector[0] * vector[0] + vector[1] * vector[1] + vector[2] * vector[2]);
    }

    /// Cartesian coordinates of atom `atom`.
    pub fn toCartesian(self: Cell, atom: usize) [3]f64 {
        const position = self.positions[atom];
        var result: [3]f64 = .{ 0, 0, 0 };
        for (0..3) |axis| {
            for (0..3) |vector| {
                result[axis] += position[vector] * self.lattice[axis][vector];
            }
        }
        return result;
    }

    /// Lattice vector `index` in Cartesian components, read as a column.
    pub fn column(self: Cell, index: usize) [3]f64 {
        return .{ self.lattice[0][index], self.lattice[1][index], self.lattice[2][index] };
    }

    /// Angle between two lattice vectors in radians.
    pub fn angle(self: Cell, first: usize, second: usize) f64 {
        const a = self.column(first);
        const b = self.column(second);
        const la = self.length(first);
        const lb = self.length(second);
        const dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
        return std.math.acos(dot / (la * lb));
    }

    /// Upstream's entry points declare the lattice as `double lattice[3][3]`,
    /// which as a parameter is `double (*)[3]`: a pointer to the *first row*,
    /// not to the whole 2D array.  That is why this returns `[*c][3]f64` and
    /// why it points at `lattice[0]`.  It is not const, because the C side
    /// may write through it.
    ///
    /// The receiver is `*const Cell` rather than `Cell` on purpose.  These are
    /// called on `const` fixtures, and a by-value receiver would hand back a
    /// pointer into a temporary copy that is dead the moment the call
    /// returns.  The `const` is dropped deliberately: upstream's read-only
    /// entry points take non-const pointers, and laundering the qualifier is
    /// what lets one helper serve both directions.
    pub fn latticePtr(self: *const Cell) [*c][3]f64 {
        return @ptrCast(@constCast(&self.lattice[0]));
    }

    /// As with the lattice, `double position[][3]` is a pointer to the first
    /// position.  Passing a pointer to a pointer would change the stride the
    /// C side assumes.
    pub fn positionPtr(self: *const Cell) [*c][3]f64 {
        return @ptrCast(@constCast(self.positions.ptr));
    }

    /// `const int *type`, as `spg_get_dataset` and the other read-only
    /// entry points declare it.
    pub fn typePtr(self: *const Cell) [*c]const c_int {
        return self.types.ptr;
    }

    /// The `spgat_*` family takes `int *type` rather than `const int *`,
    /// even though it only reads the types.  Upstream's own headers are
    /// inconsistent here, so the fork exposes both shapes instead of
    /// casting at each of the eleven call sites.
    pub fn mutableTypePtr(self: *const Cell) [*c]c_int {
        return @constCast(self.types.ptr);
    }
};

/// A cell owned by a Zig allocator.
///
/// `spg_standardize_cell`, `spg_find_primitive` and `spg_refine_cell` write
/// their results into caller-provided buffers; this type owns those buffers and
/// releases them with the same allocator. No process-global allocator hook is
/// installed, and nothing allocated by upstream `malloc` is freed here.
pub const OwnedCell = struct {
    allocator: std.mem.Allocator,
    lattice: [3][3]f64,
    positions: [][3]f64,
    types: []c_int,

    /// Releases the buffers. The lattice is inline and needs no release.
    pub fn deinit(self: OwnedCell) void {
        self.allocator.free(self.positions);
        self.allocator.free(self.types);
    }

    /// Borrows the cell for further spglib calls. Invalid after `deinit`.
    pub fn asCell(self: *const OwnedCell) Cell {
        return .{ .lattice = self.lattice, .positions = self.positions, .types = self.types };
    }

    pub fn atomCount(self: *const OwnedCell) usize {
        return self.positions.len;
    }

    /// The `spgat_*` family writes through all three of these, so an owned cell
    /// cannot borrow itself: `asCell` returns a struct by value, and a pointer
    /// taken into that temporary would outlive it. These address the owner's own
    /// fields instead, which is what a call that fills the buffers needs.
    pub fn latticePtr(self: *const OwnedCell) [*c][3]f64 {
        return @ptrCast(@constCast(&self.lattice[0]));
    }

    /// As with `Cell.positionPtr`: a pointer to the first position, not to a
    /// pointer to one, because the C side assumes that stride.
    pub fn positionPtr(self: *const OwnedCell) [*c][3]f64 {
        return self.positions.ptr;
    }

    /// `spgat_*` declares `int *type` even where it only reads.
    pub fn mutableTypePtr(self: *const OwnedCell) [*c]c_int {
        return self.types.ptr;
    }
};

/// Allocates `capacity` atoms. The caller chooses the capacity: the lattice is
/// left undefined and only `positions[0..capacity]` and `types[0..capacity]`
/// are written by the caller before the spglib call that fills them.
///
/// `spg_standardize_cell`, `spg_find_primitive` and `spg_refine_cell` write up
/// to four times the input atom count and never check the buffer they were
/// given, so every one of those paths needs `4 * atomCount` slots. Only
/// `spg_refine_cell` says so in the header (include/spglib.h:463-471); the
/// standardisation paths say it nowhere and pass no array size.
pub fn allocateCell(allocator: std.mem.Allocator, capacity: usize) !OwnedCell {
    const positions = try allocator.alloc([3]f64, capacity);
    errdefer allocator.free(positions);
    const types = try allocator.alloc(c_int, capacity);
    return .{
        .allocator = allocator,
        .lattice = undefined,
        .positions = positions,
        .types = types,
    };
}
