// A downstream package that only knows the exported `spglib` module.
//
// It identifies a cubic perovskite cell and prints the answer, so running it
// exercises the real library through the public facade rather than a mock.
//
// ## Two configurations
//
// The same source builds against a linked package and against a
// runtime-loaded one. `spglib.runtime_loaded` is a comptime constant, so the
// difference is one branch and no duplicated program: in the runtime-loaded
// build the provider is named on the command line (`--provider <path>`) or in
// `SPGLIB_TEST_PROVIDER`, loaded once, and the same answers follow. In a linked
// build neither is needed and neither is read.

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

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

pub fn main(init: std.process.Init) !void {
    // In a runtime-loading build nothing below can run until a provider is
    // loaded, and the load is the one explicit step the contract asks for. In a
    // linked build this branch is not analyzed at all and the module is already
    // usable.
    if (comptime spglib.runtime_loaded) {
        spglib.load(.{ .path = try providerRequest(init) }) catch |err| {
            std.debug.print("consumer: loading the named provider failed: {t}\n", .{err});
            return err;
        };
    }

    const version = spglib.getVersion();
    std.debug.print("spglib {s}, {s} provider\n", .{
        version.version,
        if (spglib.runtime_loaded) "loaded" else "linked",
    });

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

/// The provider this run should load, from `--provider <path>` or from
/// `SPGLIB_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location, and a build
/// that was not told which file to load says so rather than loading something
/// else.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get("SPGLIB_TEST_PROVIDER") orelse
        return noProvider();
}

/// Say which variable is missing. An error name on its own would send the next
/// person into the loader instead of to the command line.
fn noProvider() ConfigurationError {
    std.debug.print(
        "consumer: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export SPGLIB_TEST_PROVIDER with a shared object exporting the " ++
            "entry points of include/spglib.h. Nothing is loaded by default and " ++
            "no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}

fn expect(condition: bool, message: []const u8) !void {
    if (condition) return;
    std.debug.print("consumer: {s}\n", .{message});
    return error.ConsumerCheckFailed;
}
