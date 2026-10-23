# Typed Zig facade

Assume the module is imported as `spglib`.

## Cells and datasets

```zig
const cell = spglib.Cell{
    .lattice = .{
        .{ 3.9, 0, 0 },
        .{ 0, 3.9, 0 },
        .{ 0, 0, 3.9 },
    },
    .positions = &.{.{ 0, 0, 0 }},
    .types = &.{1},
};
const dataset = try spglib.getDataset(cell, 1e-5);
defer dataset.deinit();
const number = dataset.spacegroupNumber();
```

`Cell` is a borrowed input: lattice vectors are columns, positions are fractional, and `types` is one integer per atom. The caller keeps all three fields alive and unchanged for each call. Helpers include `atomCount`, `validate`, `volume`, `length`, `angle`, `column` and `toCartesian`.

| API | Result |
|---|---|
| `allocateCell(allocator, capacity)` | Allocates an `OwnedCell`; `asCell()` borrows its buffers. |
| `getDataset(cell, symprec)` | Default-angle symmetry search. Returns an owned `Dataset`. |
| `getDatasetWithHallNumber(cell, hall_number, symprec)` | Search for a setting; Hall number `0` selects the default search. |
| `getDatasetWithAngleTolerance(cell, symprec, angle_tolerance)` | Search with angle tolerance in degrees; `-1.0` selects the library default. |
| `standardizeCell(allocator, cell, options)`, `findPrimitive(allocator, cell, symprec)`, `refineCell(allocator, cell, symprec)` | Return an allocator-owned `OwnedCell`; the input remains unchanged. |
| `niggliReduce(&lattice, symprec)` | Reduces the lattice in place on success. |

`StandardizeOptions` has `to_primitive` (default `true`), `no_idealize` (default `false`) and `symprec`. `Dataset` provides space-group metadata, transformation data, and borrowed operation and atom-mapping slices. Those slices expire at `deinit`.

## Magnetic symmetry

* `getMagneticDataset(cell, spins, symprec)` takes one scalar spin per atom.
* `getMagneticDatasetWithTensors(cell, tensors, options)` accepts `MagneticTensorOptions`: rank 0 has one value per atom; rank 1 has three. Other ranks and mismatched slice lengths return `InputError` before the C call.
* `MagneticDataset` provides magnetic-space-group identifiers, operations, standardised-cell data and `timeReversals()` (0 or 1 per operation). Its slices expire at `deinit`.

## Symmetry and database lookups

* `getSymmetry(allocator, cell, symprec, max_operations)` returns allocator-owned `Symmetry`; a short buffer is an error, not a truncated result.
* `getSymmetryFromDatabase(allocator, hall_number)` returns the stored operations for a Hall number.
* `getPointGroup(rotations)`, `getSpacegroupType(hall_number)` and `getMagneticSpacegroupType(uni_number)` return copied values.
* `gridPointFromAddress(address, mesh)` returns the mesh index. Addresses outside the mesh are folded onto their mesh point; mesh entries must be positive.

`Operations` is a view of rotation and translation slices. `Dataset`, `MagneticDataset`, and `Symmetry` are single-owner handles: call `deinit` once, and do not deinit a copied handle. Dataset handles free through spglib; `OwnedCell` and `Symmetry` free through the allocator passed to their constructor. `PointGroup`, `SpacegroupType`, and `MagneticSpacegroupType` contain copied values and need no release. `Version` copies numeric fields; its string slices borrow static library storage. Do not replace either dataset handle's public `raw` pointer: accessors read it and `deinit` frees it.

## Errors and status

`ErrorCode` mirrors the C status enum; `toError(code)` maps it to `Error`. Facade calls return `Error` for a recorded spglib failure and `InputError` for validation before the C call; allocating calls can also return `std.mem.Allocator.Error`. `Error` includes `ArraySizeShortage`. `InputError` covers empty or mismatched cells, invalid counts, tensor shape/rank, nonpositive `symprec`, invalid Hall/UNI numbers, and unsafe mesh/address values.

`lastErrorCode()` and `lastError()` read the current thread's diagnostic; read it immediately after a failed call because any later successful call clears it. `errorMessage(code)` returns `null` when no message exists. `getVersion()` returns the library version.

## Runtime loading and C access

`runtime_loaded` identifies the build configuration. `LoadSource` selects an explicit `.path` or `.system` request; `LoadError` reports failures. `load(source)` returns `LoadError!void` in a runtime-loading build; `loadedSource()` reports the successful request or `null`. Calling `load` in a linked build panics.

`spglib.c` exposes the translated C header. The raw standardize, find-primitive and refine-cell C entry points (including their `spgat_` forms) can write the lattice and types; pass writable copies. The typed facade handles these writes in its returned `OwnedCell`.
