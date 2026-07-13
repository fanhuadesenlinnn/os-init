# Separate catalog roles and use one provider boundary

OS Init keeps one flat selection surface, but a selectable entry is now one of
three explicit roles:

- A module is a stateful capability with declared lifecycle operations and a
  composable verification expression.
- A preset is a dependency-only composition and never reaches the executor.
- An action is a one-shot diagnostic or status command and cannot be mixed
  with lifecycle modules in one batch.

The Go control plane owns availability, dependency expansion, lifecycle
validation, stable phase ordering, privilege preview, execution, logs, and
summaries. Shell remains the platform implementation layer. Every script is
invoked through `modules/provider.sh` using a stable script/operation/component
protocol; legacy positional arguments are private implementation details.

Arch-specific code no longer owns a second menu, planner, confirmation flow,
runner, or summary. It retains pacman/systemd/workstation implementation,
configuration validation, diagnostics, and configuration-fingerprint state.

## Consequences

- Unsupported operations are rejected before execution.
- Presets do not need acknowledgement scripts or synthetic installed state.
- Verification grows through nested `All`/`Any` checks instead of new module
  fields.
- Execution order uses language-independent phases and order hints.
- Target-user policy is resolved in the catalog layer rather than the TUI.
- Platform differences and opinionated workstation recipes remain explicit.
