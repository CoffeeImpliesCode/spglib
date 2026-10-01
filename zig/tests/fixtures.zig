// Crystal fixtures shared by the behaviour tests, the smoke example and the
// documentation.
//
// Provenance for every entry:
//
//  * `rutile` is the rutile cell upstream uses throughout test/functional/c
//    (six atoms), where the expected space group is 136 "P4_2/mnm".
//  * `bcc`, `distorted_bcc`, `fcc_primitive` and `coincident_atoms` reproduce
//    upstream test_dataset_access.cpp, test_standardization.cpp,
//    test_refine_cell.cpp and test_error.cpp.
//  * `bcc` and `cscl` share one lattice and one pair of positions and differ
//    only in the species, which is exactly the distinction upstream
//    test/functional/c/test_symmetry_search.cpp:74-83 turns on: it passes
//    `types[] = {1, 2}` and asserts a multiplicity of 48, i.e. Pm-3m, because
//    two distinguishable species at (0,0,0) and (1/2,1/2,1/2) are CsCl. The
//    same lattice with one species is bcc iron, Im-3m, whose order is 96
//    (src/spg_database.c `symmetry_operation_index` Hall 529 = {96, 7197}).
//    Reading 48 off `bcc` reads CsCl's answer off iron.
//  * `corundum` is the 30-atom hexagonal Al2O3 cell of upstream
//    test_standardization.cpp:29-64. Its lattice is oblique, so a transposed
//    reading is visible: the columns give a = b = 4.8076344022756095 with
//    gamma = 120 and c = 13.1172699198127543, while the rows would give
//    a = 5.378 and b = 4.164. R-3c is R-centred, so the primitive cell holds
//    10 of the 30 atoms, which upstream pins in
//    test_find_primitive_cell.cpp:74.
//  * `rocksalt` and `perovskite` are textbook cells whose answers are fixed by
//    the International Tables: Fm-3m (225) with 192 operations and Pm-3m (221)
//    with 48.
//  * `distorted_perovskite` is `perovskite` with the c axis shortened by
//    0.005 A, which is below a 1e-2 tolerance and above a 1e-5 one.
//  * The magnetic spin sets come from upstream test_magnetic_dataset.cpp, which
//    pins UNI 1155, 1156 and 1158 for the three rutile cases.
//  * `non_collinear_cubic` is upstream
//    test_magnetic_dataset.cpp:214-231: one atom in a cubic cell of side 10
//    with the axial site tensor (1, 0, 0), which upstream reports as 16
//    operations. It carries three doubles for one atom, so it also pins the
//    rank-1 tensor count.

const spglib = @import("spglib");

pub const Cell = spglib.Cell;

pub const bcc = Cell{
    .lattice = .{
        .{ 4, 0, 0 },
        .{ 0, 4, 0 },
        .{ 0, 0, 4 },
    },
    .positions = &.{
        .{ 0, 0, 0 },
        .{ 0.5, 0.5, 0.5 },
    },
    .types = &.{ 1, 1 },
};

/// CsCl: the same bcc lattice and positions as `bcc` with two distinguishable
/// species, which is the input upstream test_symmetry_search.cpp:74-83 uses for
/// its multiplicity of 48. Pm-3m, 48 operations.
pub const cscl = Cell{
    .lattice = .{
        .{ 4, 0, 0 },
        .{ 0, 4, 0 },
        .{ 0, 0, 4 },
    },
    .positions = &.{
        .{ 0, 0, 0 },
        .{ 0.5, 0.5, 0.5 },
    },
    .types = &.{ 1, 2 },
};

pub const rutile = Cell{
    .lattice = .{
        .{ 5, 0, 0 },
        .{ 0, 5, 0 },
        .{ 0, 0, 3 },
    },
    .positions = &.{
        .{ 0, 0, 0 },
        .{ 0.5, 0.5, 0.5 },
        .{ 0.3, 0.3, 0 },
        .{ 0.7, 0.7, 0 },
        .{ 0.2, 0.8, 0.5 },
        .{ 0.8, 0.2, 0.5 },
    },
    .types = &.{ 1, 1, 2, 2, 2, 2 },
};

/// SrTiO3 in the ideal cubic aristotype.
pub const perovskite = Cell{
    .lattice = .{
        .{ 3.905, 0, 0 },
        .{ 0, 3.905, 0 },
        .{ 0, 0, 3.905 },
    },
    .positions = &.{
        .{ 0, 0, 0 },
        .{ 0.5, 0.5, 0.5 },
        .{ 0.5, 0.5, 0 },
        .{ 0.5, 0, 0.5 },
        .{ 0, 0.5, 0.5 },
    },
    .types = &.{ 1, 2, 3, 3, 3 },
};

/// The same perovskite with c = 3.900 A: tetragonal, so it is no longer 221.
pub const distorted_perovskite = Cell{
    .lattice = .{
        .{ 3.905, 0, 0 },
        .{ 0, 3.905, 0 },
        .{ 0, 0, 3.900 },
    },
    .positions = perovskite.positions,
    .types = perovskite.types,
};

