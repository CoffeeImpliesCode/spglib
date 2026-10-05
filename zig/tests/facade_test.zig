// Behaviour tests for the spglib Zig facade.
//
// Every expected value here is an independent known answer: a space-group
// number and operation count fixed by the International Tables, an upstream
// fixture from test/functional/c, or a structural invariant such as "every
// operation maps atoms onto atoms of the same type".
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
const Cell = spglib.Cell;
const Operations = spglib.Operations;

test "the recorded status names the failure and its own message table" {
    nativeReady();

    // spg_get_error_message stops at the SPGERR_NONE sentinel before it
    // compares its argument, so `.none` has no message pointer at all
    // (`src/spglib.c:214-228` breaks on the `{SPGERR_NONE, ""}` row at index 9
    // first). An unrecognised recorded code is reported as `.none` rather than
    // as success, so a failure without a code is never silently dropped.
    try testing.expect(spglib.errorMessage(.none) == null);
    try testing.expectEqual(error.None, spglib.toError(.none));

    // Two different codes must not come back with the same text. `spg_free_*`
    // aside, the table at `src/spglib.c` holds one distinct string per code, so
    // a lookup that returned a constant, or that indexed the table wrongly,
    // would collapse them.
    const atoms = spglib.errorMessage(.atomsTooClose);
    const search = spglib.errorMessage(.spacegroupSearchFailed);
    try testing.expect(atoms != null);
    try testing.expect(search != null);
    if (std.mem.eql(u8, atoms.?, search.?)) {
        std.debug.print(
            "atomsTooClose and spacegroupSearchFailed report the same text: {s}\n",
            .{atoms.?},
        );
        return error.TestUnexpectedResult;
    }
}

test "ideal cubic perovskite is Pm-3m with the full octahedral group" {
    nativeReady();

    const symprec = 1e-5;
    const dataset = try spglib.getDataset(fixtures.perovskite, symprec);
    defer dataset.deinit();

    try testing.expectEqual(@as(c_int, 221), dataset.spacegroupNumber());
    try testing.expectEqualStrings("Pm-3m", dataset.internationalSymbol());
    try testing.expectEqualStrings("m-3m", dataset.pointgroupSymbol());
    try testing.expectEqual(@as(usize, 5), dataset.atomCount());
    try testing.expectEqual(@as(usize, 48), dataset.operationCount());

    const operations = dataset.operations();
    try expectActsOnCell(fixtures.perovskite, operations, symprec);
    // m-3m is exactly the 48 signed permutation matrices; nothing else.
    try expectSignedPermutationGroup(operations.rotations);
}

test "rock salt is Fm-3m and reaches the database maximum of 192 operations" {
    nativeReady();

    const symprec = 1e-5;
    const dataset = try spglib.getDataset(fixtures.rocksalt, symprec);
    defer dataset.deinit();

    try testing.expectEqual(@as(c_int, 225), dataset.spacegroupNumber());
    try testing.expectEqualStrings("Fm-3m", dataset.internationalSymbol());
    try testing.expectEqual(@as(usize, 192), dataset.operationCount());
    try expectActsOnCell(fixtures.rocksalt, dataset.operations(), symprec);

    // Eight conventional atoms map onto two primitive atoms, one per species.
    const mapping = dataset.mappingToPrimitive();
    try testing.expectEqual(@as(usize, 8), mapping.len);
    var seen: [2]bool = .{ false, false };
    for (mapping) |index| {
        try testing.expect(index >= 0 and index < 2);
        seen[@intCast(index)] = true;
    }
    try testing.expect(seen[0] and seen[1]);
}

test "rutile is P4_2/mnm with 16 operations and two symmetry classes" {
    nativeReady();

    const symprec = 1e-5;
    const dataset = try spglib.getDataset(fixtures.rutile, symprec);
    defer dataset.deinit();

    try testing.expectEqual(@as(c_int, 136), dataset.spacegroupNumber());
    try testing.expectEqualStrings("P4_2/mnm", dataset.internationalSymbol());
    try testing.expectEqual(@as(usize, 16), dataset.operationCount());
    try testing.expectEqual(@as(usize, 6), dataset.atomCount());
    try expectActsOnCell(fixtures.rutile, dataset.operations(), symprec);

    // Upstream pins every field of this type for Hall number 419 in
    // test/functional/fortran/test_fortran_spg_get_spacegroup_type.F90:40-69.
    const sgtype = try spglib.getSpacegroupType(dataset.hallNumber());
    try testing.expectEqual(@as(c_int, 136), sgtype.number);
    // Hall 419 is the only P4_2/mnm setting in the database, so the search must
    // land on it.
    try testing.expectEqual(@as(c_int, 419), dataset.hallNumber());
    try testing.expectEqualStrings("P4_2/mnm", sgtype.internationalShort());
    try testing.expectEqualStrings("P 4_2/m n m", sgtype.international());

    // The two titanium sites are equivalent to each other, the four oxygen
    // sites to each other, and the two classes differ.
    const equivalents = dataset.equivalentAtoms();
    try testing.expectEqual(@as(usize, 6), equivalents.len);
    try testing.expectEqual(equivalents[0], equivalents[1]);
    try testing.expectEqual(equivalents[2], equivalents[3]);
    try testing.expectEqual(equivalents[2], equivalents[4]);
    try testing.expect(equivalents[0] != equivalents[2]);
}

test "body centred iron is Im-3m with Hall number 529 and 96 operations" {
    nativeReady();

    const symprec = 1e-5;
    const dataset = try spglib.getDataset(fixtures.bcc, symprec);
    defer dataset.deinit();

    try testing.expectEqual(@as(c_int, 229), dataset.spacegroupNumber());
    try testing.expectEqual(@as(c_int, 529), dataset.hallNumber());
    try testing.expectEqual(@as(usize, 96), dataset.operationCount());

    // Hall number 529 is Im-3m, the last body-centred entry of the database
    // (src/spg_database.c:1070).
    const sgtype = try spglib.getSpacegroupType(dataset.hallNumber());
    try testing.expectEqual(@as(c_int, 229), sgtype.number);
    try testing.expectEqualStrings("Im-3m", sgtype.internationalShort());
    try testing.expectEqualStrings("Oh^9", sgtype.schoenflies());
    try testing.expectEqualStrings("Oh", sgtype.pointgroupSchoenflies());
    try testing.expectEqualStrings("m-3m", sgtype.pointgroupInternational());

    // The database entry for the same Hall number must list the same group.
    const database = try spglib.getSymmetryFromDatabase(testing.allocator, dataset.hallNumber());
    defer database.deinit();
    try testing.expectEqual(dataset.operationCount(), database.count());
}

