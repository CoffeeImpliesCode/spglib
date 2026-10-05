// Exercises the remaining public entry points of the facade.
//
// This file exists so that `zig build check` and `zig build check-targets`
// compile every public declaration, accessors included, instead of only the
// handful the other tests happen to call. It is an ordinary test file: natively
// it runs and checks the values, and for a foreign target it is compiled without
// running, which is what makes the cross-target check meaningful.
//
// ## What a runtime-loading build needs
//
// Such a build has no library until `load` has been called, so every test calls
// `nativeReady()` first. That is a no-op at comptime in a linked build. A
// runtime-loading build that was not told which provider to use stops with the
// variable's name rather than reporting a failure that says nothing about the
// reason.

const std = @import("std");

const spglib = @import("spglib");
const fixtures = @import("fixtures.zig");
const provider = @import("provider.zig");

const nativeReady = provider.nativeReady;
const testing = std.testing;

test "cell helpers report geometry on an oblique cell" {
    nativeReady();
    const cell = fixtures.perovskite;
    try testing.expectApproxEqAbs(3.905, cell.length(0), 1e-12);
    try testing.expectApproxEqAbs(3.905, cell.length(2), 1e-12);
    try testing.expectApproxEqAbs(3.905 * 3.905 * 3.905, cell.volume(), 1e-9);

    // The first perovskite atom sits on the origin in Cartesian coordinates.
    const origin = cell.toCartesian(0);
    try testing.expectApproxEqAbs(0, origin[0], 1e-12);
    try testing.expectApproxEqAbs(0, origin[1], 1e-12);
    try testing.expectApproxEqAbs(0, origin[2], 1e-12);

    // The body-centre titanium maps to the middle of the cube.
    const centre = cell.toCartesian(1);
    try testing.expectApproxEqAbs(1.9525, centre[0], 1e-9);
    try testing.expectApproxEqAbs(1.9525, centre[2], 1e-9);

    // Corundum is not diagonal, so it distinguishes the column basis from its
    // transpose: the columns are 4.8076, 4.8076 and 13.1173 with an angle of
    // 120 degrees between the first two, and the rows are not those.
    const oblique = fixtures.corundum;
    try testing.expectApproxEqAbs(4.8076344022756095, oblique.length(1), 1e-12);
    try testing.expectApproxEqAbs(13.1172699198127543, oblique.length(2), 1e-12);
    try testing.expectApproxEqAbs(120.0, oblique.angle(0, 1) * 180.0 / std.math.pi, 1e-9);
    try testing.expectApproxEqRel(
        @abs(fixtures.determinant(oblique.lattice)),
        oblique.volume(),
        1e-12,
    );
}

test "the space-group type of Hall number 419 matches the upstream table" {
    nativeReady();

    // Every field is pinned by
    // test/functional/fortran/test_fortran_spg_get_spacegroup_type.F90:40-69.
    const sgtype = try spglib.getSpacegroupType(419);
    try testing.expectEqual(@as(c_int, 136), sgtype.number);
    try testing.expectEqual(@as(c_int, 419), sgtype.hallNumber);
    try testing.expectEqual(@as(c_int, 36), sgtype.arithmeticCrystalClassNumber);
    try testing.expectEqualStrings("P4_2/mnm", sgtype.internationalShort());
    // The full Hermann-Mauguin symbol keeps the blank after the lattice
    // letter: src/spg_database.c:851 stores "P 4_2/m 2_1/n 2/m  " in
    // `international_full`, and `spgdb_remove_space` (src/spg_database.c:10225)
    // only strips the trailing padding, never the interior blank.
    try testing.expectEqualStrings("P 4_2/m 2_1/n 2/m", sgtype.internationalFull());
    try testing.expectEqualStrings("P 4_2/m n m", sgtype.international());
    try testing.expectEqualStrings("D4h^14", sgtype.schoenflies());
    try testing.expectEqualStrings("-P 4n 2n", sgtype.hallSymbol());
    try testing.expectEqualStrings("", sgtype.choice());
    try testing.expectEqualStrings("4/mmm", sgtype.pointgroupInternational());
    try testing.expectEqualStrings("D4h", sgtype.pointgroupSchoenflies());
    try testing.expectEqualStrings("4/mmmP", sgtype.arithmeticCrystalClassSymbol());
}

