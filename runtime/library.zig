// SPDX-License-Identifier: BSD-3-Clause
//
//! spglib's side of the runtime loader: the names its synchronization binding
//! has, and what it requires of a provider beyond resolving its symbols.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them
//! spglib's, and it is the file another SDK replaces.
//!
//! ## What a provider must be
//!
//! Every `SPG_API` declaration in `include/spglib.h`, which is the whole
//! declared library surface: the version and identity calls, the error table,
//! the dataset search and standardisation families, the deprecated compatibility
//! entry points, the symmetry searches with collinear spins and with site
//! tensors, the space-group and magnetic space-group type lookups, the built-in
//! operation databases, the k-point mesh routines, and the lattice reductions.
//! That is 59 functions and not the subset the typed facade in `zig/root.zig`
//! happens to call, because a caller that reaches `spglib.c` must find the same
//! library behind every name it can see.
//!
//! Two of those 59 are not in that list, and `runtime/graph.zig` says why under
//! `provider_optional`: `spg_get_grid_points_by_rotations` and
//! `spg_get_BZ_grid_points_by_rotations` are declared at
//! `include/spglib.h:544-546` and `:551-554` and defined nowhere in this tree,
//! so no provider built from it can export them.
//!
//! There is no exported data in this surface. Every one of the 59 is a
//! function, so no table entry has to keep a provider address live, and there is
//! no `NAMEAddr()` accessor to generate. The crystallographic tables
//! (`src/spg_database.c`, `src/msg_database.c`, `src/sitesym_database.c`) are
//! `static` arrays inside the library and are not exported; a provider reaches
//! them only through the functions below.
//!
//! ## The ABI boundary, stated honestly
//!
//! A provider must agree with the translated header on four things, all of them
//! structural rather than stylistic:
//!
//!  * **Struct layout.** `SpglibDataset` (`include/spglib.h:115-141`) and
//!    `SpglibMagneticDataset` (`:158-185`) are returned as *pointers* to memory
//!    the provider allocated, and the caller reads twenty-odd fields straight
//!    out of them: `rotations`, `translations`, `wyckoffs`,
//!    `site_symmetry_symbols`, `std_positions`, `std_tensors` and the rest. A
//!    provider whose idea of those offsets differs produces a dataset that looks
//!    complete and is nonsense, so this is the load boundary in the strictest
//!    sense. The header fixes every offset: no macro, no configure test and no
//!    conditional typedef touches those two structs, which is stated here
//!    because "no configuration-dependent struct" is a claim a caller has to be
//!    able to check rather than take.
//!
//!  * **Struct return convention.** `spg_get_spacegroup_type`
//!    (`:428`), `spg_get_spacegroup_type_from_symmetry` (`:341`),
//!    `spg_get_magnetic_spacegroup_type` (`:434`) and
//!    `spg_get_magnetic_spacegroup_type_from_symmetry` (`:345`) all return a
//!    struct **by value**, and those structs are 80 to 110 bytes. That is past
//!    the register-return limit on every ABI this SDK targets, so the pair has
//!    to agree on the hidden-return-pointer convention as well as the layout.
//!    This is the one part of the boundary the check below can actually observe,
//!    which is why it queries a by-value struct return.
//!
//!  * **Scalar widths.** `int`, `double` and `size_t` throughout, in that
//!    order: counts are `int`, tolerances and coordinates are `double`, and the
//!    `spg_get_dense_*` family returns `size_t` while its `int`-returning twin
//!    returns `c_int` (`include/spglib.h:493`, `:517`, `:535`). The target's own
//!    widths and calling conventions are what "the C ABI" means for a provider
//!    reached through `dlopen`.
//!
//!  * **Allocator ownership.** Every result the provider allocates, it also
//!    frees: `spg_get_dataset` and `spg_get_magnetic_dataset` return `malloc`
//!    storage released by `spg_free_dataset` (`:244`) and
//!    `spg_free_magnetic_dataset` (`:245`), which walk the dataset's own arrays
//!    and `free` them (`src/spglib.c:293-333`, `:335-365`). There is no
//!    allocator hook and no provider-supplied allocator argument anywhere in the
//!    header, so a caller passes no allocator and gets none, and the only correct
//!    release for a dataset is the matching `spg_free_*` **from the same
//!    provider**. Because the loader keeps exactly one provider for the life of
//!    the process and refuses a second one, a `Dataset` handed out by this
//!    module and freed by this module cannot cross a provider boundary; that is
//!    the property that makes the ownership rule hold rather than a convention.
//!
//! What is deliberately *not* part of the boundary:
//!
//!  * `SPG_API` itself (`include/spglib.h:12-27`). It expands to
//!    `__attribute__((visibility("default")))` when the library itself is being
//!    built and to nothing otherwise, so it decides which symbols are visible,
//!    not what any of them mean.
//!  * `SPG_DEPRECATED` (`:35-48`). It picks between the C23 attribute and the
//!    compiler's own, and a declaration's deprecation changes no layout and no
//!    convention.
//!  * `GRID_ORDER_XYZ` and `GRID_BOUNDARY_AS_NEGATIVE` (`src/kgrid.c:87`,
//!    `:112`, `:122`). Both are internal to `src/kgrid.c` and neither appears in
//!    `include/spglib.h`, so a provider built either way presents the same
//!    declarations. They do change which grid point an address maps onto, which
//!    is a provider behaviour a caller observes, not an ABI difference this
//!    route can see.
//!  * The optimize mode the provider was built with. Nothing in the public
//!    header depends on it.
//!
//! ## What is actually checked
//!
//! Resolving the symbols and translating a header are the boundary. They are not
//! proof that a provider is compatible, and this file does not pretend to add
//! one. Three checks run after every symbol resolved and before anything is
//! published, and each one is a fact about a *working* entry point rather than a
//! count:
//!
//!   * `spg_get_major_version`, `spg_get_minor_version` and
//!     `spg_get_micro_version` must answer the three integers this build's
//!     translated header carries in `SPGLIB_MAJOR_VERSION`,
//!     `SPGLIB_MINOR_VERSION` and `SPGLIB_MICRO_VERSION`. Those macros come from
//!     the generated `version.h` this build configures from `src/version.h.in`,
//!     and `src/spglib.c:191-204` returns the same three macros the provider was
//!     compiled with, so a provider built from a different source tree is
//!     refused by value instead of by symbol count. This is the weakest of the
//!     three and it is here because it is nearly free, not because it settles
//!     compatibility.
//!   * `spg_get_version()` must return exactly the string
//!     `SPGLIB_VERSION` names. `src/spglib.c:176-179` returns the macro, so
//!     this reads the provider's own read-only data through the header's own
//!     expectation of it.
//!   * `spg_get_spacegroup_type(1)` must answer space group 1 with Hall number
//!     1 and the international short symbol `"P1"`. Hall number 1 is P1 in the
//!     International Tables and is the first row of `spg_database.c`'s table,
//!     so the expected values are an independent known answer rather than
//!     something this build computed. This is the strongest of the three,
//!     because it is a **by-value struct return**: it exercises the hidden
//!     return-pointer convention, the field offsets inside
//!     `SpglibSpacegroupType`, its `char[11]` character arrays, and the
//!     provider's static database, all in one call that allocates nothing.
//!
//! What is deliberately not called: anything that takes a cell. `spg_get_dataset`
//! allocates through the provider's `malloc`, and a load-time check has no
//! business allocating memory the caller did not ask for and cannot free if the
//! load then fails.
//!
//! None of the three inspects the `SpglibDataset` layout, because no load-time
//! check can: producing one requires a cell and a successful symmetry search,
//! which is the caller's business and not the loader's. A caller that needs the
//! pointer-returned layouts to match has to take a provider built from this
//! header, which is what `README.zig.md` documents.

