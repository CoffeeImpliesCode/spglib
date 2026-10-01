// Runnable smoke example: `zig build smoke`.
//
// Prints deterministic, semantic output for well-known crystals and checks it.
// Every number below is fixed by the International Tables or by an upstream
// fixture, so the output is a property of the library and not of this wrapper.

const std = @import("std");

const spglib = @import("spglib");
// A Zig module's root is its root source file's directory, so a module rooted
// at `zig/examples/smoke.zig` cannot reach `zig/tests/` with a relative import
// and `Module` has no option to widen it. build.zig roots a module at
// `zig/tests/fixtures.zig` and passes it in as the named import "fixtures".
const fixtures = @import("fixtures");

const allocator = std.heap.page_allocator;

pub fn main() !void {
    const version = spglib.getVersion();
    std.debug.print("spglib {s} ({s})\n", .{ version.version, version.commit });

    try reportRutile();
    try reportPerovskite();
    try reportToleranceSweep();
    try reportCorundum();
    try reportMagnetic();
    try reportFailure();
    try reportRawEscapeHatch();
}

/// Rutile: space group 136, 16 operations, and 6 atoms because P4_2/mnm is a
/// P lattice, so its primitive cell is its conventional cell.
fn reportRutile() !void {
    const symprec = 1e-5;
    const dataset = try spglib.getDataset(fixtures.rutile, symprec);
    defer dataset.deinit();

    // Rutile is a primitive tetragonal cell, so its primitive cell is itself.
    const primitive = try spglib.findPrimitive(allocator, fixtures.rutile, symprec);
    defer primitive.deinit();
    // Body centred iron is not: two conventional atoms reduce to one.
    const bcc_primitive = try spglib.findPrimitive(allocator, fixtures.bcc, symprec);
    defer bcc_primitive.deinit();

    std.debug.print(
        "rutile: spacegroup {d} {s}, {d} operations, {d} atoms, {d} primitive atoms\n",
        .{
            dataset.spacegroupNumber(),
            dataset.internationalSymbol(),
            dataset.operationCount(),
            dataset.atomCount(),
            primitive.atomCount(),
        },
    );
    std.debug.print(
        "bcc iron: {d} atoms reduce to {d} primitive atom\n",
        .{ fixtures.bcc.atomCount(), bcc_primitive.atomCount() },
    );
    try require(dataset.spacegroupNumber() == 136, "rutile spacegroup is {d}", .{dataset.spacegroupNumber()});
    try require(
        std.mem.eql(u8, dataset.internationalSymbol(), "P4_2/mnm"),
        "rutile symbol is {s}",
        .{dataset.internationalSymbol()},
    );
    try require(dataset.operationCount() == 16, "rutile has {d} operations", .{dataset.operationCount()});
    try require(primitive.atomCount() == 6, "rutile primitive cell has {d} atoms", .{primitive.atomCount()});
    try require(bcc_primitive.atomCount() == 1, "bcc primitive cell has {d} atoms", .{bcc_primitive.atomCount()});

    // A space group is closed under composition; the search result must be too.
    const operations = dataset.operations();
    const closed = isClosedUnderComposition(operations);
    std.debug.print("rutile symmetry closure: {s}\n", .{if (closed) "closed" else "NOT closed"});
    try require(closed, "rutile operations are not closed under composition", .{});

    const point_group = try spglib.getPointGroup(operations.rotations);
    std.debug.print("rutile point group: {s}\n", .{point_group.symbol()});
    try require(std.mem.eql(u8, point_group.symbol(), "4/mmm"), "rutile point group is {s}", .{point_group.symbol()});

    // The caller bounds the search; spglib refuses instead of truncating.
    const bounded = spglib.getSymmetry(allocator, fixtures.rutile, symprec, 8);
    if (bounded) |symmetry| {
        symmetry.deinit();
        return error.SmokeCheckFailed;
    } else |failure| {
        std.debug.print(
            "rutile search bounded to 8 operations: rejected ({s})\n",
            .{@errorName(failure)},
        );
        try require(failure == error.ArraySizeShortage, "unexpected failure {s}", .{@errorName(failure)});
    }
}

/// Cubic perovskite: space group 221, the 48 signed permutations of m-3m.
fn reportPerovskite() !void {
    const symprec = 1e-5;
    const dataset = try spglib.getDataset(fixtures.perovskite, symprec);
    defer dataset.deinit();

    std.debug.print(
        "perovskite: spacegroup {d} {s}, point group {s}, {d} operations, orbits {d}\n",
        .{
            dataset.spacegroupNumber(),
            dataset.internationalSymbol(),
            dataset.pointgroupSymbol(),
            dataset.operationCount(),
            fixtures.distinctCount(dataset.mappingToPrimitive()),
        },
    );
    try require(dataset.spacegroupNumber() == 221, "perovskite spacegroup is {d}", .{dataset.spacegroupNumber()});
    try require(
        std.mem.eql(u8, dataset.internationalSymbol(), "Pm-3m"),
        "perovskite symbol is {s}",
        .{dataset.internationalSymbol()},
    );
    try require(dataset.operationCount() == 48, "perovskite has {d} operations", .{dataset.operationCount()});
    try require(
        allSignedPermutations(dataset.operations().rotations),
        "perovskite rotations are not the 48 signed permutations",
        .{},
    );
}