test "a Hall number of zero selects the same group as the default search" {
    nativeReady();

    const dataset = try spglib.getDataset(fixtures.rutile, 1e-5);
    defer dataset.deinit();
    const pinned = try spglib.getDatasetWithHallNumber(fixtures.rutile, 0, 1e-5);
    defer pinned.deinit();
    try testing.expectEqual(dataset.spacegroupNumber(), pinned.spacegroupNumber());
    try testing.expectEqual(dataset.hallNumber(), pinned.hallNumber());

    // Asking for that Hall number explicitly reproduces the same group.
    const explicit = try spglib.getDatasetWithHallNumber(fixtures.rutile, dataset.hallNumber(), 1e-5);
    defer explicit.deinit();
    try testing.expectEqual(dataset.hallNumber(), explicit.hallNumber());
    try testing.expectEqual(dataset.operationCount(), explicit.operationCount());
}

test "the angle-tolerance entry point agrees with the default search" {
    nativeReady();

    const dataset = try spglib.getDataset(fixtures.perovskite, 1e-5);
    defer dataset.deinit();
    const with_tolerance = try spglib.getDatasetWithAngleTolerance(fixtures.perovskite, 1e-5, -1.0);
    defer with_tolerance.deinit();
    try testing.expectEqual(dataset.hallNumber(), with_tolerance.hallNumber());
    try testing.expectEqual(dataset.operationCount(), with_tolerance.operationCount());
}

test "symprec decides whether a tetragonal distortion is seen" {
    nativeReady();

    // The c axis is 0.005 A short of a: far above a 1e-5 tolerance, far below
    // a 1e-2 one.
    const ideal = try spglib.getDataset(fixtures.perovskite, 1e-5);
    defer ideal.deinit();

    const tight = try spglib.getDataset(fixtures.distorted_perovskite, 1e-5);
    defer tight.deinit();
    try testing.expectEqual(@as(c_int, 123), tight.spacegroupNumber());
    try testing.expectEqualStrings("P4/mmm", tight.internationalSymbol());
    try testing.expectEqual(@as(usize, 16), tight.operationCount());

    const loose = try spglib.getDataset(fixtures.distorted_perovskite, 1e-2);
    defer loose.deinit();
    try testing.expectEqual(@as(c_int, 221), loose.spacegroupNumber());
    try testing.expectEqualStrings("Pm-3m", loose.internationalSymbol());
    try testing.expectEqual(ideal.operationCount(), loose.operationCount());
}

test "symprec decides whether a distorted bcc cell standardises to bcc" {
    nativeReady();

    // Upstream uses symprec 1e-1 for this cell (test_standardization.cpp:9-14).
    // The primitive vectors are the columns of `I_mat`, the
    // conventional-to-primitive matrix for body centring
    // (src/spacegroup.c:350-352); each column is (+-1/2, +-1/2, -1/2) and so
    // has length sqrt(3)/2. On a cubic conventional cell of edge A that makes
    // every primitive vector sqrt(3)/2 * A. The edge is read back from the same
    // library, because `standardize_primitive` derives the primitive cell from
    // `dataset->std_lattice` (src/spglib.c:1845-1865).
    const conventional = try spglib.standardizeCell(testing.allocator, fixtures.distorted_bcc, .{
        .to_primitive = false,
        .symprec = 1e-1,
    });
    defer conventional.deinit();
    const reference = @sqrt(3.0) / 2.0 * conventional.asCell().length(0);

    const loose = try spglib.standardizeCell(testing.allocator, fixtures.distorted_bcc, .{
        .to_primitive = true,
        .symprec = 1e-1,
    });
    defer loose.deinit();
    try testing.expectEqual(@as(usize, 1), loose.atomCount());
    try testing.expect(lengthDeviation(loose, reference) < 1e-6);

    const tight = try spglib.standardizeCell(testing.allocator, fixtures.distorted_bcc, .{
        .to_primitive = true,
        .symprec = 1e-5,
    });
    defer tight.deinit();
    // At a tight tolerance the distortion is real, so the cell keeps its
    // near-cubic vectors instead of the bcc ones.
    try testing.expect(lengthDeviation(tight, reference) > 1e-2);
}

test "primitive and conventional standardisation keep the cell volume" {
    nativeReady();

    const primitive = try spglib.findPrimitive(testing.allocator, fixtures.bcc, 1e-5);
    defer primitive.deinit();
    try testing.expectEqual(@as(usize, 1), primitive.atomCount());
    // The conventional cell holds two atoms, so its primitive cell has half
    // the volume.
    try testing.expectApproxEqRel(fixtures.bcc.volume(), 2.0 * primitive.asCell().volume(), 1e-6);

    const conventional = try spglib.standardizeCell(testing.allocator, fixtures.bcc, .{
        .to_primitive = false,
        .symprec = 1e-5,
    });
    defer conventional.deinit();
    try testing.expectEqual(@as(usize, 2), conventional.atomCount());
    try testing.expectApproxEqRel(fixtures.bcc.volume(), conventional.asCell().volume(), 1e-6);
}

test "refineCell recovers the conventional Bravais lattice" {
    nativeReady();

    // The fcc primitive cell of a = 4 holds one atom; its conventional cell
    // holds four and has four times the volume.
    var refined = try spglib.refineCell(
        testing.allocator,
        fixtures.fcc_primitive,
        1e-5,
    );
    defer refined.deinit();
    try testing.expectEqual(@as(usize, 4), refined.atomCount());
    try testing.expectApproxEqRel(4.0 * fixtures.fcc_primitive.volume(), refined.asCell().volume(), 1e-6);
    try testing.expectApproxEqAbs(4.0, refined.lattice[0][0], 1e-6);
    try testing.expectApproxEqAbs(0.0, refined.lattice[0][1], 1e-6);
}

