// Coverage for the raw C surface exposed as `pub const c`.
//
// The Zig facade deliberately stays small. These tests exist so that the parts
// of include/spglib.h the facade does not wrap - the k-point mesh routines, the
// deprecated compatibility entry points and the magnetic database lookup - are
// still reachable and still behave as upstream documents.
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
const c = spglib.c;

/// Upstream test/functional/c/test_kpoints.cpp uses this exact rutile metric.
var kpoint_cell = spglib.Cell{
    .lattice = .{
        .{ 4, 0, 0 },
        .{ 0, 4, 0 },
        .{ 0, 0, 3 },
    },
    .positions = fixtures.rutile.positions,
    .types = fixtures.rutile.types,
};

test "the deprecated international symbol search still answers" {
    nativeReady();

    var symbol: [11]u8 = @splat(0);
    const number = c.spg_get_international(
        &symbol,
        kpoint_cell.latticePtr(),
        kpoint_cell.positionPtr(),
        kpoint_cell.types.ptr,
        @intCast(kpoint_cell.atomCount()),
        1e-5,
    );
    try testing.expectEqual(@as(c_int, 136), number);
    try testing.expectEqualStrings("P4_2/mnm", std.mem.sliceTo(&symbol, 0));
}

test "the deprecated multiplicity search reads off the species it is given" {
    nativeReady();

    // Upstream test/functional/c/test_symmetry_search.cpp:74-83 passes
    // `types[] = {1, 2}` and asserts 48: two distinguishable species on the
    // bcc lattice are CsCl, Pm-3m, whose order is 48. One species on the same
    // lattice is bcc iron, Im-3m, whose order is 96 (Hall 529's entry in
    // src/spg_database.c's `symmetry_operation_index` is {96, 7197}).
    // Reading 48 off a one-species cell measures the wrong structure.
    const cscl = c.spg_get_multiplicity(
        fixtures.cscl.latticePtr(),
        fixtures.cscl.positionPtr(),
        fixtures.cscl.typePtr(),
        @intCast(fixtures.cscl.atomCount()),
        1e-5,
    );
    try testing.expectEqual(@as(c_int, 48), cscl);

    const iron = c.spg_get_multiplicity(
        fixtures.bcc.latticePtr(),
        fixtures.bcc.positionPtr(),
        fixtures.bcc.typePtr(),
        @intCast(fixtures.bcc.atomCount()),
        1e-5,
    );
    try testing.expectEqual(@as(c_int, 96), iron);
}

test "the symmetry database entry for Hall number 460 lists 36 operations" {
    nativeReady();

    var rotations: [192][3][3]c_int = undefined;
    var translations: [192][3]f64 = undefined;
    const size = c.spg_get_symmetry_from_database(&rotations, &translations, 460);
    try testing.expectEqual(@as(c_int, 36), size);

    // Every database operation has an integer rotation in {-1,0,1} and a
    // translation inside one unit cell.
    const used: usize = @intCast(size);
    var identity_count: usize = 0;
    for (rotations[0..used], translations[0..used]) |rotation, translation| {
        for (rotation) |row| {
            for (row) |value| try testing.expect(value == -1 or value == 0 or value == 1);
        }
        for (translation) |value| try testing.expect(value >= -1e-9 and value < 1 + 1e-9);
        if (isIdentityOperation(rotation, translation)) identity_count += 1;
    }
    // R-3c is R-centred, so the identity *rotation* is paired with each of the
    // three centring translations. `symmetry_operation_index` gives Hall 460
    // {36, 4059}, and decoding `symmetry_operations` 4059..4094 yields 12
    // distinct rotations: six carrying (0,0,0), (2/3,1/3,1/3) and (1/3,2/3,2/3),
    // and six that invert z carrying the same three shifted by (0,0,1/2), i.e.
    // (0,0,1/2), (2/3,1/3,5/6) and (1/3,2/3,1/6). Only the identity
    // *operation* - identity rotation with zero translation - is unique.
    try testing.expectEqual(@as(usize, 1), identity_count);
}