const std = @import("std");

const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.h` compiled with
/// `RT_SYNC_PREFIX=spglib_rt`, which is what `runtime/graph.zig` passes. Two
/// spellings of that prefix have to agree: this file names the symbols, and
/// graph.zig defines the macro. A build where they disagree does not link, and
/// that is the whole error report: there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
pub const Sync = struct {
    extern fn spglib_rt_lock() void;
    extern fn spglib_rt_unlock() void;
    extern fn spglib_rt_wait() void;
    extern fn spglib_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64 bits on x86_64, aarch64 and riscv64.
    extern fn spglib_rt_thread_self() u64;

    pub fn lock() void {
        spglib_rt_lock();
    }
    pub fn unlock() void {
        spglib_rt_unlock();
    }
    pub fn wait() void {
        spglib_rt_wait();
    }
    pub fn broadcast() void {
        spglib_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return spglib_rt_thread_self();
    }
};

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "spglib";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated header, not from this file.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        /// One resolved address into one optional table field, and the empty
        /// case beside it. Both index `optional_symbols`, not `symbols`.
        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// The library-specific checks, run after every symbol resolved and
        /// before anything is published.
        ///
        /// Every call here takes nothing and returns by value or by copy, so
        /// none of them needs a cell, allocates through the provider, or leaves
        /// anything behind for a failed load to clean up. Two of them write the
        /// provider's own thread-local status to `SPGLIB_SUCCESS`
        /// (`src/spglib.c:192`, `:197`, `:202`, `:177`), which is the value a
        /// fresh provider already carries, and the check runs before any caller
        /// code has had the chance to record a failure of its own.
        pub fn validate(dst: *const table) ?[]const u8 {
            const major = dst.spg_get_major_version();
            if (major != dispatch.SPGLIB_MAJOR_VERSION) {
                return validationMessage(
                    "spg_get_major_version() reported {d}, not the {d} this header was " ++
                        "translated from, so this provider was built from a different " ++
                        "source tree than the one these declarations describe",
                    .{ major, @as(c_int, dispatch.SPGLIB_MAJOR_VERSION) },
                );
            }
            const minor = dst.spg_get_minor_version();
            if (minor != dispatch.SPGLIB_MINOR_VERSION) {
                return validationMessage(
                    "spg_get_minor_version() reported {d}, not the {d} this header was " ++
                        "translated from, so this provider was built from a different " ++
                        "source tree than the one these declarations describe",
                    .{ minor, @as(c_int, dispatch.SPGLIB_MINOR_VERSION) },
                );
            }
            const micro = dst.spg_get_micro_version();
            if (micro != dispatch.SPGLIB_MICRO_VERSION) {
                return validationMessage(
                    "spg_get_micro_version() reported {d}, not the {d} this header was " ++
                        "translated from, so this provider was built from a different " ++
                        "source tree than the one these declarations describe",
                    .{ micro, @as(c_int, dispatch.SPGLIB_MICRO_VERSION) },
                );
            }

            if (!matchesCString(dst.spg_get_version(), dispatch.SPGLIB_VERSION)) {
                return "spg_get_version() did not return the version string this header " ++
                    "was translated from, so the provider's own build identity and " ++
                    "these declarations do not come from the same source tree";
            }

            // The by-value struct return. Hall number 1 is P1 and space group 1
            // in the International Tables and is the first row of the built-in
            // table, so nothing here is computed by this build.
            const spgtype = dst.spg_get_spacegroup_type(1);
            if (spgtype.number != 1 or spgtype.hall_number != 1) {
                return validationMessage(
                    "spg_get_spacegroup_type(1) answered space group {d} at Hall number " ++
                        "{d} rather than space group 1 at Hall number 1, so either the " ++
                        "by-value struct return or the field offsets of " ++
                        "SpglibSpacegroupType do not line up with this header",
                    .{ spgtype.number, spgtype.hall_number },
                );
            }
            if (!std.mem.eql(u8, boundedBytes(&spgtype.international_short), "P1")) {
                return validationMessage(
                    "spg_get_spacegroup_type(1) answered the symbol {s} rather than P1, " ++
                        "which is what Hall number 1 is in the International Tables, so " ++
                        "the character arrays inside SpglibSpacegroupType are not at " ++
                        "the offsets this header declares",
                    .{boundedBytes(&spgtype.international_short)},
                );
            }
            return null;
        }
    };
}

/// True when `actual` is `expected` and nothing more.
///
/// `actual` is a pointer into the provider's read-only data. It is walked for at
/// most `expected.len + 1` bytes rather than to its own NUL, so a provider whose
/// string is not terminated where the header says it is fails the check instead
/// of running off the end of a section it does not own.
fn matchesCString(actual: [*c]const u8, expected: []const u8) bool {
    if (actual == null) return false;
    var index: usize = 0;
    while (index < expected.len) : (index += 1) {
        if (actual[index] != expected[index]) return false;
    }
    return actual[expected.len] == 0;
}

/// The bytes of a fixed-width `char` array up to its first NUL, or the whole
/// array when it is unterminated.
///
/// The upstream structs are `char[11]`, `char[20]` and so on, NUL-terminated by
/// convention rather than by construction, so the same rule the facade uses
/// applies here.
fn boundedBytes(field: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, field, 0) orelse field.len;
    return field[0..end];
}

/// One scratch buffer for the load-time messages that carry a number.
///
/// The loader retains nothing but the table and the request, so a message built
/// here only has to outlive the `load` call that returns it. That call is the
/// only writer: `validate` runs inside a load attempt, and two attempts for one
/// configured module never run at once (`runtime/loader.zig`), so the buffer is
/// written once per load and read by the caller of that load. A second SDK in
/// the same process has its own copy of this file and therefore its own buffer.
var message_buffer: [256]u8 = undefined;

/// Render `format` into `message_buffer`.
///
/// The three callers pass two `c_int`s, or two `c_int`s and a slice of at most
/// eleven bytes from a `char[11]`, which always fit. The fallback can therefore
/// only be reached if this file is edited to call it with something else, and it
/// says what happened rather than dropping the check.
fn validationMessage(comptime format: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(&message_buffer, format, args) catch
        "spglib: a load-time check failed and its value could not be printed";
}