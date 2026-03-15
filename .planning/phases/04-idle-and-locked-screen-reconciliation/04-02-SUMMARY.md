---
phase: 04-idle-and-locked-screen-reconciliation
plan: 02
subsystem: ui
tags: [idle, reconciliation, prompt, time-entry, swiftui, tests]
requires:
  - phase: 04-idle-and-locked-screen-reconciliation
    provides: Persisted pending-idle state and idle-return prompt gating
provides:
  - Idle-resolution actions for assign, discard, and split outcomes
  - Prompt UI that blocks ordinary check-in completion while idle is unresolved
  - Ledger-consistency tests for idle resolution and split validation
affects: [time-ledger, prompt, scheduler]
tech-stack:
  added: []
  patterns: [Idle resolution is completed through TempoAppModel so prompt state, scheduler reset, and ledger writes stay atomic]
key-files:
  created: []
  modified:
    - Sources/TempoApp/App/TempoAppModel.swift
    - Sources/TempoApp/Features/CheckIn/CheckInPromptContent.swift
    - Sources/TempoApp/Features/CheckIn/CheckInProjectListView.swift
    - Tests/TempoAppTests/CheckInCompletionTests.swift
    - Tests/TempoAppTests/PersistenceModelTests.swift
    - Tests/TempoAppTests/TempoAppBootstrapTests.swift
key-decisions:
  - "Made project taps selection-only while idle is pending so the user must choose an explicit assign, discard, or split action."
  - "Used the normal scheduler completion path after idle resolution so the next poll always restarts from the current time with idle state fully cleared."
patterns-established:
  - "Idle-resolution entries use explicit `idle-assigned` and `idle-split` sources for downstream analytics and auditability."
  - "Prompt copy switches from the standard check-in headline to idle-resolution copy whenever an unresolved idle interval has returned."
requirements-completed: [IDLE-04, IDLE-05, IDLE-03]
duration: 10min
completed: 2026-03-16
---

# Phase 4: Idle and Locked-Screen Reconciliation Summary

**Tempo now forces explicit reconciliation of returned idle time with assign, discard, and split controls that preserve a contiguous local ledger**

## Performance

- **Duration:** 10 min
- **Started:** 2026-03-16T00:32:00+0100
- **Completed:** 2026-03-16T00:37:00+0100
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments
- Added atomic idle-resolution mutations that write `idle-assigned` or `idle-split` rows, or intentionally discard the interval, before restarting normal polling.
- Reworked the prompt so unresolved idle intervals show "Resolve idle time" with assign, discard, and split controls ahead of ordinary check-in behavior.
- Added deterministic tests for idle-entry writes, split validation, and prompt-title blocking while idle is pending.

## Task Commits

Plan implementation landed in one consolidated feature commit because the ledger actions and prompt contract are coupled in `TempoAppModel`:

1. **Task 1: Add app-model resolution APIs for assign, discard, and split** - `7eb0631`
2. **Task 2: Present the idle-resolution UI before ordinary project check-in** - `7eb0631`
3. **Task 3: Add ledger-consistency tests for idle resolution outcomes** - `6e11518`

## Files Created/Modified
- `Sources/TempoApp/App/TempoAppModel.swift` - Adds idle-resolution actions, selection state, and prompt gating for unresolved idle intervals.
- `Sources/TempoApp/Features/CheckIn/CheckInPromptContent.swift` - Presents the dedicated idle-resolution UI with assign, discard, and split actions.
- `Sources/TempoApp/Features/CheckIn/CheckInProjectListView.swift` - Supports selected-project highlighting while idle resolution is active.
- `Tests/TempoAppTests/CheckInCompletionTests.swift` - Verifies assign, discard, and contiguous split outcomes.
- `Tests/TempoAppTests/PersistenceModelTests.swift` - Verifies split-duration validation rejects out-of-range inputs.
- `Tests/TempoAppTests/TempoAppBootstrapTests.swift` - Verifies idle-resolution copy replaces the standard check-in headline.

## Decisions Made
- Reused the existing prompt project search and ordering so idle resolution inherits the same project-selection behavior as normal check-ins.
- Treated discard as a first-class resolution path that clears scheduler state without writing a time entry, instead of encoding a synthetic "discarded" row.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 5 can trust idle-adjusted entries and explicit idle sources when aggregating analytics and CSV exports.
- The prompt and scheduler now prevent unresolved idle time from leaking into later ordinary check-ins.

## Self-Check: PASSED

---
*Phase: 04-idle-and-locked-screen-reconciliation*
*Completed: 2026-03-16*