test "the space-group type of Hall number 343 matches the upstream table" {
    nativeReady();

    // A second record from the same upstream subtest, whose every field is
    // independently pinned by
    // test/functional/fortran/test_fortran_spg_get_spacegroup_type.F90:82-94
    // (`test_spacegroup_type_from_symmetry_Imma`). Two settings with different
    // lengths in every string field are what catch a field mapped to the wrong
    // member of the C struct: one record can agree with a swap, two cannot.
    const sgtype = try spglib.getSpacegroupType(343);
    try testing.expectEqual(@as(c_int, 74), sgtype.number);
    try testing.expectEqual(@as(c_int, 343), sgtype.hallNumber);
    try testing.expectEqual(@as(c_int, 21), sgtype.arithmeticCrystalClassNumber);
    try testing.expectEqualStrings("Imma", sgtype.internationalShort());
    try testing.expectEqualStrings("I 2/m 2/m 2/a", sgtype.internationalFull());
    try testing.expectEqualStrings("I m m a", sgtype.international());
    try testing.expectEqualStrings("D2h^28", sgtype.schoenflies());
    try testing.expectEqualStrings("-I 2b 2", sgtype.hallSymbol());
    try testing.expectEqualStrings("", sgtype.choice());
    try testing.expectEqualStrings("mmm", sgtype.pointgroupInternational());
    try testing.expectEqualStrings("D2h", sgtype.pointgroupSchoenflies());
    try testing.expectEqualStrings("mmmI", sgtype.arithmeticCrystalClassSymbol());
}

test "a dataset reports the setting and origin choice of its type" {
    nativeReady();

    const dataset = try spglib.getDataset(fixtures.rutile, 1e-5);
    defer dataset.deinit();

    // Rutile is P4_2/mnm in its only setting, Hall 419, which upstream pins
    // as "-P 4n 2n" with no origin choice.
    try testing.expectEqual(@as(c_int, 419), dataset.hallNumber());
    try testing.expectEqualStrings("-P 4n 2n", dataset.hallSymbol());
    try testing.expectEqualStrings("", dataset.choice());
}

test "dataset symbols, matrices and site data are well formed" {
    nativeReady();

    const dataset = try spglib.getDataset(fixtures.bcc, 1e-5);
    defer dataset.deinit();

    const sgtype = try spglib.getSpacegroupType(dataset.hallNumber());
    try testing.expectEqualStrings("Im-3m", sgtype.internationalShort());
    // Im-3m is the body-centred m-3m arithmetic class: arth_get_symbol maps
    // space group 229 to class 73, whose symbol is "m-3mI" (src/arithmetic.c).
    try testing.expectEqual(@as(c_int, 73), sgtype.arithmeticCrystalClassNumber);
    try testing.expectEqualStrings("m-3mI", sgtype.arithmeticCrystalClassSymbol());

    // The change-of-basis matrix is unimodular and the origin shift is finite.
    try testing.expectApproxEqAbs(1.0, @abs(fixtures.determinant(dataset.transformationMatrix())), 1e-6);
    for (dataset.originShift()) |component| try testing.expect(std.math.isFinite(component));

    // The standard rotation matrix is orthogonal.
    const rotation = dataset.standardRotationMatrix();
    for (0..3) |row| {
        for (0..3) |column| {
            var dot: f64 = 0;
            for (0..3) |inner| dot += rotation[row][inner] * rotation[column][inner];
            try testing.expectApproxEqAbs(@as(f64, if (row == column) 1 else 0), dot, 1e-6);
        }
    }

    const atoms = dataset.atomCount();
    for (dataset.wyckoffs()) |wyckoff| try testing.expect(wyckoff >= 0 and wyckoff <= 28);
    for (dataset.equivalentAtoms()) |equivalent| {
        try testing.expect(equivalent >= 0 and equivalent < atoms);
    }
    for (dataset.mappingToPrimitive()) |mapped| {
        try testing.expect(mapped >= 0 and mapped < dataset.atomCount());
    }

    // The Wyckoff identifiers of bcc iron share one site symmetry.
    try testing.expectEqual(dataset.wyckoffs()[0], dataset.wyckoffs()[1]);
}