test "the magnetic database lookup for UNI 1242 returns six operations" {
    nativeReady();

    var rotations: [384][3][3]c_int = undefined;
    var translations: [384][3]f64 = undefined;
    var time_reversals: [384]c_int = undefined;
    const size = c.spg_get_magnetic_symmetry_from_database(
        &rotations,
        &translations,
        &time_reversals,
        1242,
        434,
    );

    // UNI 1242 is BNS 146.12, whose family space group is R3. The
    // rhombohedral setting of R3 is Hall 434, and `get_hall_number_offset`
    // (src/msg_database.c:90114) maps it to offset 1 of UNI 1242's two
    // settings. That row of `magnetic_spacegroup_operation_index` is
    // {6, 51813}, so the answer is six operations. The settings are
    // compatible; the earlier failure was a wrong flag convention, not a
    // mismatched setting.
    try testing.expectEqual(@as(c_int, 6), size);
    const used: usize = @intCast(size);

    // `msgdb_get_magnetic_operation` stores `enc / 34012224`, which is 0 or 1
    // and never -1 (src/msg_database.c:82236-82239).
    // docs/magnetic_dataset.md:82-85 states the same contract: 1 is a
    // time-reversal operation, 0 an ordinary one.
    var ordinary: usize = 0;
    var time_reversed: usize = 0;
    var identity_count: usize = 0;
    for (time_reversals[0..used]) |flag| {
        switch (flag) {
            0 => ordinary += 1,
            1 => time_reversed += 1,
            else => return error.TestUnexpectedResult,
        }
    }
    for (rotations[0..used], translations[0..used]) |rotation, translation| {
        if (isIdentityOperation(rotation, translation)) identity_count += 1;
    }

    // This is a type-IV group: the anti-translation (1/2,1/2,1/2) carries
    // time reversal, so three of the six operations are time-reversed and
    // three are ordinary. Decoding `magnetic_symmetry_operations`
    // 51813..51818 gives translations (0,0,0) three times and (1/2,1/2,1/2)
    // three times, with time-reversal flags 0,0,1,0,1,1.
    try testing.expectEqual(@as(usize, 3), ordinary);
    try testing.expectEqual(@as(usize, 3), time_reversed);
    try testing.expectEqual(@as(usize, 1), identity_count);
}

test "the irreducible reciprocal mesh of rutile matches two upstream counts" {
    nativeReady();

    // Two independent known answers for the same rutile metric
    // (lattice 4,4,3 with the six positions in kpoint_cell):
    //   * 8x8x8 with is_shift {1,1,1} gives 40, from
    //     test/example/python_api/example_full.py:279-283, which defines
    //     `rutile` with exactly this lattice and these positions and
    //     prints "Number of irreducible k-points of Rutile with 8x8x8
    //     Monkhorst-Pack mesh is %d (40)".
    //   * 40x40x40 with is_shift {1,1,1} gives 4200, from
    //     test/functional/c/test_kpoints.cpp:16-33, which uses the same six
    //     positions and types and asserts `num_ir == 4200`.
    // The reduction cannot itself return 0, so the two runs discriminate
    // differently than "reduction versus sweep" would suggest. Both branches
    // of `get_dense_irreciprocal_mesh` seed `ir_mapping_table[i] = i` and only
    // ever lower it under a `grid_point_rot < ir_mapping_table[i]` guard, and
    // `grid_point_rot` is a `size_t` (src/kpoint.c:434, :468). For i = 0 the
    // guard is an unsigned comparison against 0, so it never fires and
    // `get_dense_num_ir` (src/kpoint.c:533-552) always counts index 0.
    // num_ir is therefore >= 1 from the reduction, and the only zero-returns
    // are the two allocations: the dense table at src/kpoint.c:92-96
    // (512,000 bytes at 40^3 against 4,096 at 8^3) and `mat_alloc_MatINT` at
    // src/spglib.c:2173-2177. Running 8^3 first separates an allocation that
    // fails only at the larger size from anything upstream of the reduction.
    try testing.expectEqual(
        @as(c_int, 40),
        try irreduciblePoints(.{ 8, 8, 8 }, .{ 1, 1, 1 }, 1, 1e-5),
    );
    try testing.expectEqual(
        @as(c_int, 4200),
        try irreduciblePoints(.{ 40, 40, 40 }, .{ 1, 1, 1 }, 1, 1e-5),
    );
}

