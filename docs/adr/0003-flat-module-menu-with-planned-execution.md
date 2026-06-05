# Flat module menu with planned execution

OS Init keeps a flat module menu as the primary user experience because the user wants direct control over what is selected. The execution order is not the selection order: OS Init should derive an execution plan that adds strong dependencies automatically, keeps soft associations as prompts, and runs work in a stable platform-aware order.

**Considered Options**

- Replace the module menu with scenario-based startup wizards.
- Execute modules exactly in the order users selected them.
- Keep flat selection but let the tool plan dependencies and execution order.

**Consequences**

- Modules should be strongly grouped by system and purpose but not ranked as recommended, advanced, or high-risk in the menu.
- Strong dependencies must be automatic because the selected module would otherwise be broken.
- Soft associations belong on the confirmation page and summary, not as automatic selections.