test "primitive lattice volume is reported through the cell type" {
    nativeReady();

    const dataset = try spglib.getDataset(fixtures.bcc, 1e-5);
    defer dataset.deinit();
    const primitive = spglib.Cell{
        .lattice = dataset.primitiveLattice(),
        .positions = &.{.{ 0, 0, 0 }},
        .types = &.{1},
    };
    // Body centring halves the cell: the conventional bcc cell holds two atoms
    // and its primitive cell one, so the primitive lattice has half the volume.
    // `> 0` would pass for a zero or transposed lattice; the exact ratio does
    // not.
    try testing.expectApproxEqRel(fixtures.bcc.volume(), 2 * primitive.volume(), 1e-6);
}

test "magnetic dataset accessors are well formed" {
    nativeReady();

    const dataset = try spglib.getMagneticDataset(fixtures.rutile, &fixtures.rutile_spins.antiferromagnetic, 1e-5);
    defer dataset.deinit();

    // The fixture is upstream's own antiferromagnetic rutile, not a cell
    // chosen to suit the code: test_magnetic_dataset.cpp:11-25 defines the same
    // lattice, the same six positions and types {1,1,2,2,2,2}, :70-74 sets the
    // spins {0.7,-0.7,0,0,0,0}, and :76-81 asserts msg_type 3 and uni_number
    // 1158 with SPGLIB_SUCCESS at symprec 1e-5. database/msg/msg_numbers.csv:1159
    // maps that to BNS 136.498. The facade reaches the same routine because
    // spg_get_magnetic_dataset (src/spglib.c:249-255) forwards angle_tolerance
    // and mag_symprec as -1.0, the TensorOptions defaults.
    try testing.expectEqual(@as(c_int, 3), dataset.magneticType());
    try testing.expectEqual(@as(c_int, 1158), dataset.uniNumber());
    try testing.expectEqual(@as(c_int, 0), dataset.tensorRank());
    const atoms = dataset.atomCount();
    for (dataset.equivalentAtoms()) |equivalent| {
        try testing.expect(equivalent >= 0 and equivalent < atoms);
    }
    try testing.expectEqual(dataset.standardAtomCount(), dataset.standardTypes().len);
    try testing.expectEqual(dataset.standardAtomCount(), dataset.standardPositions().len);
    try testing.expectEqual(dataset.standardAtomCount(), dataset.standardTensors().len);
    try testing.expectApproxEqAbs(1.0, @abs(fixtures.determinant(dataset.transformationMatrix())), 1e-6);
    for (dataset.originShift()) |component| try testing.expect(std.math.isFinite(component));

    // Rutile is already its own conventional cell, so the standardised cell is
    // the input cell: a = b = 5 and c = 3 at the same volume. The bound is the
    // search tolerance the standardisation ran at.
    const standard = spglib.Cell{
        .lattice = dataset.standardLattice(),
        .positions = dataset.standardPositions(),
        .types = dataset.standardTypes(),
    };
    try testing.expectApproxEqAbs(5.0, standard.length(0), 1e-6);
    try testing.expectApproxEqAbs(5.0, standard.length(1), 1e-6);
    try testing.expectApproxEqAbs(3.0, standard.length(2), 1e-6);
    try testing.expectApproxEqRel(fixtures.rutile.volume(), standard.volume(), 1e-6);

    // The standard rotation matrix takes the input frame to the standard
    // frame, so rotating the input lattice by it must reproduce the
    // standardised lattice. That is the claim the field carries
    // (docs/magnetic_dataset.md:101-103 defers to `dataset_idealized_cell`)
    // and it is checkable without freezing the matrix entries.
    //
    // `get_rigid_rotation` currently builds
    // `lattice @ inv(tmat) @ tmat @ inv(lattice)`
    // (src/magnetic_spacegroup.c:1041-1043), whose middle factors cancel, so
    // the shipped code returns the identity for every input. Asserting that
    // would freeze an apparent upstream slip: `inv_tmat_bravais` is computed
    // from `tmat`, not from `tmat_bravais` as its name says. The lattice
    // agreement below is the statement that stays true either way, and
    // rutile is already its own conventional cell, so identity is what a
    // correct standardisation must produce for this fixture.
    const rotation = dataset.standardRotationMatrix();
    for (0..3) |row| {
        for (0..3) |column| {
            var dot: f64 = 0;
            for (0..3) |inner| dot += rotation[row][inner] * rotation[column][inner];
            try testing.expectApproxEqAbs(@as(f64, if (row == column) 1 else 0), dot, 1e-6);
        }
    }
    try testing.expectApproxEqAbs(1.0, @abs(fixtures.determinant(rotation)), 1e-6);

    var rotated: [3][3]f64 = undefined;
    for (0..3) |row| {
        for (0..3) |column| {
            var sum: f64 = 0;
            for (0..3) |inner| {
                sum += rotation[row][inner] * fixtures.rutile.lattice[inner][column];
            }
            rotated[row][column] = sum;
        }
    }
    for (0..3) |row| {
        for (0..3) |column| {
            try testing.expectApproxEqAbs(
                dataset.standardLattice()[row][column],
                rotated[row][column],
                1e-6,
            );
        }
    }

    const primitive = spglib.Cell{
        .lattice = dataset.primitiveLattice(),
        .positions = &.{.{ 0, 0, 0 }},
        .types = &.{1},
    };
    // Rutile is a P lattice, so its magnetic dataset's primitive cell is the
    // conventional cell itself and the two must have the same volume. That is
    // a property of the centring rather than of the accessor, and it is what
    // makes a zero or transposed lattice visible here: `> 0` would not.
    const input = spglib.Cell{
        .lattice = dataset.standardLattice(),
        .positions = &.{.{ 0, 0, 0 }},
        .types = &.{1},
    };
    try testing.expectApproxEqRel(input.volume(), primitive.volume(), 1e-6);
}

