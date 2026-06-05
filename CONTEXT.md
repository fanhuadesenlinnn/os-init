# OS Init Context

OS Init is a China-ready system initialization tool for macOS, general Linux, and minimal Arch Linux installations. This context defines the product language used by users, maintainers, and AI agents when discussing what belongs in the tool.

## Language

**OS Init**:
The cross-platform initialization tool that gives users one entrypoint for preparing macOS, general Linux, and Arch Linux systems.
_Avoid_: kickstart, dotfiles installer, package installer

**Initialization Track**:
A platform-shaped area of the product with its own scope and takeover depth.
_Avoid_: scenario, preset, profile

**macOS Initialization**:
The initialization track for a Mac that is both a development machine and a daily-use personal computer.
_Avoid_: macOS server setup

**General Linux Initialization**:
The initialization track for Linux servers and development environments outside the ArchDevKit flow.
_Avoid_: desktop Linux setup

**ArchDevKit Initialization**:
The initialization track for turning a minimal Arch Linux installation into a complete development environment.
_Avoid_: Arch module pack, Arch add-on

**ArchDevKit**:
The independent large module that owns the Arch Linux full-system initialization logic.
_Avoid_: normal module, Linux submodule

**Module**:
A user-selectable unit of work shown in the flat module menu.
_Avoid_: plugin, package, task

**Application Installation Module**:
A module that installs or updates an application without taking over private accounts, subscriptions, or personal data.
_Avoid_: app setup, account setup

**Template Configuration Module**:
A module that explicitly backs up an existing development or terminal configuration and writes an OS Init template.
_Avoid_: app install, private sync

**Private Application Configuration**:
User-owned account, subscription, privacy, or personal-data configuration that OS Init should not manage by default.
_Avoid_: initialization config

**Flat Module Menu**:
The primary selection model where users choose modules directly from grouped lists.
_Avoid_: scenario wizard, recommendation flow

**Strong Grouping**:
The organization of flat modules into clear system and purpose groups without ranking modules.
_Avoid_: recommended tier, advanced tier

**Strong Dependency**:
A module relationship where the selected module cannot work correctly unless another module is also applied.
_Avoid_: suggestion, nice-to-have

**Soft Association**:
A module relationship where another module often improves the experience but is not required.
_Avoid_: dependency, auto-install

**Execution Plan**:
The ordered set of work derived from selected modules, strong dependencies, and platform rules.
_Avoid_: selection order

**Independent Flow**:
A flow that executes separately from normal OS Init modules and ends at its own summary.
_Avoid_: mixed batch

**Unified Configuration**:
The single OS Init configuration surface shared by all initialization tracks.
_Avoid_: per-tool config, scattered config

**Current-System Configuration Section**:
The portion of unified configuration generated for the operating system where OS Init is first configured.
_Avoid_: universal full config

**Confirmation Page**:
The pre-execution page that explains selected work, required privileges, automatic dependency additions, soft associations, and important affected paths.
_Avoid_: warning wall

**Summary Page**:
The post-execution page that tells the user what succeeded, what failed, what was skipped, and what to do next.
_Avoid_: result list

## Relationships

- **OS Init** has three **Initialization Tracks**: **macOS Initialization**, **General Linux Initialization**, and **ArchDevKit Initialization**.
- **ArchDevKit Initialization** is represented by **ArchDevKit**, which is an **Independent Flow**.
- A **Flat Module Menu** contains **Modules** arranged by **Strong Grouping**.
- **macOS Initialization** may include **Application Installation Modules** and explicit **Template Configuration Modules**.
- **Private Application Configuration** stays outside normal **Application Installation Modules**.
- **Strong Dependencies** are added to the **Execution Plan** automatically.
- **Soft Associations** are shown on the **Confirmation Page** but are not automatically added.
- **Unified Configuration** contains common settings and one or more **Current-System Configuration Sections**.
- The **Summary Page** follows both normal **Execution Plans** and **Independent Flows**.

## Example Dialogue

> **Dev:** "Should we put ArchDevKit proxy next to the normal Mihomo module?"
> **Domain expert:** "No. **ArchDevKit** is an **Independent Flow** for **ArchDevKit Initialization**. The normal Mihomo **Module** belongs to **General Linux Initialization**."

> **Dev:** "If the user selects a zsh plugin without zsh, should we suggest zsh?"
> **Domain expert:** "That is a **Strong Dependency**, so it belongs in the **Execution Plan** automatically. Suggestions are only for **Soft Associations**."

## Flagged Ambiguities

- "Arch module" was used to mean both a normal Linux module on Arch and the Arch full-system initializer. Resolved: use **Module** for normal selectable work and **ArchDevKit** for the independent full-system initializer.
- "Scenario" was considered for startup UX, but the chosen model is **Flat Module Menu** with **Strong Grouping**.
- "Config" was used for OS Init and ArchDevKit separately. Resolved: users face **Unified Configuration**; ArchDevKit may still keep internal configuration mechanics behind its independent flow.