test "a one-atom cell resolves and the result is a real rotation group" {
    nativeReady();

    // `fcc_primitive` carries a single atom, so its atom count is odd. That
    // makes it the cell that exercises the odd-size path through
    // `ovl_overlap_checker_alloc`, whose blob offsets depend on `size`
    // (src/overlap.c:464-471), and through the site's equivalent-atom
    // bookkeeping. The answers below are the group's own, not a repeat of the
    // call.
    //
    // The group is Fm-3m, not the R setting of the same crystal class, for
    // two reasons read out of the source. The Bravais lattice is fcc:
    // upstream drives this very cell through `spg_refine_cell` and gets a
    // four-atom conventional cell (test/functional/c/test_refine_cell.cpp:9-27),
    // which is the F-centred conventional cell, so the database lookup runs
    // over the FACE rows only. And the table holds exactly one row for space
    // group 225: src/spg_database.c:1058-1059, `{225, "Oh^5  ", "-F 4 2 3",
    // "F 4/m -3 2/m", "Fm-3m", "", FACE, 32}`, which upstream's own trailing
    // comment labels row 523, and `spg_get_spacegroup_type` indexes that same
    // table, so the Hall number is 523. Its symbol is "Fm-3m" and its
    // point-group number is 32, the m-3m row of `pointgroup_data`
    // (src/pointgroup.c:282-289).
    const dataset = try spglib.getDataset(fixtures.fcc_primitive, 1e-5);
    defer dataset.deinit();

    try testing.expectEqual(@as(c_int, 225), dataset.spacegroupNumber());
    try testing.expectEqual(@as(c_int, 523), dataset.hallNumber());
    try testing.expectEqualStrings("Fm-3m", dataset.internationalSymbol());
    try testing.expectEqualStrings("-F 4 2 3", dataset.hallSymbol());
    try testing.expectEqualStrings("m-3m", dataset.pointgroupSymbol());
    try testing.expectEqual(@as(usize, 1), dataset.atomCount());
    // The operation count is in the basis of the cell that was passed in, and
    // this cell is the primitive fcc one, where the four F-centring
    // translations are already lattice translations of the basis. What is left
    // is the 48 rotations of m-3m, all of which are automorphisms of that
    // basis. The space group's own 192 is the same group in the conventional
    // basis, 48 rotations times 4 centring vectors.
    try testing.expectEqual(@as(usize, 48), dataset.operationCount());

    // On one site: every operation must map the single atom onto itself, and
    // the 48 operations must be 48 distinct rotations, since in this basis no
    // two of them differ only by a centring translation.
    const operations = dataset.operations();
    try expectActsOnCell(fixtures.fcc_primitive, operations, 1e-5);
    var distinct: usize = 0;
    for (operations.rotations) |rotation| {
        if (!containsRotation(operations.rotations[0..distinct], rotation)) distinct += 1;
    }
    try testing.expectEqual(@as(usize, 48), distinct);

    const equivalents = dataset.equivalentAtoms();
    try testing.expectEqual(@as(usize, 1), equivalents.len);
    try testing.expectEqual(@as(c_int, 0), equivalents[0]);
}

test "corundum is an oblique R-centred cell that reduces to ten atoms" {
    nativeReady();

    // The hexagonal Al2O3 cell of upstream test_standardization.cpp:29-64.
    // Its columns are a = b = 4.8076344022756095 with gamma = 120 and
    // c = 13.1172699198127543. Read as rows instead, a would be 5.378 and b
    // 4.164, so these lengths pin the basis orientation the C API uses.
    try testing.expectApproxEqAbs(4.8076344022756095, fixtures.corundum.length(0), 1e-12);
    try testing.expectApproxEqAbs(4.8076344022756095, fixtures.corundum.length(1), 1e-12);
    try testing.expectApproxEqAbs(13.1172699198127543, fixtures.corundum.length(2), 1e-12);
    try testing.expectApproxEqAbs(120.0, fixtures.corundum.angle(0, 1) * 180.0 / std.math.pi, 1e-9);

    // The second atom sits at (2/3, 1/3, z), which in the hexagonal net is
    // (2a + b) / 3.
    const site = fixtures.corundum.toCartesian(1);
    try testing.expectApproxEqAbs(2.4038172011378047, site[0], 1e-9);
    try testing.expectApproxEqAbs(1.3878445081595654, site[1], 1e-9);

    const dataset = try spglib.getDataset(fixtures.corundum, 1e-5);
    defer dataset.deinit();
    try testing.expectEqual(@as(c_int, 167), dataset.spacegroupNumber());
    try testing.expectEqualStrings("R-3c", dataset.internationalSymbol());
    try testing.expectEqual(@as(usize, 30), dataset.atomCount());
    try expectActsOnCell(fixtures.corundum, dataset.operations(), 1e-5);

    // R centring divides the 30-atom hexagonal cell into three; upstream pins
    // the same 10 at test_find_primitive_cell.cpp:74.
    const primitive = try spglib.findPrimitive(testing.allocator, fixtures.corundum, 1e-5);
    defer primitive.deinit();
    try testing.expectEqual(@as(usize, 10), primitive.atomCount());
    try testing.expectApproxEqRel(fixtures.corundum.volume(), 3.0 * primitive.asCell().volume(), 1e-6);
}

test "niggli reduction keeps the cell volume" {
    nativeReady();

    var lattice: [3][3]f64 = .{
        .{ 3.0, 0.0, 0.0 },
        .{ 2.5, 1.5, 0.0 },
        .{ 2.6, 1.4, 1.2 },
    };
    const before = @abs(fixtures.determinant(lattice));
    try spglib.niggliReduce(&lattice, 1e-5);
    try testing.expectApproxEqRel(before, @abs(fixtures.determinant(lattice)), 1e-9);
}

