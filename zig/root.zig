//! Crystal symmetry for upstream spglib, wrapped as a typed Zig facade over
//! the complete translated `include/spglib.h`.
//!
//! Two ways in, and both come from this one module:
//!
//!   * `pub const c` is the unfiltered translation of `include/spglib.h`,
//!     the k-point mesh routines, the deprecated compatibility entry points
//!     and the magnetic database lookups included. Nothing is filtered out.
//!   * The declarations below are a thin typed facade over that same C API.
//!     It re-implements no upstream algorithm; it carries pointers, counts
//!     and status codes across the FFI boundary with checked conversions.
//!
//! Shortest useful sequence: build a `Cell` over slices the caller owns, call
//! `getDataset` with a positive `symprec`, read the answer, and release the
//! dataset with `deinit`. The cell's slices only have to outlive the call that
//! reads them; spglib copies what it needs, and the dataset borrows nothing
//! from them afterwards.
//!
//! ```zig
//! const std = @import("std");
//! const spglib = @import("spglib");
//!
//! pub fn main() !void {
//!     const cell = spglib.Cell{
//!         .lattice = .{ .{ 3.905, 0, 0 }, .{ 0, 3.905, 0 }, .{ 0, 0, 3.905 } },
//!         .positions = &.{ .{ 0, 0, 0 }, .{ 0.5, 0.5, 0.5 } },
//!         .types = &.{ 1, 2 },
//!     };
//!     const dataset = try spglib.getDataset(cell, 1e-5);
//!     defer dataset.deinit();
//!     std.debug.print("{d} {s}\n", .{ dataset.spacegroupNumber(), dataset.internationalSymbol() });
//! }
//! ```
//!
//! Ownership: `Dataset` and `MagneticDataset` own memory that spglib allocated
//! with `malloc`, and `deinit` releases it through the matching `spg_free_*`.
//! `OwnedCell` and `Symmetry` own Zig allocations and release them with the
//! allocator they were created with. Both regimes are single-owner: a copied
//! handle names the same allocation, so `deinit` runs exactly once per value
//! produced, on one copy only. Borrowed slices never outlive their owner.
//!
//! A `Dataset` is released by the *provider* that produced it, which in a
//! runtime-loading build is the one library `load` opened. There is one table
//! per configured module for the life of the process and no second provider, so
//! a dataset this module hands out and this module frees cannot cross a
//! provider boundary. That is what makes the ownership rule hold rather than a
//! convention; `runtime/library.zig` states the rest of the ABI boundary.
//!
//! The typed surface is a subset of `c`, not a filter over it. This is the
//! whole of what it leaves behind; line numbers are `include/spglib.h`.
//!
//! Still current upstream and without a facade function: the lattice reduction
//! `spg_delaunay_reduce` (:480) and the non-dense
//! `spg_get_grid_point_from_address` (:491); the four standardisation
//! declarations that take no angle tolerance, `spg_standardize_cell` (:437),
//! `spg_find_primitive` (:454), `spgat_find_primitive` (:458) and
//! `spg_refine_cell` (:469); `spgat_get_dataset_with_hall_number` (:239); the
//! collinear-spin searches (:261,267,273), the site-tensor searches
//! (:301,308,316), the symmetry-to-type searches (:341,345) and the magnetic
//! operation-database lookup (:420); and the reciprocal-mesh constructors
//! (:512,517,531,535), the grid-points-by-rotations family
//! (:544,547,551,555) and the Brillouin-zone relocation pair (:582,587).
//!
//! The deprecated `spg_get_layer_dataset` (:212),
//! `spg_get_hall_number_from_symmetry` (:327) and the multiplicity,
//! international and Schoenflies pairs are listed with their replacements in
//! README.zig.md.
//!
//! The typed surface does expose grid-address mapping, magnetic type metadata
//! and the native-deprecated allocator-backed `getSymmetry`; see their
//! contracts and README.zig.md.
//!
//! Toolchain limit: FORK-NOTES.md entry 30 records wrong floating-point
//! arguments in Zig 0.16.0 Debug on x86_64-linux-gnu for calls combining at
//! least seven integer-class arguments with a `double`. The same probes passed
//! from C and from ReleaseSafe Zig. Pure-integer calls and `spg_get_dataset`
//! did not show that failure. The register-level cause was not established.
//! `zigCallerOptimize` therefore selects ReleaseSafe for this graph's Zig
//! callers when Debug is requested; the C library keeps the requested mode.
//! Raw-C callers outside this graph must account for that compiler limit.
//! This is the recorded configuration, not a claim about other toolchains.

const std = @import("std");

/// Complete translated C declarations from include/spglib.h.
///
/// In a runtime-loading build this is a generated dispatch instead of the
/// translation step's own output. It publishes the same namespace: every type
/// and constant is re-exported from the translated header rather than
/// restated, so `c.SpglibDataset` is the same nominal type either way and
/// nothing here needs a cast. What differs is how a name reaches the library. In
/// the linked configuration it is a direct call; in the runtime-loaded one it is
/// a call through a table that `load` fills, and a call before that fill stops
/// the program with a message naming the function. `runtime_loaded` says which
/// configuration this build is, at comptime.
pub const c = @import("c");

