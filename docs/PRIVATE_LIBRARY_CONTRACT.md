# Private installable library contract

`com.scenarys.neo-cube` is a private Scenarys component. Applications consume the
opaque C ABI in `include/scenarys/neo_cube.h`; they never include the C++ core or
copy its implementation.

## Compatibility

- Package versions use SemVer. ABI compatibility is tracked independently by
  `SCENARYS_NEO_CUBE_ABI_VERSION` and `package/manifest.json`.
- Adding a function or an enum value without changing existing layout is a minor
  package release. Removing or changing an existing symbol, numeric result code,
  parameter, struct layout, ownership rule, or 1-based coordinate meaning requires
  a new ABI version and a major package release.
- Consumers check `scenarys_neo_cube_abi_version()` before creating a run.
- Every supported application must run the consumer contract tests against the
  exact artifact it ships or installs.

## Ownership and state

- `scenarys_neo_cube_run_create` returns an opaque run owned by the caller.
- The caller must release it exactly once with `scenarys_neo_cube_run_destroy`.
- One handle is confined to one execution context unless a future ABI explicitly
  adds synchronization. Applications synchronize DTOs/events, not raw handles.
- Rows, columns and phases exposed by the ABI are 1-based. `next_phase == 0`
  means the run is complete.

## Cross-application synchronization

The library performs deterministic local calculation only. Scenarys adapters own
identity, persistence, ordering and transport. A synchronized event envelope must
include a schema version, event id, aggregate/run id, monotonic sequence, producer,
engine version and scenario version. Consumers apply events idempotently and reject
gaps or incompatible schema versions. No formula, internal matrix, trace, token or
raw engine state is permitted in an event.

The official company policy may tighten these rules. Until it arrives, releases
remain local and unsigned; no artifact is uploaded or distributed.