test "the symmetry search refuses to truncate into a smaller buffer" {
    nativeReady();

    const rutile = try spglib.getSymmetry(testing.allocator, fixtures.rutile, 1e-5, 16);
    defer rutile.deinit();
    try testing.expectEqual(@as(usize, 16), rutile.count());

    try testing.expectError(
        error.ArraySizeShortage,
        spglib.getSymmetry(testing.allocator, fixtures.rutile, 1e-5, 8),
    );
    try testing.expectEqual(spglib.ErrorCode.arraySizeShortage, spglib.lastErrorCode());
    try testing.expectError(
        error.OperationCountOutOfRange,
        spglib.getSymmetry(testing.allocator, fixtures.rutile, 1e-5, 0),
    );
}

test "a bounded symmetry search returns the same group as the dataset" {
    nativeReady();

    const dataset = try spglib.getDataset(fixtures.rutile, 1e-5);
    defer dataset.deinit();
    const symmetry = try spglib.getSymmetry(testing.allocator, fixtures.rutile, 1e-5, 64);
    defer symmetry.deinit();

    try testing.expectEqual(dataset.operationCount(), symmetry.count());
    for (dataset.operations().rotations, symmetry.rotations) |from_dataset, from_search| {
        try testing.expectEqualDeep(from_dataset, from_search);
    }
    try expectActsOnCell(fixtures.rutile, symmetry.operations(), 1e-5);
}

test "the point group of the perovskite rotations is m-3m" {
    nativeReady();

    const dataset = try spglib.getDataset(fixtures.perovskite, 1e-5);
    defer dataset.deinit();
    const point_group = try spglib.getPointGroup(dataset.operations().rotations);
    try testing.expectEqualStrings("m-3m", point_group.symbol());
    // `spg_get_pointgroup` returns the point-group number, which is a row of
    // `pointgroup_data` (src/pointgroup.c:26-289): 32 is the m-3m row
    // (src/pointgroup.c:282-289). It is not a count of rotations, so it says
    // nothing about the dataset's 48 operations; the distinct-rotation count
    // below is what pins those.
    try testing.expectEqual(@as(c_int, 32), point_group.number);
    var distinct: usize = 0;
    for (dataset.operations().rotations) |rotation| {
        if (!containsRotation(dataset.operations().rotations[0..distinct], rotation)) distinct += 1;
    }
    try testing.expectEqual(@as(usize, 48), distinct);

    const rutile_dataset = try spglib.getDataset(fixtures.rutile, 1e-5);
    defer rutile_dataset.deinit();
    const rutile_group = try spglib.getPointGroup(rutile_dataset.operations().rotations);
    try testing.expectEqualStrings("4/mmm", rutile_group.symbol());
    // 4/mmm is row 15 of the same table (src/pointgroup.c:146-153), which is
    // also the pointgroup_number the database records for Hall 419, P4_2/mnm
    // (src/spg_database.c:851).
    try testing.expectEqual(@as(c_int, 15), rutile_group.number);
}

test "the point group search rejects an empty operation list" {
    nativeReady();

    try testing.expectError(error.OperationCountOutOfRange, spglib.getPointGroup(&.{}));
}

test "coincident atoms are rejected as too close" {
    nativeReady();

    try testing.expectError(
        error.AtomsTooClose,
        spglib.getDataset(fixtures.coincident_atoms, 1e-5),
    );
    try testing.expectEqual(spglib.ErrorCode.atomsTooClose, spglib.lastErrorCode());
    // The recorded status is per-thread and every successful entry point
    // overwrites it with SPGLIB_SUCCESS, so it has to be read here rather than
    // after the next call. That ordering is the property, not whether a message
    // happens to exist for the code.
    try testing.expectEqual(error.AtomsTooClose, spglib.lastError());
}

test "any successful call clears the status a failure recorded" {
    nativeReady();

    if (spglib.getDataset(fixtures.coincident_atoms, 1e-5)) |dataset| {
        dataset.deinit();
        return error.TestUnexpectedResult;
    } else |_| {}
    try testing.expect(spglib.lastErrorCode() == .atomsTooClose);

    // getVersion is one of the entry points that overwrites the status with
    // SPGLIB_SUCCESS, which is why the code above has to be read first.
    _ = spglib.getVersion();
    try testing.expectEqual(spglib.ErrorCode.success, spglib.lastErrorCode());
}

test "repeated dataset failures leak nothing on the Zig side" {
    nativeReady();

    // testing.allocator fails the test if an allocation made here is never
    // released. spglib allocates its dataset before failing and frees that
    // itself, so repeated failures must not accumulate memory either.
    var attempts: usize = 0;
    while (attempts < 64) : (attempts += 1) {
        try testing.expectError(
            error.AtomsTooClose,
            spglib.getDataset(fixtures.coincident_atoms, 1e-5),
        );
    }
    try testing.expectEqual(spglib.ErrorCode.atomsTooClose, spglib.lastErrorCode());
}

test "a cell with no volume fails with a real spglib status" {
    nativeReady();

    if (spglib.getDataset(fixtures.degenerate, 1e-5)) |dataset| {
        dataset.deinit();
        return error.TestUnexpectedResult;
    } else |failure| {
        // The error the call returned must be the one the library recorded,
        // which is what makes `lastErrorCode` a diagnostic behind a real answer
        // rather than a second channel that can disagree with it. A degenerate
        // lattice has no space group, so some upstream failure is expected;
        // *which* one is upstream's business and is deliberately not pinned
        // here, because it is not a property of this wrapper.
        try testing.expectEqual(failure, spglib.toError(spglib.lastErrorCode()));
        try testing.expect(failure != error.None);
    }
}