test "magnetic space-group type carries its numbers" {
    nativeReady();

    // database/msg/msg_numbers.csv records Litvin 1153, BNS 136.496,
    // OG 136.2.1153 at UNI 1156.
    const magnetic_type = try spglib.getMagneticSpacegroupType(1156);
    try testing.expectEqual(@as(c_int, 1156), magnetic_type.uniNumber);
    try testing.expectEqual(@as(c_int, 1153), magnetic_type.litvinNumber);
    try testing.expectEqual(@as(c_int, 136), magnetic_type.number);
    try testing.expectEqualStrings("136.496", magnetic_type.bnsNumber());
    try testing.expectEqualStrings("136.2.1153", magnetic_type.ogNumber());
    try testing.expect(magnetic_type.magneticType >= 1 and magnetic_type.magneticType <= 4);
}

test "allocateCell supplies the fourfold headroom the raw standardisation path needs" {
    nativeReady();

    // `allocateCell` allocates exactly the capacity it is asked for, so the
    // four-times-the-atom-count rule is the caller's to apply.
    // `spgat_standardize_cell` overwrites the buffers without ever being told
    // how large they are, and upstream's distorted bcc cell of
    // test_standardization.cpp:9-14 reduces from two conventional atoms to
    // one primitive atom.
    const input = fixtures.distorted_bcc;
    const capacity = input.atomCount() * 4;
    var result = try spglib.allocateCell(testing.allocator, capacity);
    defer result.deinit();
    result.lattice = input.lattice;
    @memcpy(result.positions[0..input.atomCount()], input.positions);
    @memcpy(result.types[0..input.atomCount()], input.types);

    // The pointers address `result` itself. `OwnedCell.asCell` copies the
    // lattice by value, so a pointer taken from that temporary would make
    // spglib standardise a lattice that is discarded on return, leaving
    // `result.lattice` reading back as the untouched input metric.
    const count = spglib.c.spgat_standardize_cell(
        result.latticePtr(),
        result.positionPtr(),
        result.mutableTypePtr(),
        @intCast(input.atomCount()),
        1, // to_primitive
        0, // no_idealize
        1e-1,
        -1.0, // angle tolerance: the spglib default sentinel
    );
    try testing.expectEqual(@as(c_int, 1), count);

    // The expected metric is read from the input cell and from upstream's own
    // centring matrix, not from a constant and not from the call under test.
    //
    // `no_idealize = 1` sends this call to `get_standardized_cell`, which
    // builds the primitive from the *input* cell through
    // `spa_transform_to_primitive` (src/spglib.c:1990-1991). The idealising
    // path, which reads `dataset->std_lattice` instead
    // (src/spglib.c:1834-1865), is a different function and is not the one
    // exercised here. The conventional standardisation below is still the
    // right anchor, because `set_cubic` idealises the conventional cell to
    // the edge (a + b + c) / 3 of the standardised metric
    // (src/refinement.c:829-838) and that sum is invariant under the axis
    // permutation a cubic standardisation may apply: (3.97 + 4.03 + 4.0) / 3
    // is exactly 4.0 for this fixture.
    const conventional = try spglib.standardizeCell(testing.allocator, input, .{
        .to_primitive = false,
        .symprec = 1e-1,
    });
    defer conventional.deinit();

    // `I_mat` (src/spacegroup.c:350-352) is the conventional-to-primitive
    // matrix for body centring. Each of its columns is (+-1/2, +-1/2, -1/2) and
    // so has length sqrt(3)/2, which on a cubic conventional cell of edge A
    // makes every primitive vector sqrt(3)/2 * A.
    //
    // The bound is 1e-3 rather than machine precision because the two paths
    // start from different metrics: this one keeps the input's 3.97, 4.03 and
    // 4.0, and a body-centred combination of those three is
    // sqrt(a^2 + b^2 + c^2) / 2 = 3.4641666 against the idealised
    // sqrt(3)/2 * 4 = 3.4641016, a relative difference of 1.9e-5. 1e-3 keeps
    // two orders of magnitude of margin and still cannot pass a wrong
    // centring: an F-centred combination would be 2% long, an unreduced cell
    // 15% long.
    const cell = result.asCell();
    const conventional_cell = conventional.asCell();
    const reference = @sqrt(3.0) / 2.0 * conventional_cell.length(0);
    for (0..3) |axis| {
        try testing.expectApproxEqRel(reference, cell.length(axis), 1e-3);
    }
    // Body centring halves the cell: the primitive holds one of the two
    // conventional atoms. The input volume is the second anchor, and the same
    // input-versus-idealised difference bounds both.
    try testing.expectApproxEqRel(conventional_cell.volume() / 2.0, cell.volume(), 1e-3);
    try testing.expectApproxEqRel(input.volume() / 2.0, cell.volume(), 1e-3);
}

