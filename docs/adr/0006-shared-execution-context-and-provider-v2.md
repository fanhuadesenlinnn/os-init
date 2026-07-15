# Share one execution engine and version the provider protocol

OS Init uses one Go execution use case for both the TUI and headless CLI. A
planned module is the unit of execution, timeout, cancellation, verification,
reporting, and state recording. Frontends adapt progress and presentation but
do not implement separate execution semantics.

Go detects the platform and target user once and passes a versioned runtime
context to providers. Shell modules retain standalone detection as a fallback,
but provider execution treats the Go context and already-loaded configuration
as authoritative.

Provider protocol v2 emits machine-readable JSON Lines events with a reserved
prefix. Human-readable module output remains unchanged and is kept separate
from protocol events. Execution records use a versioned JSON schema and atomic,
private files under the target user's OS Init state directory.

Catalog domains may use dedicated builders, but every module lifecycle must be
explicit. Catalog validation rejects missing scripts, duplicate IDs, unknown
dependencies, and invalid lifecycle declarations.

## Consequences

- TUI and automation have the same per-module timeout and verification rules.
- New provider fields can be added without parsing localized log messages.
- Go and Shell no longer make independent platform/configuration decisions
  during normal provider execution.
- Third-party module packs remain out of scope until trust and signing policy is
  defined; the versioned context, catalog validation, and provider protocol are
  prerequisites for that future work.