test "input mistakes are caught before the C call" {
    nativeReady();

    try testing.expectError(
        error.AtomCountMismatch,
        spglib.getDataset(fixtures.mismatched_atoms, 1e-5),
    );
    try testing.expectError(
        error.NonPositiveSymprec,
        spglib.getDataset(fixtures.perovskite, 0.0),
    );
    // A `var`, because niggliReduce reduces in place and therefore takes a
    // mutable pointer even on the path that rejects the tolerance.
    var identity = [3][3]f64{
        .{ 1, 0, 0 },
        .{ 0, 1, 0 },
        .{ 0, 0, 1 },
    };
    try testing.expectError(
        error.NonPositiveSymprec,
        spglib.niggliReduce(&identity, -1.0),
    );
    const empty = Cell{
        .lattice = .{
            .{ 1, 0, 0 },
            .{ 0, 1, 0 },
            .{ 0, 0, 1 },
        },
        .positions = &.{},
        .types = &.{},
    };
    try testing.expectError(error.EmptyCell, spglib.getDataset(empty, 1e-5));
}

test "ferromagnetic, gray and antiferromagnetic rutile are three distinct types" {
    nativeReady();

    const cases = .{
        .{ .spins = &fixtures.rutile_spins.ferromagnetic, .magnetic_type = @as(c_int, 1), .uni = @as(c_int, 1155) },
        .{ .spins = &fixtures.rutile_spins.gray, .magnetic_type = @as(c_int, 2), .uni = @as(c_int, 1156) },
        .{ .spins = &fixtures.rutile_spins.antiferromagnetic, .magnetic_type = @as(c_int, 3), .uni = @as(c_int, 1158) },
    };
    inline for (cases) |case| {
        const dataset = try spglib.getMagneticDataset(fixtures.rutile, case.spins, 1e-5);
        defer dataset.deinit();
        try testing.expectEqual(case.magnetic_type, dataset.magneticType());
        try testing.expectEqual(case.uni, dataset.uniNumber());
        try testing.expectEqual(@as(usize, 6), dataset.atomCount());
        // include/spglib.h:160-163 types a magnetic dataset's `hall_number`
        // as the Hall number of the family space group for types I, II and
        // III, and of the maximal space group for type IV. It is not the
        // space-group number. Rutile's family space group is P4_2/mnm in its
        // only setting, Hall 419, and 136 is the space-group number that
        // Hall number maps to. Reading one for the other is the mistake this
        // line exists to prevent.
        try testing.expectEqual(@as(c_int, 419), dataset.hallNumber());
        try testing.expectEqual(
            @as(c_int, 136),
            (try spglib.getSpacegroupType(dataset.hallNumber())).number,
        );

        const operations = dataset.operations();
        const reversals = dataset.timeReversals();
        try testing.expectEqual(operations.count(), reversals.len);
        // 0 is ordinary and 1 carries time reversal; the array never holds -1.
        for (reversals) |flag| try testing.expect(flag == 0 or flag == 1);
    }
}

test "the gray magnetic group pairs every operation with a time-reversed twin" {
    nativeReady();

    const dataset = try spglib.getMagneticDataset(fixtures.rutile, &fixtures.rutile_spins.gray, 1e-5);
    defer dataset.deinit();

    const operations = dataset.operations();
    const reversals = dataset.timeReversals();
    var ordinary: usize = 0;
    var time_reversed: usize = 0;
    for (reversals) |flag| {
        if (flag == 0) ordinary += 1;
        if (flag == 1) time_reversed += 1;
    }
    // A gray group is type II: every operation appears with and without time
    // reversal, so the list is exactly twice as long as the space group and
    // the flags split evenly. `time_reversals` holds 0 and 1, so the two
    // halves are counted by those values rather than by sign.
    try testing.expectEqual(operations.count(), 2 * 16);
    try testing.expectEqual(ordinary, time_reversed);
    try testing.expectEqual(ordinary, 16);
}

test "antiferromagnetic bcc iron has an anti-translation with time reversal" {
    nativeReady();

    const dataset = try spglib.getMagneticDataset(fixtures.bcc_antiferromagnetic, &fixtures.bcc_spins, 1e-5);
    defer dataset.deinit();

    const operations = dataset.operations();
    const reversals = dataset.timeReversals();
    try testing.expectEqual(operations.count(), reversals.len);

    // The type-IV anti-translation maps the cell onto itself while flipping
    // time, so its translation is (1/2, 1/2, 1/2) modulo 1 and its flag is 1.
    var found = false;
    for (operations.translations, reversals) |translation, reversal| {
        if (reversal != 1) continue;
        if (allHalfComponents(translation)) found = true;
    }
    try testing.expect(found);
    try testing.expect(dataset.magneticType() >= 1 and dataset.magneticType() <= 4);
}

test "magnetic tensor counts and ranks are validated" {
    nativeReady();

    // One double per atom at rank 0: any other count is a caller mistake.
    // The spin array is bound first: a container-level array decl cannot be
    // sliced through the decl path directly.
    const gray = fixtures.rutile_spins.gray;
    try testing.expectError(
        error.TensorCountMismatch,
        spglib.getMagneticDataset(fixtures.rutile, gray[0..5], 1e-5),
    );
    // Three doubles per atom at rank 1.
    try testing.expectError(
        error.TensorCountMismatch,
        spglib.getMagneticDatasetWithTensors(fixtures.rutile, &([_]f64{0} ** (6 * 2)), .{
            .rank = 1,
            .symprec = 1e-5,
        }),
    );
    // SiteTensorType stops at NONCOLLINEAR, so a higher rank is refused before
    // any C call rather than reaching unallocated tensor storage.
    try testing.expectError(
        error.TensorRankOutOfRange,
        spglib.getMagneticDatasetWithTensors(fixtures.rutile, &([_]f64{0} ** (6 * 3)), .{
            .rank = 2,
            .symprec = 1e-5,
        }),
    );
    try testing.expectError(
        error.TensorRankOutOfRange,
        spglib.getMagneticDatasetWithTensors(fixtures.rutile, &([_]f64{0} ** (6 * 64)), .{
            .rank = 4,
            .symprec = 1e-5,
        }),
    );
}