test "the dense reciprocal mesh agrees with the int one point by point" {
    nativeReady();

    // kpoint.c:101-103 has the int entry point copy the dense mapping table
    // element by element, so the two must agree on the count and on every
    // index, not merely on the total.
    const mesh = [3]c_int{ 5, 5, 5 };
    const is_shift = [3]c_int{ 1, 1, 1 };
    const points: usize = 5 * 5 * 5;

    const addresses = try testing.allocator.alloc([3]c_int, points);
    defer testing.allocator.free(addresses);
    const mapping = try testing.allocator.alloc(c_int, points);
    defer testing.allocator.free(mapping);
    const dense = try testing.allocator.alloc(usize, points);
    defer testing.allocator.free(dense);

    const from_int = c.spg_get_ir_reciprocal_mesh(
        addresses.ptr,
        mapping.ptr,
        &mesh,
        &is_shift,
        1,
        kpoint_cell.latticePtr(),
        kpoint_cell.positionPtr(),
        kpoint_cell.typePtr(),
        @intCast(kpoint_cell.atomCount()),
        1e-5,
    );
    const from_dense = c.spg_get_dense_ir_reciprocal_mesh(
        addresses.ptr,
        dense.ptr,
        &mesh,
        &is_shift,
        1,
        kpoint_cell.latticePtr(),
        kpoint_cell.positionPtr(),
        kpoint_cell.typePtr(),
        @intCast(kpoint_cell.atomCount()),
        1e-5,
    );

    try testing.expect(from_int > 0);
    try testing.expectEqual(@as(usize, @intCast(from_int)), from_dense);
    for (mapping, dense) |int_index, dense_index| {
        try testing.expectEqual(int_index, @as(c_int, @intCast(dense_index)));
    }
}

/// Number of irreducible k-points of `kpoint_cell` on `mesh`, and checks that
/// the returned mapping really does cover exactly `irreducible` distinct
/// targets. Upstream's Python example counts that with `len(np.unique(mapping))`
/// (test/example/python_api/example_full.py:273), so the same quantity is used
/// here rather than trusting the returned count on its own.
fn irreduciblePoints(
    mesh: [3]c_int,
    is_shift: [3]c_int,
    is_time_reversal: c_int,
    symprec: f64,
) !c_int {
    const nx: usize = @intCast(mesh[0]);
    const ny: usize = @intCast(mesh[1]);
    const nz: usize = @intCast(mesh[2]);
    const points: usize = nx * ny * nz;

    const addresses = try testing.allocator.alloc([3]c_int, points);
    defer testing.allocator.free(addresses);
    const mapping = try testing.allocator.alloc(c_int, points);
    defer testing.allocator.free(mapping);

    const irreducible = c.spg_get_ir_reciprocal_mesh(
        addresses.ptr,
        mapping.ptr,
        &mesh,
        &is_shift,
        is_time_reversal,
        kpoint_cell.latticePtr(),
        kpoint_cell.positionPtr(),
        kpoint_cell.typePtr(),
        @intCast(kpoint_cell.atomCount()),
        symprec,
    );
    if (irreducible <= 0) return irreducible;

    // `ir_mapping_table` does not hold compacted indices. src/kpoint.c:82 says
    // "Each value of 'map' corresponds to the index of grid_point", and
    // `get_dense_ir_reciprocal_mesh_normal` seeds `ir_mapping_table[i] = i`
    // (src/kpoint.c:445) and afterwards only lowers it to another grid
    // point's own entry (src/kpoint.c:451-457). Every value therefore indexes
    // the full mesh, and the returned count is the number of DISTINCT values
    // taken, which is precisely what `get_dense_num_ir` counts
    // (src/kpoint.c:533-552) and what upstream's own example obtains from
    // `len(np.unique(mapping))` (test/example/python_api/example_full.py:273).
    //
    // Bounding the values by the irreducible count instead would reject every
    // mapping whose target is not itself a representative, which is the common
    // case: the reduction maps most grid points onto a point that is not its
    // own image.
    var seen = try testing.allocator.alloc(bool, points);
    defer testing.allocator.free(seen);
    @memset(seen, false);
    var distinct: usize = 0;
    for (mapping) |index| {
        if (index < 0 or index >= @as(c_int, @intCast(points))) {
            return error.TestUnexpectedResult;
        }
        if (!seen[@intCast(index)]) {
            seen[@intCast(index)] = true;
            distinct += 1;
        }
    }
    if (distinct != @as(usize, @intCast(irreducible))) return error.TestUnexpectedResult;
    return irreducible;
}