/// NaCl in the conventional rock-salt cell: an fcc lattice with a second
/// species filling its octahedral holes, so both sublattices are fcc and the
/// two are related by (1/2, 1/2, 1/2). Species 1 is the corner-and-face-centre
/// sublattice, indices 0, 2, 3 and 4 above; species 2 is the shifted one,
/// indices 1, 5, 6 and 7. That 4+4 split is what makes the cell Fm-3m with 192
/// operations; a single atom of one species at the origin and seven of the
/// other is a different structure with a different group.
pub const rocksalt = Cell{
    .lattice = .{
        .{ 5.64, 0, 0 },
        .{ 0, 5.64, 0 },
        .{ 0, 0, 5.64 },
    },
    .positions = &.{
        .{ 0, 0, 0 },
        .{ 0.5, 0.5, 0.5 },
        .{ 0.5, 0.5, 0 },
        .{ 0.5, 0, 0.5 },
        .{ 0, 0.5, 0.5 },
        .{ 0, 0, 0.5 },
        .{ 0, 0.5, 0 },
        .{ 0.5, 0, 0 },
    },
    .types = &.{ 1, 2, 1, 1, 1, 2, 2, 2 },
};

/// Upstream test_spg_standardize_cell_BCC input: measurably non-cubic.
pub const distorted_bcc = Cell{
    .lattice = .{
        .{ 3.97, 0, 0 },
        .{ 0, 4.03, 0 },
        .{ 0, 0, 4.0 },
    },
    .positions = &.{
        .{ 0.002, 0, 0 },
        .{ 0.5, 0.5001, 0.5 },
    },
    .types = &.{ 1, 1 },
};

/// Upstream test_spg_standardize_cell_corundum input: hexagonal Al2O3, 30
/// atoms, 10 per primitive cell.
pub const corundum = Cell{
    .lattice = .{
        .{ 4.8076344022756095, -2.4038172011378047, 0 },
        .{ 0, 4.1635335244786962, 0 },
        .{ 0, 0, 13.1172699198127543 },
    },
    .positions = &.{
        .{ 0.0000000000000000, 0.0000000000000000, 0.3521850942289043 },
        .{ 0.6666666666666643, 0.3333333333333357, 0.6855184275622400 },
        .{ 0.3333333333333357, 0.6666666666666643, 0.0188517608955686 },
        .{ 0.0000000000000000, 0.0000000000000000, 0.6478149057711028 },
        .{ 0.6666666666666643, 0.3333333333333357, 0.9811482391044314 },
        .{ 0.3333333333333357, 0.6666666666666643, 0.3144815724377600 },
        .{ 0.0000000000000000, 0.0000000000000000, 0.1478149057710957 },
        .{ 0.6666666666666643, 0.3333333333333357, 0.4811482391044314 },
        .{ 0.3333333333333357, 0.6666666666666643, 0.8144815724377600 },
        .{ 0.0000000000000000, 0.0000000000000000, 0.8521850942288972 },
        .{ 0.6666666666666643, 0.3333333333333357, 0.1855184275622400 },
        .{ 0.3333333333333357, 0.6666666666666643, 0.5188517608955686 },
        .{ 0.3061673906454899, 0.0000000000000000, 0.2500000000000000 },
        .{ 0.9728340573121541, 0.3333333333333357, 0.5833333333333357 },
        .{ 0.6395007239788255, 0.6666666666666643, 0.9166666666666643 },
        .{ 0.6938326093545102, 0.0000000000000000, 0.7500000000000000 },
        .{ 0.3604992760211744, 0.3333333333333357, 0.0833333333333357 },
        .{ 0.0271659426878458, 0.6666666666666643, 0.4166666666666643 },
        .{ 0.0000000000000000, 0.3061673906454899, 0.2500000000000000 },
        .{ 0.6666666666666643, 0.6395007239788255, 0.5833333333333357 },
        .{ 0.3333333333333357, 0.9728340573121541, 0.9166666666666643 },
        .{ 0.0000000000000000, 0.6938326093545102, 0.7500000000000000 },
        .{ 0.6666666666666643, 0.0271659426878458, 0.0833333333333357 },
        .{ 0.3333333333333357, 0.3604992760211744, 0.4166666666666643 },
        .{ 0.6938326093545102, 0.6938326093545102, 0.2500000000000000 },
        .{ 0.3604992760211744, 0.0271659426878458, 0.5833333333333357 },
        .{ 0.0271659426878458, 0.3604992760211744, 0.9166666666666643 },
        .{ 0.3061673906454899, 0.3061673906454899, 0.7500000000000000 },
        .{ 0.9728340573121541, 0.6395007239788255, 0.0833333333333357 },
        .{ 0.6395007239788255, 0.9728340573121541, 0.4166666666666643 },
    },
    .types = &.{
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        2, 2, 2, 2, 2, 2,
    },
};

