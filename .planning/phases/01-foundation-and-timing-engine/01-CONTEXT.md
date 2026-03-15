# Phase 1: Foundation and Timing Engine - Context

**Gathered:** 2026-03-15
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase establishes the native macOS menu bar app shell, local persistence, project and settings models, and the polling scheduler that determines when the next check-in is due. It does not deliver the actual check-in popup flow, analytics implementation, delay execution, or idle reconciliation behavior beyond storing the settings needed for those later phases.

</domain>

<decisions>
## Implementation Decisions

### App shape
- Tempo should be menu-bar-driven for everyday use.
- Phase 1 should still include a general native app window shell so later phases have a proper place for analytics and other larger views.
- Settings should be managed through a menu bar popover, not a dedicated settings window in this phase.

### Persistence model
- Use SwiftData for local persistence in v1.
- Keep the storage model local-only and app-private; no cloud or network assumptions.
- Choose the simplest persistence structure that supports reliable local state and future analytics.

### Project management workflow
- Project management in Phase 1 should be bare-bones and functional, not polished.
- Users should be able to add, rename, and delete projects from the management UI.
- Deletion must be blocked once a project has tracked time associated with it.

### Scheduler behavior
- The first check-in should occur one full interval after app launch.
- If the app wakes or relaunches after a check-in became overdue, it should prompt immediately.
- Elapsed time should cover the full accountable period by default; later idle handling phases will carve out idle and locked time.
- The menu bar should show only the time remaining until the next check-in.

### Settings defaults
- Delay presets should default to 15 and 30 minutes.
- App relaunch or login launch should start quietly in the menu bar.

### Claude's Discretion
- Exact structure of the general app window shell, as long as it is minimal and reusable for later phases.
- Exact layout and wording of the bare-bones project management controls.
- Exact internal model boundaries for scheduler state versus persisted settings, as long as they preserve the polling semantics above.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Planning artifacts
- `.planning/PROJECT.md` — Product vision, constraints, core value, and locked project-level decisions.
- `.planning/REQUIREMENTS.md` — Phase-linked requirements for menu bar app, local storage, projects, and settings.
- `.planning/ROADMAP.md` — Phase 1 goal, requirements mapping, success criteria, and plan scaffolding.
- `.planning/STATE.md` — Current project status and active phase reference.

### Phase requirements
- `.planning/REQUIREMENTS.md` — `PROJ-01`, `PROJ-04`, `POLL-01`, `DELY-02`, `MENU-01`, `SETG-01`, `SETG-02`, `SETG-03`, `DATA-01`, `DATA-02` define the required scope for this phase.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- No application code exists yet; Phase 1 will establish the initial reusable app shell and persistence foundation.

### Established Patterns
- No existing code patterns are present yet.
- Project-level decisions already constrain the stack to native macOS, Swift, SwiftUI, and local-only persistence.

### Integration Points
- Phase 1 creates the base menu bar app, general window shell, settings popover, persistence layer, and scheduler state that all later phases will build on.

</code_context>

<specifics>
## Specific Ideas

- Menu bar is the primary product surface, but analytics later need a real app window rather than trying to fit everything into a popover.
- The app should stay quiet on launch and in general operation.
- Bare-bones project/settings management is preferred over polished workflows in the first phase.

</specifics>

<deferred>
## Deferred Ideas

- Actual analytics views and project time breakdowns belong to Phase 5.
- Delay execution behavior belongs to Phase 3; Phase 1 only defines the stored presets.
- Idle detection and idle-time reconciliation belong to Phase 4.

</deferred>

---
*Phase: 01-foundation-and-timing-engine*
*Context gathered: 2026-03-15*