test "a rank-1 search reports three tensor components per atom" {
    nativeReady();

    const tensors = [_]f64{0} ** (6 * 3);
    const dataset = try spglib.getMagneticDatasetWithTensors(fixtures.rutile, &tensors, .{
        .rank = 1,
        .symprec = 1e-5,
        .is_axial = true,
    });
    defer dataset.deinit();
    try testing.expectEqual(@as(c_int, 1), dataset.tensorRank());
    // Zero tensors make the structure gray again.
    try testing.expectEqual(@as(c_int, 2), dataset.magneticType());
    try testing.expectEqual(dataset.atomCount(), dataset.standardAtomCount());
    try testing.expectEqual(dataset.standardAtomCount() * 3, dataset.standardTensors().len);
}

test "a non-collinear site tensor keeps its three components per atom" {
    nativeReady();

    // Upstream test_magnetic_dataset.cpp:214-231: one atom, the axial tensor
    // (1, 0, 0), and 16 operations.
    const dataset = try spglib.getMagneticDatasetWithTensors(
        fixtures.non_collinear_cubic,
        &fixtures.non_collinear_spins,
        .{ .rank = 1, .symprec = 1e-5, .is_axial = true },
    );
    defer dataset.deinit();
    try testing.expectEqual(@as(c_int, 1), dataset.tensorRank());
    try testing.expectEqual(@as(usize, 16), dataset.operationCount());
    try testing.expectEqual(@as(usize, 3), dataset.standardTensors().len);
    try testing.expectEqual(
        dataset.operationCount(),
        dataset.timeReversals().len,
    );
}

test "magnetic space-group types are looked up by UNI number" {
    nativeReady();

    // database/msg/msg_numbers.csv records Litvin 1242, BNS 146.12,
    // OG 146.3.1242 at UNI 1242.
    const magnetic_type = try spglib.getMagneticSpacegroupType(1242);
    try testing.expectEqual(@as(c_int, 1242), magnetic_type.uniNumber);
    try testing.expectEqualStrings("146.12", magnetic_type.bnsNumber());
    try testing.expectEqualStrings("146.3.1242", magnetic_type.ogNumber());
    // The generator takes `number` from the BNS prefix, so 146.12 is 146.
    try testing.expectEqual(@as(c_int, 146), magnetic_type.number);
    try testing.expect(magnetic_type.magneticType >= 1 and magnetic_type.magneticType <= 4);
}

test "space-group type lookups reject a number the database does not carry" {
    nativeReady();

    try testing.expectError(error.HallNumberOutOfRange, spglib.getSpacegroupType(0));
    try testing.expectError(error.HallNumberOutOfRange, spglib.getSpacegroupType(531));
    try testing.expectError(
        error.UniNumberOutOfRange,
        spglib.getMagneticSpacegroupType(0),
    );
    try testing.expectError(
        error.UniNumberOutOfRange,
        spglib.getMagneticSpacegroupType(1652),
    );

    // Both ends of each range are real entries with answers this repository
    // can read out of the upstream data rather than from the library itself.
    // Hall 1 is the first row of src/spg_database.c and Hall 530 the last.
    const first = try spglib.getSpacegroupType(1);
    try testing.expectEqual(@as(c_int, 1), first.number);
    try testing.expectEqual(@as(c_int, 1), first.hallNumber);
    try testing.expectEqualStrings("P1", first.internationalShort());
    try testing.expectEqualStrings("P 1", first.international());
    try testing.expectEqualStrings("P 1", first.hallSymbol());

    const last = try spglib.getSpacegroupType(530);
    try testing.expectEqual(@as(c_int, 230), last.number);
    try testing.expectEqual(@as(c_int, 530), last.hallNumber);
    try testing.expectEqualStrings("Ia-3d", last.internationalShort());
    try testing.expectEqualStrings("I a -3 d", last.international());
    try testing.expectEqualStrings("-I 4bd 2c 3", last.hallSymbol());

    // database/msg/msg_numbers.csv lists the first row as Litvin 1, BNS 1.1,
    // OG 1.1.1 at UNI 1, and the last as Litvin 1651, BNS 230.149,
    // OG 230.5.1651 at UNI 1651.
    const first_uni = try spglib.getMagneticSpacegroupType(1);
    try testing.expectEqual(@as(c_int, 1), first_uni.litvinNumber);
    try testing.expectEqual(@as(c_int, 1), first_uni.number);
    try testing.expectEqualStrings("1.1", first_uni.bnsNumber());
    try testing.expectEqualStrings("1.1.1", first_uni.ogNumber());

    const last_uni = try spglib.getMagneticSpacegroupType(1651);
    try testing.expectEqual(@as(c_int, 1651), last_uni.litvinNumber);
    try testing.expectEqual(@as(c_int, 230), last_uni.number);
    try testing.expectEqualStrings("230.149", last_uni.bnsNumber());
    try testing.expectEqualStrings("230.5.1651", last_uni.ogNumber());
}

