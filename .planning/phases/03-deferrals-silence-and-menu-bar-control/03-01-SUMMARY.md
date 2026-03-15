---
phase: 03-deferrals-silence-and-menu-bar-control
plan: 01
subsystem: scheduler
tags: [scheduler, deferrals, swiftdata, prompt, tests]
requires:
  - phase: 02-check-in-logging-flow
    provides: Persisted check-in completion flow and prompt project selection
provides:
  - Delay-aware scheduler state with persisted deferral windows
  - Prompt delay actions driven by configured presets
  - Deterministic delay scheduling and no-write regression coverage
affects: [scheduler, menu-bar, silence-mode]
tech-stack:
  added: []
  patterns: [Scheduler result carries all prompt-state transitions so app model writes one canonical state shape]
key-files:
  created: []
  modified:
    - Sources/TempoApp/Scheduler/PollingScheduler.swift
    - Sources/TempoApp/Scheduler/SchedulerStateStore.swift
    - Sources/TempoApp/Models/SchedulerStateRecord.swift
    - Sources/TempoApp/App/TempoAppModel.swift
    - Sources/TempoApp/Features/CheckIn/CheckInPromptContent.swift
    - Tests/TempoAppTests/PollingSchedulerTests.swift
    - Tests/TempoAppTests/CheckInCompletionTests.swift
key-decisions:
  - "Persisted both delayed-until and original prompt-reference timestamps so delayed prompts can resume with the full accountable time block intact."
  - "Kept delay actions out of the completion path so postponement never creates a TimeEntryRecord."
patterns-established:
  - "Prompt delay buttons read directly from AppSettingsRecord.delayPresetMinutes so UI options stay user-configurable."
  - "Delayed prompts are hidden in UI but continue using the original accountable reference once the delay expires."
requirements-completed: [POLL-07, DELY-01, DELY-03]
duration: 8min
completed: 2026-03-16
---

# Phase 3: Deferrals, Silence, and Menu Bar Control Summary

**Prompt deferrals now persist delay windows, hide overdue prompts immediately, and re-surface the same accountable work block when the delay expires**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-16T00:03:00+0100
- **Completed:** 2026-03-16T00:17:16+0100
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments
- Added persisted delay fields and richer scheduler snapshots/results for delayed prompt handling.
- Added prompt delay actions that use configured delay presets and dismiss the prompt without writing time.
- Added deterministic tests covering delay scheduling, delay expiry, and no-write behavior.

## Task Commits

Plan implementation landed in one consolidated commit because scheduler state, prompt wiring, and tests all share the same delay path:

1. **Task 1: Extend scheduler state with explicit delay semantics** - `dbfb975`
2. **Task 2: Add delay actions to the prompt and app model** - `dbfb975`
3. **Task 3: Add tests for delayed prompt scheduling and no-write behavior** - `dbfb975`

## Files Created/Modified
- `Sources/TempoApp/Scheduler/PollingScheduler.swift` - Adds delay-aware scheduler transitions and carried prompt state.
- `Sources/TempoApp/Scheduler/SchedulerStateStore.swift` - Persists new delay fields from scheduler results.
- `Sources/TempoApp/Models/SchedulerStateRecord.swift` - Stores delayed-until and delayed-from prompt timestamps.
- `Sources/TempoApp/App/TempoAppModel.swift` - Exposes delay actions and applies delayed scheduler results.
- `Sources/TempoApp/Features/CheckIn/CheckInPromptContent.swift` - Renders preset-based delay buttons inside the prompt.
- `Tests/TempoAppTests/PollingSchedulerTests.swift` - Verifies delay scheduling and overdue re-entry after expiry.
- `Tests/TempoAppTests/CheckInCompletionTests.swift` - Verifies delay actions do not create time entries.

## Decisions Made
- Stored the original prompt reference separately from the delayed deadline so overdue elapsed time remains correct after deferral.
- Reused the scheduler-result application path for delay updates to keep persistence behavior identical across lifecycle refresh and prompt actions.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Silence mode can build on the same scheduler result shape and persistence plumbing added for delays.
- Menu-bar status can now distinguish ordinary next-check-in state from delayed prompts.

---
*Phase: 03-deferrals-silence-and-menu-bar-control*
*Completed: 2026-03-16*
