// Public Zig surface of the spglib fork.
//
// Two ways in:
//   * `pub const c` is the complete translated include/spglib.h, including the
//     k-point mesh routines the facade does not wrap. Nothing is filtered out.
//   * The declarations below are a thin typed facade over that C API. It
//     re-implements no upstream algorithm; it only carries pointers, counts and
//     status codes across the FFI boundary with checked conversions.
//
// Ownership: `Dataset` and `MagneticDataset` own memory that spglib allocated
// with `malloc` and release it through `deinit`, which calls the matching
// `spg_free_*`. `OwnedCell` and `Symmetry` own Zig allocations and release them
// with the allocator they were created with. Borrowed slices never outlive
// their owner.
//
// Build constraint, Zig 0.16.0 at `-O Debug`: a call to an `extern "C"`
// function that spills an argument onto the stack, which is any call with
// seven or more integer-class arguments, also mis-assigns that same call's
// floating-point arguments. Zig loads the constants into xmm6 and xmm7 where
// the callee reads xmm0 and xmm1, so the tolerance never arrives. Spilled
// integers are correct, which is why `spg_get_stabilized_reciprocal_mesh`,
// nine integer arguments and no double, answers correctly from Zig while
// `spg_get_ir_reciprocal_mesh`, nine integer arguments and one double, does
// not. Every entry point that reaches `get_dataset` with a tolerance is on the
// wrong side of that line, so the Zig caller for this module must not be
// compiled at `-O Debug`; build.zig routes it through `zigCallerOptimize`. A C
// caller against the same archive is correct in both modes, which is what
// makes this a compiler defect rather than a defect in these bindings.

const std = @import("std");

/// Complete translated C declarations from include/spglib.h.
pub const c = @import("c");

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