test "grid addresses fold onto mesh points and only unrepresentable ones are refused" {
    nativeReady();

    // The grid-point index is not a value this program can compare against a
    // constant taken from a table, because both the mesh and the address are
    // arguments. It is a formula instead, and the formula is upstream's own.
    // Tracing `spg_get_dense_grid_point_from_address`
    // (`src/spglib.c:893-904`) for address {2,1,0} in mesh {4,4,4}:
    //
    //   * `kgd_get_grid_address_double_mesh` (`src/kgrid.c:38-42`) doubles each
    //     component and adds the shift, which is zero here, giving {4,2,0};
    //   * `reduce_grid_address_double` (`src/kgrid.c:120-129`) subtracts
    //     `2 * mesh[i]` only where the component *exceeds* `mesh[i]`, so 4 is
    //     not greater than 4 and nothing is subtracted: {4,2,0} stays;
    //   * `get_grid_point_double_mesh` (`src/kgrid.c:68-83`) halves each
    //     component, giving {2,1,0}, and `modulo_i3` (:96-106) leaves it alone;
    //   * `get_grid_point_single_mesh` (`src/kgrid.c:88-89`) returns
    //     `address[2] * mesh[0] * mesh[1] + address[1] * mesh[0] + address[0]`,
    //     which is 0 * 16 + 1 * 4 + 2 = 6.
    //
    // That is an independent derivation, not a re-read of what the call
    // returned, which is what makes it a check rather than an echo.
    const mesh: [3]c_int = .{ 4, 4, 4 };
    const address: [3]c_int = .{ 2, 1, 0 };
    try testing.expectEqual(
        @as(usize, 6),
        try spglib.gridPointFromAddress(address, mesh),
    );

    // A negative address, where `modulo_i3` is the step that decides the
    // answer. Address {-1,0,0} doubles to {-2,0,0}; nothing exceeds the mesh, so
    // the reduction does nothing; halving gives {-1,0,0}; and C's truncating
    // remainder leaves -1 % 4 as -1, which `modulo_i3` then lifts to 3. The
    // index is therefore 3. Skipping `modulo_i3` would answer -1, and reducing
    // a component that merely *equals* the mesh would answer 62, so this one
    // case separates two different mistakes.
    try testing.expectEqual(
        @as(usize, 3),
        try spglib.gridPointFromAddress(.{ -1, 0, 0 }, mesh),
    );

    // A component above the mesh, where the reduction is what decides the
    // answer. Address {3,0,0} doubles to {6,0,0}; 6 exceeds 4, so
    // `reduce_grid_address_double` subtracts 2 * 4 and produces {-2,0,0}. The
    // rest of the trace then matches the case above and the index is 3 again.
    // The pair is deliberate: {2,1,0} and {3,0,0} are both in range and reach
    // the same index, while only the second one crosses `mesh[i]`, so a
    // reduction that used `>=` instead of `>` would answer 62 for {2,1,0} and
    // disagree here.
    try testing.expectEqual(
        @as(usize, 3),
        try spglib.gridPointFromAddress(.{ 3, 0, 0 }, mesh),
    );

    // Further out of the mesh again, and the point of the case: upstream folds
    // an address the mesh does not bound rather than refusing it. {5,0,0}
    // doubles to {10,0,0}; 10 exceeds 4, so the reduction subtracts 8 once and
    // leaves {2,0,0}; halving gives {1,0,0}; 1 % 4 is 1; the index is 1. An
    // address that named no mesh point would have no answer to compare with, so
    // this is the behaviour a caller folding reduced-zone addresses relies on.
    try testing.expectEqual(
        @as(usize, 1),
        try spglib.gridPointFromAddress(.{ 5, 0, 0 }, mesh),
    );

    // The two refusals left, both because the arithmetic upstream performs is
    // `int` in C. A zero mesh entry is a division by zero in `modulo_i3`
    // (src/kgrid.c:100), and an entry above 2^30 - 1 cannot be doubled by
    // `reduce_grid_address_double` (src/kgrid.c:125) without overflowing.
    try testing.expectError(error.MeshOutOfRange, spglib.gridPointFromAddress(address, .{ 4, 0, 4 }));
    try testing.expectError(
        error.MeshOutOfRange,
        spglib.gridPointFromAddress(address, .{ 4, 1073741824, 4 }),
    );

    // The same ceiling on the address side: 2^30 doubled is 2^31, which the
    // `int` of `address[i] * 2` (src/kgrid.c:39) cannot hold.
    try testing.expectError(
        error.GridAddressOutOfRange,
        spglib.gridPointFromAddress(.{ 1073741824, 0, 0 }, mesh),
    );
}

test "the dataset reports the standardised perovskite cell" {
    nativeReady();

    const dataset = try spglib.getDataset(fixtures.perovskite, 1e-5);
    defer dataset.deinit();

    const standard = dataset.standardLattice();
    try testing.expectApproxEqAbs(3.905, standard[0][0], 1e-3);
    try testing.expectApproxEqAbs(3.905, standard[2][2], 1e-3);
    try testing.expectApproxEqRel(fixtures.perovskite.volume(), cellFrom(dataset.primitiveLattice()).volume(), 1e-6);

    const atoms = dataset.atomCount();
    try testing.expectEqual(atoms, dataset.standardAtomCount());
    try testing.expectEqual(atoms, dataset.standardTypes().len);
    try testing.expectEqual(atoms, dataset.standardPositions().len);
    try testing.expectEqual(atoms, dataset.wyckoffs().len);
    try testing.expectEqual(atoms, dataset.siteSymmetrySymbols().len);
    try testing.expectEqual(atoms, dataset.crystallographicOrbits().len);
    try testing.expectEqual(atoms, dataset.standardMappingToPrimitive().len);
    try testing.expectEqual(atoms, dataset.mappingToPrimitive().len);

    // Three crystallographic orbits: Sr on 1a, Ti on 1b and the three oxygen
    // sites on 3c. Sr and Ti are separate orbits because the cell is
    // primitive, so no operation carries one onto the other: every operation
    // of Pm-3m fixes the origin and fixes (1/2,1/2,1/2) separately. The field
    // holds the index of the first member of each class of the primitive cell,
    // pulled back to the input cell (`set_crystallographic_orbits`,
    // src/refinement.c:887-917), and its contract is "symmetrically equivalent
    // under the space group type" (python/spglib/spg.py:120-128).
    const orbits = dataset.crystallographicOrbits();
    try testing.expectEqual(@as(usize, 3), fixtures.distinctCount(orbits));
    try testing.expect(orbits[0] != orbits[1]);
    try testing.expect(orbits[0] != orbits[2]);
    try testing.expectEqual(orbits[2], orbits[3]);
    try testing.expectEqual(orbits[2], orbits[4]);
}

