# Phase 2: Check-In Logging Flow - Context

**Gathered:** 2026-03-15
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers the actual check-in experience on top of the existing scheduler: a prominent full-screen prompt, elapsed-time context, project selection from the flat local list, inline project creation inside the prompt, and writing completed time entries silently. Delay, silence controls, idle reconciliation, analytics, and menu bar status expansion remain outside this phase.

</domain>

<decisions>
## Implementation Decisions

### Prompt presentation
- The check-in should appear as a centered card on top of a dimmed full-screen backdrop.
- Most of the screen should remain empty so the prompt has a single focal point.
- The desktop behind the prompt should stay recognizable through the dimming layer.
- The interaction should feel productive and intentional, not urgent or alarm-like.

### Project picking flow
- Existing projects should be shown in a simple vertical list.
- Recently used projects should be pinned at the top of the list.
- Project rows should show the project name only.
- Clicking a project should immediately log the time block and close the prompt without a confirmation step.

### Inline project creation
- The prompt should include a single text field above the project list.
- Typing in the field should filter the existing project list in real time.
- When the typed value does not match an existing project, the UI should show an explicit create action next to the entered name.
- Creating a project from the prompt should immediately log the current elapsed block to that new project.
- Name validation should stay minimal: accept any non-empty trimmed name.

### Completion and timing context
- The main prompt copy should be phrased around the user's current activity: "What are you currently doing".
- The prompt should show elapsed duration only, not a start/end time range.
- After a project is logged, the prompt should close immediately with no extra confirmation UI.
- If the prompt is overdue, the UI should mention that only with subtle supporting text.

### Claude's Discretion
- Exact typography, spacing, and sizing of the centered card and dimming treatment.
- Exact wording around the elapsed-duration subtitle and the subtle overdue copy, as long as the primary prompt stays aligned with the user's direction.
- Exact rule for "recently used" ordering, as long as it is derived from completed check-ins and keeps the full flat list accessible.

</decisions>

<specifics>
## Specific Ideas

- The check-in should feel like a productive interruption rather than a warning or alert.
- The prompt should let the user start typing immediately to either find an existing project or create a new one from the same field.
- The create affordance should be visible right next to unmatched input instead of switching into a separate creation flow.

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Planning artifacts
- `.planning/PROJECT.md` — Product vision, local-only constraints, and silent-operation requirement.
- `.planning/REQUIREMENTS.md` — `PROJ-02`, `PROJ-03`, `POLL-02`, `POLL-03`, `POLL-04`, `POLL-05`, `POLL-06`, and `UX-01` define this phase's required behavior.
- `.planning/ROADMAP.md` — Phase 2 goal, success criteria, and plan scaffolding.
- `.planning/STATE.md` — Current phase status and verification constraints on this machine.
- `.planning/phases/01-foundation-and-timing-engine/01-CONTEXT.md` — Locked product and scheduler decisions from Phase 1.

### Existing application code
- `Sources/TempoApp/App/TempoAppModel.swift` — Owns scheduler snapshot state, project creation hooks, and app-level flow integration points.
- `Sources/TempoApp/Scheduler/PollingScheduler.swift` — Defines `nextCheckInAt`, overdue handling, and accountable elapsed interval semantics that the prompt must display.
- `Sources/TempoApp/Models/ProjectRecord.swift` — Defines the flat project model and persisted ordering.
- `Sources/TempoApp/Models/TimeEntryRecord.swift` — Defines the stored time-entry shape written when a check-in is completed.
- `Sources/TempoApp/Features/Projects/ProjectManagementView.swift` — Shows the current project-list presentation assumptions and editing behavior outside the prompt.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TempoAppModel`: already exposes scheduler state (`nextCheckInAt`, overdue flag, accountable elapsed interval) and project creation methods that Phase 2 can extend.
- `ProjectRecord`: already provides a flat persisted project list with stable `sortOrder`.
- `TimeEntryRecord`: already exists as the persistence target for completed check-ins.
- `AppWindowShellView` and `MenuBarRootView`: existing app surfaces can launch or coexist with the prompt flow without redefining the app shell.

### Established Patterns
- App state is centralized in `TempoAppModel` and persisted through SwiftData singleton records plus model queries.
- Project management is intentionally simple and local-only; Phase 2 should keep the check-in flow equally direct.
- The scheduler already treats elapsed time as the accountable period since the last completed check-in or scheduled boundary.

### Integration Points
- The prompt should be driven from `TempoAppModel` when the scheduler becomes due or overdue.
- Completing a check-in must update both `TimeEntryRecord` persistence and scheduler state so the next polling cycle starts cleanly.
- Inline project creation should reuse the same model-context persistence path as the main project management screen.

</code_context>

<deferred>
## Deferred Ideas

- Delay actions and re-prompt timing belong to Phase 3.
- Silence-for-rest-of-day behavior and related menu bar controls belong to Phase 3.
- Idle/locked-screen reconciliation belongs to Phase 4.
- Analytics and export remain Phase 5 work.

</deferred>

---
*Phase: 02-check-in-logging-flow*
*Context gathered: 2026-03-15*