/// The same cell with c shortened by 0.005 A: tetragonal at a tight tolerance,
/// cubic at a loose one.
fn reportToleranceSweep() !void {
    const tight = try spglib.getDataset(fixtures.distorted_perovskite, 1e-5);
    defer tight.deinit();
    const loose = try spglib.getDataset(fixtures.distorted_perovskite, 1e-2);
    defer loose.deinit();

    std.debug.print(
        "symprec sweep on the distorted perovskite: 1e-5 -> {d} {s} ({d} ops), 1e-2 -> {d} {s} ({d} ops)\n",
        .{
            tight.spacegroupNumber(),
            tight.internationalSymbol(),
            tight.operationCount(),
            loose.spacegroupNumber(),
            loose.internationalSymbol(),
            loose.operationCount(),
        },
    );
    try require(tight.spacegroupNumber() == 123, "tight sweep found {d}", .{tight.spacegroupNumber()});
    try require(loose.spacegroupNumber() == 221, "loose sweep found {d}", .{loose.spacegroupNumber()});

    // Upstream standardises this measurably non-cubic cell at symprec 1e-1.
    // The primitive vectors of a body-centred cell are the columns of I_mat
    // (src/spacegroup.c:350-352), each of length sqrt(3)/2 times the
    // conventional edge, and `standardize_primitive` applies it directly with
    // an identity `trans_mat` and no Delaunay step (src/spglib.c:1864-1865,
    // src/spacegroup.c:547-557). So the primitive edge is sqrt(3)/2 of the
    // conventional one, not sqrt(8)/2.
    //
    // The conventional edge comes from the conventional standardisation at
    // the same tolerance rather than a hard-coded 4.0: both paths start from
    // the same `dataset->std_lattice`, so the ratio stays exact whichever
    // cubic parameter the idealisation settles on.
    const conventional = try spglib.standardizeCell(allocator, fixtures.distorted_bcc, .{
        .to_primitive = false,
        .symprec = 1e-1,
    });
    defer conventional.deinit();
    const reference = std.math.sqrt(3.0) / 2.0 * conventional.asCell().length(0);
    const standardized = try spglib.standardizeCell(allocator, fixtures.distorted_bcc, .{
        .to_primitive = true,
        .symprec = 1e-1,
    });
    defer standardized.deinit();
    const deviation = lengthDeviation(standardized, reference);
    std.debug.print(
        "distorted bcc at symprec 1e-1: {d} primitive atoms, vector lengths within {d:.6} of {d:.6}\n",
        .{ standardized.atomCount(), deviation, reference },
    );
    try require(standardized.atomCount() == 1, "bcc primitive cell has {d} atoms", .{standardized.atomCount()});
    try require(deviation < 1e-2, "bcc primitive vectors deviate by {d}", .{deviation});

    // A body-centred conventional cell encloses exactly twice the volume of
    // its primitive cell. That ratio is structural, so it holds whatever
    // value the idealisation chose, and it catches a wrong geometric factor
    // on its own: a reference edge is one equation, this is a second.
    const volume_ratio = conventional.asCell().volume() / standardized.asCell().volume();
    try require(
        @abs(volume_ratio - 2.0) < 1e-6,
        "bcc conventional-to-primitive volume ratio is {d}",
        .{volume_ratio},
    );
}

/// Hexagonal corundum: 30 atoms in the R-centred conventional cell, 10 in the
/// primitive one, and an oblique lattice that is only correct read as columns.
fn reportCorundum() !void {
    const dataset = try spglib.getDataset(fixtures.corundum, 1e-5);
    defer dataset.deinit();

    const primitive = try spglib.findPrimitive(allocator, fixtures.corundum, 1e-5);
    defer primitive.deinit();

    std.debug.print(
        "corundum: spacegroup {d} {s}, a = b = {d:.6}, gamma = {d:.1} deg, {d} atoms reduce to {d}\n",
        .{
            dataset.spacegroupNumber(),
            dataset.internationalSymbol(),
            fixtures.corundum.length(0),
            fixtures.corundum.angle(0, 1) * 180.0 / std.math.pi,
            dataset.atomCount(),
            primitive.atomCount(),
        },
    );
    try require(dataset.spacegroupNumber() == 167, "corundum spacegroup is {d}", .{dataset.spacegroupNumber()});
    try require(
        std.mem.eql(u8, dataset.internationalSymbol(), "R-3c"),
        "corundum symbol is {s}",
        .{dataset.internationalSymbol()},
    );
    try require(dataset.atomCount() == 30, "corundum cell has {d} atoms", .{dataset.atomCount()});
    try require(primitive.atomCount() == 10, "corundum primitive cell has {d} atoms", .{primitive.atomCount()});
}

