// A downstream package that only knows the exported `spglib` module.
//
// It identifies a cubic perovskite cell and prints the answer, so running it
// exercises the real library through the public facade rather than a mock.

const std = @import("std");

const spglib = @import("spglib");

/// SrTiO3: cubic, so the answer is fixed by the International Tables.
const perovskite = spglib.Cell{
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

pub fn main() !void {
    const version = spglib.getVersion();
    std.debug.print("linked against spglib {s}\n", .{version.version});

    const dataset = try spglib.getDataset(perovskite, 1e-5);
    defer dataset.deinit();

    std.debug.print(
        "spacegroup {d} {s}, point group {s}, {d} operations, cell volume {d:.4}\n",
        .{
            dataset.spacegroupNumber(),
            dataset.internationalSymbol(),
            dataset.pointgroupSymbol(),
            dataset.operationCount(),
            perovskite.volume(),
        },
    );

    try expect(dataset.spacegroupNumber() == 221, "expected space group 221");
    try expect(
        std.mem.eql(u8, dataset.internationalSymbol(), "Pm-3m"),
        "unexpected international symbol",
    );
    try expect(dataset.operationCount() == 48, "expected 48 operations");

    // The same cell reduced to its primitive setting.
    const primitive = try spglib.findPrimitive(std.heap.page_allocator, perovskite, 1e-5);
    defer primitive.deinit();
    std.debug.print("primitive cell: {d} atoms\n", .{primitive.atomCount()});
    try expect(primitive.atomCount() == 5, "expected the five-atom primitive cell of a P lattice");

    // The space-group type database is reachable through the same module.
    const spacegroup_type = try spglib.getSpacegroupType(dataset.hallNumber());
    // `international` is the spaced Hermann-Mauguin form; `internationalShort`
    // is the compact one used in the International Tables listings.
    std.debug.print("hall {d} is {s} ({s})\n", .{
        spacegroup_type.hallNumber,
        spacegroup_type.internationalShort(),
        spacegroup_type.schoenflies(),
    });
    try expect(spacegroup_type.number == dataset.spacegroupNumber(), "hall number disagrees with the dataset");

    // The same module exports the complete translated C API as `spglib.c`, and
    // it is a plain C call, not a facade one. Hall number 460 is the hexagonal
    // setting of R-3c, space group 167, in the database upstream ships
    // (src/spg_database.c:932), so the answer is fixed outside this package.
    //
    // Ownership: `SpglibSpacegroupType` comes back by value with its character
    // arrays inline, so there is nothing to release here. Nothing is compared
    // against the facade's answer, which would only prove that two wrappers of
    // one struct agree.
    const raw_type = spglib.c.spg_get_spacegroup_type(460);
    const raw_symbol = std.mem.sliceTo(&raw_type.international_short, 0);
    std.debug.print(
        "raw C spg_get_spacegroup_type(460): {d} {s}\n",
        .{ raw_type.number, raw_symbol },
    );
    try expect(raw_type.number == 167, "expected space group 167 for Hall number 460");
    try expect(raw_type.hall_number == 460, "expected Hall number 460 back");
    try expect(std.mem.eql(u8, raw_symbol, "R-3c"), "expected R-3c for Hall number 460");
}

fn expect(condition: bool, message: []const u8) !void {
    if (condition) return;
    std.debug.print("consumer: {s}\n", .{message});
    return error.ConsumerCheckFailed;
}