/// Upstream test_refine_cell_BCC input: the fcc primitive lattice of a = 4.
pub const fcc_primitive = Cell{
    .lattice = .{
        .{ 0, 2, 2 },
        .{ 2, 0, 2 },
        .{ 2, 2, 0 },
    },
    .positions = &.{.{ 0, 0, 0 }},
    .types = &.{1},
};

/// Upstream test_error.cpp input: two atoms of the same type coincide.
pub const coincident_atoms = Cell{
    .lattice = .{
        .{ 4, 0, 0 },
        .{ 0, 4, 0 },
        .{ 0, 0, 4 },
    },
    .positions = &.{
        .{ 0, 0, 0 },
        .{ 0.5, 0.5, 0.5 },
        .{ 0.5, 0.5, 0.5 },
    },
    .types = &.{ 1, 1, 1 },
};

/// A cell whose lattice vectors are coplanar, so it has no volume.
pub const degenerate = Cell{
    .lattice = .{
        .{ 4, 0, 0 },
        .{ 0, 4, 0 },
        .{ 4, 4, 0 },
    },
    .positions = &.{.{ 0, 0, 0 }},
    .types = &.{1},
};

/// A cell with more types than positions; rejected before the C call.
pub const mismatched_atoms = Cell{
    .lattice = .{
        .{ 4, 0, 0 },
        .{ 0, 4, 0 },
        .{ 0, 0, 4 },
    },
    .positions = &.{
        .{ 0, 0, 0 },
        .{ 0.5, 0.5, 0.5 },
    },
    .types = &.{ 1, 1, 1 },
};

/// Ferro-, gray and antiferromagnetic variants of the rutile cell.
pub const rutile_spins = struct {
    pub const ferromagnetic = [_]f64{ 0.3, 0.3, 0, 0, 0, 0 };
    pub const gray = [_]f64{ 0, 0, 0, 0, 0, 0 };
    pub const antiferromagnetic = [_]f64{ 0.7, -0.7, 0, 0, 0, 0 };
};

/// Antiferromagnetic bcc iron: the anti-translation is (1/2, 1/2, 1/2).
pub const bcc_antiferromagnetic = Cell{
    .lattice = .{
        .{ 4, 0, 0 },
        .{ 0, 4, 0 },
        .{ 0, 0, 4 },
    },
    .positions = &.{
        .{ 0, 0, 0 },
        .{ 0.5, 0.5, 0.5 },
    },
    .types = &.{ 1, 1 },
};

pub const bcc_spins = [_]f64{ 0.6, -0.6 };

/// Upstream test_spg_get_magnetic_dataset_non_collinear: one atom carrying the
/// axial site tensor (1, 0, 0), three doubles for one atom.
pub const non_collinear_cubic = Cell{
    .lattice = .{
        .{ 10, 0, 0 },
        .{ 0, 10, 0 },
        .{ 0, 0, 10 },
    },
    .positions = &.{.{ 0, 0, 0 }},
    .types = &.{1},
};

pub const non_collinear_spins = [_]f64{ 1, 0, 0 };

/// Shared matrix helpers. Both the behaviour tests and the smoke example
/// characterise the cubic group as the signed permutation matrices.
pub fn isSignedPermutation(matrix: [3][3]c_int) bool {
    for (0..3) |row| {
        var present: usize = 0;
        for (0..3) |column| {
            const value = matrix[row][column];
            if (value == 0) continue;
            if (value != 1 and value != -1) return false;
            present += 1;
        }
        if (present != 1) return false;
    }
    for (0..3) |column| {
        var present: usize = 0;
        for (0..3) |row| {
            if (matrix[row][column] != 0) present += 1;
        }
        if (present != 1) return false;
    }
    return true;
}

/// Collapses a 3x3 signed permutation matrix into a unique key.
pub fn permutationKey(matrix: [3][3]c_int) i64 {
    var key: i64 = 0;
    for (0..3) |row| {
        for (0..3) |column| {
            key += @as(i64, @intCast(matrix[row][column] + 1)) * intPow(3, 3 * row + column);
        }
    }
    return key;
}

fn intPow(base: i64, exponent: usize) i64 {
    var result: i64 = 1;
    for (0..exponent) |_| result *= base;
    return result;
}

/// Triple product of a row-major 3x3 matrix.
pub fn determinant(matrix: [3][3]f64) f64 {
    return matrix[0][0] * (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1]) -
        matrix[0][1] * (matrix[1][0] * matrix[2][2] - matrix[1][2] * matrix[2][0]) +
        matrix[0][2] * (matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0]);
}

/// Number of distinct values in a slice of atom mappings.
pub fn distinctCount(mapping: []const c_int) usize {
    var distinct: usize = 0;
    for (mapping, 0..) |value, index| {
        var seen = false;
        for (mapping[0..index]) |earlier| {
            if (earlier == value) seen = true;
        }
        if (!seen) distinct += 1;
    }
    return distinct;
}