/// The loader core, which is where a linked build's two public types come from.
///
/// It is imported only by the linked configuration. In a runtime-loading build
/// the dispatch carries its own copy of the same declarations, and this module
/// is never referenced, so it is never resolved and never compiled. Either way
/// there is exactly one `LoadSource` and one `LoadError` in a build, which is
/// what keeps them one type for a consumer that names them.
const rt = @import("rt");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where the C library is linked and `c` is the
/// translated header itself. True when the build generated a dispatch that
/// resolves the same symbols through the platform loader, in which case `load`
/// is the call that makes the library usable.
///
/// It is a comptime constant, so a consumer can write two different code paths
/// and have only the one it chose analyzed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open.
///
/// `.path` is an explicit file path and `.system` is an explicit name for the
/// platform loader. There is no path-to-system fallback and no implicit
/// fallback of any kind; a request that cannot be honoured is an error, not a
/// different library.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
///
/// Declared here, in the module a consumer imports, rather than only inside the
/// loader: the caller names the failure it is handling.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the native library this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then
/// use this module as if it were linked. Calling it again with the same request
/// succeeds and changes nothing; calling it with a different request after a
/// success is `ProviderMismatch`, and the library already in use stays in use.
/// A failed attempt publishes nothing and can be retried explicitly, by
/// calling this again: there is no automatic retry, and no implicit second
/// source.
///
/// It keeps the process handle and its own copy of the request to the end of
/// the process. There is no unload and no reset, because the table is
/// process-global state that other code may already have called through.
///
/// Safe to call from any thread. A thread that arrives while an attempt for
/// the same request is in flight waits for that attempt and gets its result,
/// whatever it was. A call from the thread that is running the attempt is
/// `ReentrantLoad` rather than a deadlock.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly
/// succeeding. `runtime_loaded` is false there, so a consumer that supports
/// both configurations can tell the two apart at comptime instead of meeting
/// this at run time.
pub fn load(source: LoadSource) LoadError!void {
    if (comptime !runtime_loaded) {
        std.debug.panic(
            "spglib: load was called on a linked build; this module is not " ++
                "runtime-loaded, so there is no library to load. Build with " ++
                "runtime loading configured, or do not call load.",
            .{},
        );
    }
    return c.load(source);
}

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life of
/// the process. Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

const cell_mod = @import("cell.zig");
const dataset_mod = @import("dataset.zig");
const error_mod = @import("error.zig");
const magnetic_mod = @import("magnetic.zig");
const symmetry_mod = @import("symmetry.zig");
const version_mod = @import("version.zig");

// Cells ----------------------------------------------------------------------

pub const Cell = cell_mod.Cell;
pub const OwnedCell = cell_mod.OwnedCell;
pub const allocateCell = cell_mod.allocateCell;

// Datasets -------------------------------------------------------------------

pub const Dataset = dataset_mod.Dataset;
pub const MagneticDataset = magnetic_mod.MagneticDataset;
pub const MagneticTensorOptions = magnetic_mod.TensorOptions;
pub const StandardizeOptions = dataset_mod.StandardizeOptions;

pub const getDataset = dataset_mod.getDataset;
pub const getDatasetWithHallNumber = dataset_mod.getDatasetWithHallNumber;
pub const getDatasetWithAngleTolerance = dataset_mod.getDatasetWithAngleTolerance;
pub const standardizeCell = dataset_mod.standardizeCell;
pub const findPrimitive = dataset_mod.findPrimitive;
pub const refineCell = dataset_mod.refineCell;
pub const niggliReduce = dataset_mod.niggliReduce;

// Magnetic symmetry ----------------------------------------------------------

pub const getMagneticDataset = magnetic_mod.getMagneticDataset;
pub const getMagneticDatasetWithTensors = magnetic_mod.getMagneticDatasetWithTensors;

// Symmetry operations, point groups and space-group types --------------------

pub const Operations = symmetry_mod.Operations;
pub const Symmetry = symmetry_mod.Symmetry;
pub const PointGroup = symmetry_mod.PointGroup;
pub const SpacegroupType = symmetry_mod.SpacegroupType;
pub const MagneticSpacegroupType = symmetry_mod.MagneticSpacegroupType;

pub const getSymmetry = symmetry_mod.getSymmetry;
pub const getSymmetryFromDatabase = symmetry_mod.getSymmetryFromDatabase;
pub const getPointGroup = symmetry_mod.getPointGroup;
pub const getSpacegroupType = symmetry_mod.getSpacegroupType;
pub const getMagneticSpacegroupType = symmetry_mod.getMagneticSpacegroupType;
pub const gridPointFromAddress = symmetry_mod.gridPointFromAddress;

// Status and build identity --------------------------------------------------

pub const ErrorCode = error_mod.ErrorCode;
pub const Error = error_mod.Error;
pub const InputError = error_mod.InputError;
pub const lastErrorCode = error_mod.lastErrorCode;
pub const lastError = error_mod.lastError;
pub const errorMessage = error_mod.errorMessage;
pub const toError = error_mod.toError;

pub const Version = version_mod.Version;
pub const getVersion = version_mod.getVersion;