test "a dataset is released by the provider that produced it" {
    nativeReady();

    // `spg_get_dataset` allocates with the provider's own `malloc`
    // (`src/spglib.c:234`) and `spg_free_dataset` releases with that same
    // provider's `free` (`src/spglib.c:293-333`). There is no allocator
    // argument and no hook anywhere in the header, so the pairing is
    // unconditional and the only thing that can break it is routing one of the
    // two to something else. In a runtime-loading build both calls go through
    // one table that `load` filled once and never replaces, so a dataset
    // cannot end up being freed by a different library.
    //
    // A wrong free does not fail loudly here: it corrupts a heap the caller
    // does not own, and the damage shows up later as a wrong answer. So this
    // runs the round trip many times over and re-checks a fixed known answer
    // after every single one. A free routed to the wrong entry point, or to a
    // Zig allocator, cannot survive that; a correct one can, because each
    // iteration fully releases what the previous one allocated.
    //
    // The magnetic dataset is included because it is a different struct with a
    // different release function (`spg_free_magnetic_dataset`,
    // `src/spglib.c:335-365`), so the two routes cannot have been confused
    // once and not the other.
    var round: usize = 0;
    while (round < 64) : (round += 1) {
        const dataset = try spglib.getDataset(fixtures.rutile, 1e-5);
        try testing.expectEqual(@as(c_int, 136), dataset.spacegroupNumber());
        try testing.expectEqual(@as(usize, 16), dataset.operationCount());
        dataset.deinit();

        const magnetic = try spglib.getMagneticDataset(
            fixtures.rutile,
            &fixtures.rutile_spins.antiferromagnetic,
            1e-5,
        );
        try testing.expectEqual(@as(c_int, 1158), magnetic.uniNumber());
        try testing.expectEqual(@as(c_int, 3), magnetic.magneticType());
        magnetic.deinit();
    }

    // The raw C route allocates and frees through the same two entry points,
    // and it is the route a caller uses when it wants the `SpglibDataset`
    // itself rather than the typed wrapper. Mixing the two routes - a raw
    // allocation released by the facade, or the reverse - is exactly the
    // cross-provider mistake the single-table rule rules out, so this exercises
    // them side by side rather than one at a time.
    var mixed: usize = 0;
    while (mixed < 16) : (mixed += 1) {
        const raw = spglib.c.spg_get_dataset(
            fixtures.perovskite.latticePtr(),
            fixtures.perovskite.positionPtr(),
            fixtures.perovskite.typePtr(),
            @intCast(fixtures.perovskite.atomCount()),
            1e-5,
        );
        if (@intFromPtr(raw) == 0) return error.TestUnexpectedResult;
        try testing.expectEqual(@as(c_int, 221), raw.*.spacegroup_number);
        spglib.c.spg_free_dataset(raw);

        const wrapped = try spglib.getDataset(fixtures.perovskite, 1e-5);
        try testing.expectEqual(@as(c_int, 221), wrapped.spacegroupNumber());
        wrapped.deinit();
    }
}

/// Asserts that every operation maps every atom onto an atom of the same type,
/// which is the defining property of a space group for a given cell.
fn expectActsOnCell(cell: Cell, operations: Operations, symprec: f64) !void {
    const count = operations.count();
    try testing.expectEqual(operations.rotations.len, operations.translations.len);
    for (0..count) |index| {
        const rotation = operations.rotations[index];
        const translation = operations.translations[index];
        for (cell.positions, cell.types) |position, atom_type| {
            var mapped: [3]f64 = .{ 0, 0, 0 };
            for (0..3) |row| {
                for (0..3) |column| {
                    mapped[row] += @as(f64, @floatFromInt(rotation[row][column])) * position[column];
                }
                mapped[row] += translation[row];
            }
            if (!mapsOntoAtomOfType(cell, mapped, atom_type, symprec)) {
                std.debug.print(
                    "operation {d} maps atom {any} of type {d} to {any}, which matches no atom\n",
                    .{ index, position, atom_type, mapped },
                );
                return error.TestUnexpectedResult;
            }
        }
    }
}

fn mapsOntoAtomOfType(cell: Cell, position: [3]f64, atom_type: c_int, symprec: f64) bool {
    for (cell.positions, cell.types) |candidate, candidate_type| {
        if (candidate_type != atom_type) continue;
        var difference: [3]f64 = .{ 0, 0, 0 };
        for (0..3) |axis| {
            difference[axis] = position[axis] - candidate[axis];
            difference[axis] -= @round(difference[axis]);
        }
        var cartesian: [3]f64 = .{ 0, 0, 0 };
        for (0..3) |axis| {
            for (0..3) |vector| {
                cartesian[axis] += difference[vector] * cell.lattice[axis][vector];
            }
        }
        const squared = cartesian[0] * cartesian[0] +
            cartesian[1] * cartesian[1] +
            cartesian[2] * cartesian[2];
        if (squared < symprec * symprec) return true;
    }
    return false;
}

/// Asserts that `rotations` are exactly the 48 signed permutation matrices.
fn expectSignedPermutationGroup(rotations: []const [3][3]c_int) !void {
    try testing.expectEqual(@as(usize, 48), rotations.len);
    var keys: [48]i64 = undefined;
    for (rotations, 0..) |rotation, index| {
        try testing.expect(fixtures.isSignedPermutation(rotation));
        keys[index] = fixtures.permutationKey(rotation);
        for (keys[0..index]) |earlier| {
            try testing.expect(earlier != keys[index]);
        }
    }
}

/// True when `rotation` already appears in `seen`, so a caller can count the
/// distinct rotations of a group without assuming anything about them.
fn containsRotation(seen: []const [3][3]c_int, rotation: [3][3]c_int) bool {
    for (seen) |earlier| {
        const candidate = fixtures.permutationKey(rotation);
        if (candidate == fixtures.permutationKey(earlier)) return true;
    }
    return false;
}

/// Largest deviation between a lattice vector length and `reference`. The
/// vectors are columns, so this goes through the cell's own accessor.
fn lengthDeviation(cell: spglib.OwnedCell, reference: f64) f64 {
    var deviation: f64 = 0;
    for (0..3) |index| {
        deviation = @max(deviation, @abs(cell.asCell().length(index) - reference));
    }
    return deviation;
}

fn cellFrom(lattice: [3][3]f64) Cell {
    return .{
        .lattice = lattice,
        .positions = &.{.{ 0, 0, 0 }},
        .types = &.{1},
    };
}

fn allHalfComponents(vector: [3]f64) bool {
    for (vector) |component| {
        const fraction = component - @floor(component);
        if (@abs(fraction - 0.5) > 1e-6) return false;
    }
    return true;
}