test "the point group transformation matrix is built from upstream's axes" {
    nativeReady();

    const dataset = try spglib.getDataset(fixtures.perovskite, 1e-5);
    defer dataset.deinit();
    const point_group = try spglib.getPointGroup(dataset.operations().rotations);

    // `trans_mat` is not an arbitrary 3x3 matrix and "every entry is small" is
    // not a property of it. `set_transformation_matrix` (src/pointgroup.c)
    // writes `tmat[i][j] = s[j] * rot_axes[axes[j] % NUM_ROT_AXES][i]`, where
    // `s[j]` is +1 or -1 depending on whether that axis is a proper or an
    // improper rotation. So **every column of the answer is some row of
    // upstream's `rot_axes` table, up to an overall sign**, and nothing else
    // can come back.
    //
    // The table below is a second copy of that 73-row array, read out of
    // `src/pointgroup.c` rather than from the library, so the check compares
    // two independent statements of the same rule. A matrix assembled from
    // arbitrary small integers - which is what a range test would accept -
    // fails it.
    const rot_axes = [_][3]c_int{
        .{ 1, 0, 0 },   .{ 0, 1, 0 },   .{ 0, 0, 1 },   .{ 0, 1, 1 },   .{ 1, 0, 1 },
        .{ 1, 1, 0 },   .{ 0, 1, -1 },  .{ -1, 0, 1 },  .{ 1, -1, 0 },  .{ 1, 1, 1 },
        .{ -1, 1, 1 },  .{ 1, -1, 1 },  .{ 1, 1, -1 },  .{ 0, 1, 2 },   .{ 2, 0, 1 },
        .{ 1, 2, 0 },   .{ 0, 2, 1 },   .{ 1, 0, 2 },   .{ 2, 1, 0 },   .{ 0, -1, 2 },
        .{ 2, 0, -1 },  .{ -1, 2, 0 },  .{ 0, -2, 1 },  .{ 1, 0, -2 },  .{ -2, 1, 0 },
        .{ 2, 1, 1 },   .{ 1, 2, 1 },   .{ 1, 1, 2 },   .{ 2, -1, -1 }, .{ -1, 2, -1 },
        .{ -1, -1, 2 }, .{ 2, 1, -1 },  .{ -1, 2, 1 },  .{ 1, -1, 2 },  .{ 2, -1, 1 },
        .{ 1, 2, -1 },  .{ -1, 1, 2 },  .{ 3, 1, 2 },   .{ 2, 3, 1 },   .{ 1, 2, 3 },
        .{ 3, 2, 1 },   .{ 1, 3, 2 },   .{ 2, 1, 3 },   .{ 3, -1, 2 },  .{ 2, 3, -1 },
        .{ -1, 2, 3 },  .{ 3, -2, 1 },  .{ 1, 3, -2 },  .{ -2, 1, 3 },  .{ 3, -1, -2 },
        .{ -2, 3, -1 }, .{ -1, -2, 3 }, .{ 3, -2, -1 }, .{ -1, 3, -2 }, .{ -2, -1, 3 },
        .{ 3, 1, -2 },  .{ -2, 3, 1 },  .{ 1, -2, 3 },  .{ 3, 2, -1 },  .{ -1, 3, 2 },
        .{ 2, -1, 3 },  .{ 1, 1, 3 },   .{ -1, 1, 3 },  .{ 1, -1, 3 },  .{ -1, -1, 3 },
        .{ 1, 3, 1 },   .{ -1, 3, 1 },  .{ 1, 3, -1 },  .{ -1, 3, -1 }, .{ 3, 1, 1 },
        .{ 3, 1, -1 },  .{ 3, -1, 1 },  .{ 3, -1, -1 },
    };
    for (0..3) |column| {
        const axis: [3]c_int = .{
            point_group.trans_mat[0][column],
            point_group.trans_mat[1][column],
            point_group.trans_mat[2][column],
        };
        const negated: [3]c_int = .{ -axis[0], -axis[1], -axis[2] };
        const found = for (rot_axes) |row| {
            if (std.meta.eql(row, axis) or std.meta.eql(row, negated)) break true;
        } else false;
        if (!found) {
            std.debug.print(
                "trans_mat column {d} is {any}, which is not a row of rot_axes " ++
                    "up to sign\n",
                .{ column, axis },
            );
            return error.TestUnexpectedResult;
        }
    }
}
