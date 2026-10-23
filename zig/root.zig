//! Typed facade over spglib's translated C API; `c` exposes the full header.
//! `Cell` borrows inputs; datasets and owned results require `deinit`; runtime calls require `load` and return Zig errors.

const std = @import("std");

/// Full translated C API; runtime builds use a generated dispatch with the same declarations.
/// Linked calls are direct; runtime calls require `load` first.
pub const c = @import("c");

const rt = @import("rt");

/// True when native symbols require an explicit runtime provider.
/// False for direct linked calls.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// `.path` requires an absolute path; `.system` is a basename, with no fallback.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Errors returned by `load`.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Loads an explicit provider; failures return `LoadError` without publication, and success stays loaded for process life.
/// Same-source calls are idempotent; concurrent same-source calls wait; mismatches and re-entry return `ProviderMismatch` and `ReentrantLoad`; linked builds panic.
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

/// Returns the successful request borrowed for process life, or null before load or in linked builds.
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

pub const Cell = cell_mod.Cell;
pub const OwnedCell = cell_mod.OwnedCell;
pub const allocateCell = cell_mod.allocateCell;

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

pub const getMagneticDataset = magnetic_mod.getMagneticDataset;
pub const getMagneticDatasetWithTensors = magnetic_mod.getMagneticDatasetWithTensors;

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

pub const ErrorCode = error_mod.ErrorCode;
pub const Error = error_mod.Error;
pub const InputError = error_mod.InputError;
pub const lastErrorCode = error_mod.lastErrorCode;
pub const lastError = error_mod.lastError;
pub const errorMessage = error_mod.errorMessage;
pub const toError = error_mod.toError;

pub const Version = version_mod.Version;
pub const getVersion = version_mod.getVersion;