/// Gray, ferro- and antiferromagnetic rutile: three distinct magnetic types.
fn reportMagnetic() !void {
    const Case = struct {
        name: []const u8,
        spins: []const f64,
        uni: c_int,
    };
    // The explicit `[_]Case` type is what makes `case.spins` a field access.
    // An inferred `.{}` literal is an anonymous tuple, and a runtime `for`
    // cannot resolve the tuple index that `.spins` then needs.
    const cases = [_]Case{
        .{ .name = "ferromagnetic", .spins = &fixtures.rutile_spins.ferromagnetic, .uni = 1155 },
        .{ .name = "gray", .spins = &fixtures.rutile_spins.gray, .uni = 1156 },
        .{ .name = "antiferromagnetic", .spins = &fixtures.rutile_spins.antiferromagnetic, .uni = 1158 },
    };
    for (cases) |case| {
        const dataset = try spglib.getMagneticDataset(fixtures.rutile, case.spins, 1e-5);
        defer dataset.deinit();
        std.debug.print(
            "rutile {s}: magnetic type {d}, UNI {d}, {d} operations\n",
            .{ case.name, dataset.magneticType(), dataset.uniNumber(), dataset.operationCount() },
        );
        try require(dataset.uniNumber() == case.uni, "{s} rutile is UNI {d}", .{ case.name, dataset.uniNumber() });
    }

    const magnetic_type = try spglib.getMagneticSpacegroupType(1242);
    std.debug.print("magnetic type 1242: BNS {s}\n", .{magnetic_type.bnsNumber()});
    try require(
        std.mem.eql(u8, magnetic_type.bnsNumber(), "146.12"),
        "UNI 1242 is BNS {s}",
        .{magnetic_type.bnsNumber()},
    );
}

/// Coincident atoms must fail loudly rather than return a group.
fn reportFailure() !void {
    const result = spglib.getDataset(fixtures.coincident_atoms, 1e-5);
    if (result) |dataset| {
        dataset.deinit();
        return error.SmokeCheckFailed;
    } else |failure| {
        std.debug.print(
            "coincident atoms: rejected with {s} ({s})\n",
            .{ @errorName(failure), spglib.errorMessage(spglib.lastErrorCode()) orelse "no message" },
        );
        try require(failure == error.AtomsTooClose, "unexpected failure {s}", .{@errorName(failure)});
    }
}

/// The complete C API stays reachable next to the facade.
fn reportRawEscapeHatch() !void {
    var symbol: [11]u8 = @splat(0);
    const number = spglib.c.spg_get_international(
        &symbol,
        fixtures.rutile.latticePtr(),
        fixtures.rutile.positionPtr(),
        fixtures.rutile.typePtr(),
        @intCast(fixtures.rutile.atomCount()),
        1e-5,
    );
    std.debug.print("raw C spg_get_international: {d} {s}\n", .{ number, std.mem.sliceTo(&symbol, 0) });
    try require(number == 136, "raw C search returned {d}", .{number});

    const mesh_index = try spglib.gridPointFromAddress(.{ 0, 0, 0 }, .{ 2, 2, 2 });
    std.debug.print("grid address 0 of a 2x2x2 mesh maps to index {d}\n", .{mesh_index});
    try require(mesh_index == 0, "grid address 0 maps to {d}", .{mesh_index});
}

/// Checks that every composition of two operations is again an operation.
fn isClosedUnderComposition(operations: spglib.Operations) bool {
    const count = operations.count();
    for (0..count) |left| {
        for (0..count) |right| {
            if (!containsComposition(operations, left, right)) return false;
        }
    }
    return true;
}

fn containsComposition(operations: spglib.Operations, left: usize, right: usize) bool {
    var composed: [3][3]c_int = @splat(@splat(0));
    var translation: [3]f64 = @splat(0);
    for (0..3) |row| {
        for (0..3) |column| {
            var sum: c_int = 0;
            for (0..3) |inner| {
                sum += operations.rotations[left][row][inner] * operations.rotations[right][inner][column];
            }
            composed[row][column] = sum;
        }
        var shift: f64 = 0;
        for (0..3) |column| {
            shift += @as(f64, @floatFromInt(operations.rotations[left][row][column])) *
                operations.translations[right][column];
        }
        translation[row] = shift + operations.translations[left][row];
    }

    const count = operations.count();
    for (0..count) |index| {
        if (!std.meta.eql(operations.rotations[index], composed)) continue;
        var matches = true;
        for (0..3) |axis| {
            var difference = translation[axis] - operations.translations[index][axis];
            difference -= @round(difference);
            if (@abs(difference) > 1e-6) matches = false;
        }
        if (matches) return true;
    }
    return false;
}

fn allSignedPermutations(rotations: []const [3][3]c_int) bool {
    if (rotations.len != 48) return false;
    for (rotations, 0..) |rotation, index| {
        if (!fixtures.isSignedPermutation(rotation)) return false;
        const key = fixtures.permutationKey(rotation);
        for (rotations[0..index]) |earlier| {
            if (fixtures.permutationKey(earlier) == key) return false;
        }
    }
    return true;
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

fn require(condition: bool, comptime format: []const u8, args: anytype) !void {
    if (condition) return;
    std.debug.print("smoke: check failed: " ++ format ++ "\n", args);
    return error.SmokeCheckFailed;
}
