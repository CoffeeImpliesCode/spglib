const std = @import("std");

const err = @import("error.zig");

/// Borrows caller-owned input; `positions` and `types` must live through each call.
/// Spglib copies needed data and retains no cell slices.
pub const Cell = struct {
    /// Lattice vectors as Cartesian columns `a`, `b`, `c`, matching spglib's C layout.
    lattice: [3][3]f64,
    /// Atomic positions in fractional coordinates, one row per atom.
    positions: []const [3]f64,
    /// Atom types, compared by equality only.
    types: []const c_int,

    /// Number of positions; validation rejects a mismatched `types` slice.
    pub fn atomCount(self: Cell) usize {
        return self.positions.len;
    }

    /// Rejects empty or mismatched cells, counts outside C `int`, and non-positive or NaN `symprec`.
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

    /// C pointer to the first lattice row; valid while `self` lives.
    /// translate-c drops `const`; do not write through it. Standardisation uses `OwnedCell`.
    pub fn latticePtr(self: *const Cell) [*c][3]f64 {
        return @ptrCast(@constCast(&self.lattice[0]));
    }

    /// C pointer to the first position, preserving the array stride.
    pub fn positionPtr(self: *const Cell) [*c][3]f64 {
        return @ptrCast(@constCast(self.positions.ptr));
    }

    /// Const C pointer to atom types for read-only calls.
    pub fn typePtr(self: *const Cell) [*c]const c_int {
        return self.types.ptr;
    }

    /// Mutable C pointer to the caller's borrowed types.
    /// Standardisation writes through it; use writable storage or `OwnedCell`.
    pub fn mutableTypePtr(self: *const Cell) [*c]c_int {
        return @constCast(self.types.ptr);
    }
};

/// Owns positions and types allocated by its allocator; `deinit` frees them.
/// Single-owner value: copies share buffers, and upstream allocations are separate.
pub const OwnedCell = struct {
    /// Allocator used by `deinit`; it must remain valid until release.
    allocator: std.mem.Allocator,
    /// Lattice vectors as Cartesian columns, matching `Cell.lattice`.
    lattice: [3][3]f64,
    /// Owned positions, resized by standardisation helpers to spglib's result count.
    positions: [][3]f64,
    /// Owned atom types, resized with `positions`.
    types: []c_int,

    /// Frees both buffers with `allocator`; the lattice is inline.
    /// Call once on the original value; release invalidates its copies.
    pub fn deinit(self: OwnedCell) void {
        self.allocator.free(self.positions);
        self.allocator.free(self.types);
    }

    /// Returns a `Cell` view with copied lattice and borrowed buffers; valid until `deinit`.
    /// Keep positions and types alive and unchanged while using the view.
    pub fn asCell(self: *const OwnedCell) Cell {
        return .{ .lattice = self.lattice, .positions = self.positions, .types = self.types };
    }

    /// Number of positions after standardisation.
    pub fn atomCount(self: *const OwnedCell) usize {
        return self.positions.len;
    }

    /// Pointer into the owner's lattice for C calls that write it.
    /// Use this instead of a pointer into the temporary returned by `asCell`.
    pub fn latticePtr(self: *const OwnedCell) [*c][3]f64 {
        return @ptrCast(@constCast(&self.lattice[0]));
    }

    /// C pointer to the first owned position, preserving the array stride.
    pub fn positionPtr(self: *const OwnedCell) [*c][3]f64 {
        return self.positions.ptr;
    }

    /// Mutable C pointer to the owned type buffer used by standardisation.
    pub fn mutableTypePtr(self: *const OwnedCell) [*c]c_int {
        return self.types.ptr;
    }
};

/// Allocates `capacity` positions and types; fill them and `lattice` before use.
/// Keep the allocator alive until `deinit`; standardisation may write four times the input atom count.
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