test "grid point indices agree between the int and dense entry points" {
    nativeReady();

    // Two distinct C entry points, not a facade and its target: upstream
    // declares one as returning `c_int` (include/spglib.h:491) and the other
    // as returning `size_t` (:493), and both reach the same computation -
    // `spg_get_grid_point_from_address` calls
    // `kgd_get_grid_point_double_mesh` and the dense one calls
    // `kgd_get_dense_grid_point_double_mesh` (src/spglib.c:880-904), and those
    // two differ only in their return type (src/kgrid.c:23-31). An index that
    // disagreed between them would mean one of them truncated or reduced
    // differently, which is a real width question rather than a restatement of
    // one call by another.
    //
    // The mesh is 5x3x4, so the address is mapped into 60 grid points and the
    // index must land inside them; `get_all_grid_addresses` asserts exactly
    // that at src/kgrid.c:57 before writing `grid_address[grid_point]`, so an
    // index outside the mesh would be a buffer overrun there.
    const mesh: [3]c_int = .{ 5, 3, 4 };
    const candidates = [_][3]c_int{
        .{ 0, 0, 0 },
        .{ 2, 1, 3 },
        .{ -2, -1, 0 },
        .{ 5, 3, 4 },
    };
    const points: usize = 5 * 3 * 4;
    for (candidates) |address| {
        const from_int = c.spg_get_grid_point_from_address(&address, &mesh);
        const from_dense = c.spg_get_dense_grid_point_from_address(&address, &mesh);
        try testing.expectEqual(from_int, @as(c_int, @intCast(from_dense)));
        try testing.expect(from_dense < points);
    }

    // The origin is its own index, and that one is a constant rather than a
    // derivation: doubling {0,0,0} gives {0,0,0}, nothing is reduced or
    // halved away, and the formula at src/kgrid.c:88-89 is 0 for all three
    // terms. Any address that reduced to the origin would collide with it.
    const origin: [3]c_int = .{ 0, 0, 0 };
    try testing.expectEqual(
        @as(usize, 0),
        c.spg_get_dense_grid_point_from_address(&origin, &mesh),
    );
}

test "the space-group type search from symmetry agrees with the dataset" {
    nativeReady();

    const dataset = try spglib.getDataset(fixtures.bcc, 1e-5);
    defer dataset.deinit();

    const operations = dataset.operations();
    const from_operations = c.spg_get_spacegroup_type_from_symmetry(
        @ptrCast(@constCast(operations.rotations.ptr)),
        @ptrCast(@constCast(operations.translations.ptr)),
        @intCast(dataset.operationCount()),
        fixtures.bcc.latticePtr(),
        1e-5,
    );
    try testing.expectEqual(dataset.spacegroupNumber(), from_operations.number);
    try testing.expectEqual(dataset.hallNumber(), from_operations.hall_number);
}

test "niggli reduction through the C entry point keeps the volume" {
    nativeReady();

    // Unit upper-triangular lattice: volume 1 before and after reduction.
    var lattice: [3][3]f64 = .{
        .{ 1.0, 0.0, 0.0 },
        .{ 0.5, 1.0, 0.0 },
        .{ 0.5, 0.25, 1.0 },
    };
    try testing.expect(c.spg_niggli_reduce(&lattice, 1e-5) != 0);
    const reduced = spglib.Cell{
        .lattice = lattice,
        .positions = &.{.{ 0, 0, 0 }},
        .types = &.{1},
    };
    try testing.expectApproxEqAbs(1.0, reduced.volume(), 1e-9);
}

test "the raw message table stops before its sentinel entry" {
    nativeReady();

    // spg_get_error_message (src/spglib.c:214-228) breaks on the
    // {SPGERR_NONE, ""} sentinel at index 9 before it compares its argument.
    // SPGERR_NONE therefore has no message pointer at all, not an empty
    // string, and neither does any code outside the table.
    // The translation spells a C pointer as `[*c]T`, which has no null in its
    // type, so a raw caller compares addresses.
    try testing.expect(@intFromPtr(c.spg_get_error_message(9)) == 0);
    // Only the sentinel is asserted here. Whether the rows before it carry text
    // is a property of upstream's message table rather than of this route, and
    // the facade's own test already checks that two codes answer differently.
}

test "a failed C dataset call reports a status through the raw accessor" {
    nativeReady();

    const failed = c.spg_get_dataset(
        fixtures.coincident_atoms.latticePtr(),
        fixtures.coincident_atoms.positionPtr(),
        fixtures.coincident_atoms.typePtr(),
        @intCast(fixtures.coincident_atoms.atomCount()),
        1e-5,
    );
    // The translation spells a C pointer as `[*c]T`, which has no null in its
    // type, so the address is what a raw caller compares.
    try testing.expect(@intFromPtr(failed) == 0);
    try testing.expectEqual(@as(c_int, 4), @as(c_int, @intCast(c.spg_get_error_code())));
}

/// True when `rotation` is the identity and `translation` is the zero vector.
/// A centred group pairs the identity *rotation* with each centring vector,
/// so only the full identity operation is unique in one.
fn isIdentityOperation(rotation: [3][3]c_int, translation: [3]f64) bool {
    for (0..3) |row| {
        for (0..3) |column| {
            const expected: c_int = if (row == column) 1 else 0;
            if (rotation[row][column] != expected) return false;
        }
    }
    for (translation) |component| {
        if (@abs(component) > 1e-9) return false;
    }
    return true;
}
