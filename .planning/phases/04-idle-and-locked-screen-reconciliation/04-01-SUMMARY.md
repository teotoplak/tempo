---
phase: 04-idle-and-locked-screen-reconciliation
plan: 01
subsystem: scheduler
tags: [idle, lock-screen, scheduler, menu-bar, swiftui, tests]
requires:
  - phase: 03-deferrals-silence-and-menu-bar-control
    provides: Delay, silence, and menu-bar scheduling state routed through TempoAppModel
provides:
  - Persisted pending-idle scheduler state with unresolved idle intervals
  - App-model idle and lock lifecycle wiring with menu-bar visibility
  - Deterministic scheduler and bootstrap coverage for idle detection and idle return
affects: [idle-resolution, prompt, scheduler, menu-bar]
tech-stack:
  added: []
  patterns: [Unresolved idle intervals are persisted in scheduler state and surfaced through TempoAppModel before any normal polling resumes]
key-files:
  created: []
  modified:
    - Sources/TempoApp/Models/SchedulerStateRecord.swift
    - Sources/TempoApp/Scheduler/SchedulerStateStore.swift
    - Sources/TempoApp/Scheduler/PollingScheduler.swift
    - Sources/TempoApp/App/TempoAppModel.swift
    - Sources/TempoApp/Views/MenuBarRootView.swift
    - Tests/TempoAppTests/PollingSchedulerTests.swift
    - Tests/TempoAppTests/TempoAppBootstrapTests.swift
key-decisions:
  - "Tracked idle-return visibility through persisted scheduler state so an unresolved idle interval can survive wake, unlock, and relaunch."
  - "Kept idle detection and lock observers in TempoAppModel so lifecycle events stay centralized beside the existing wake and prompt transitions."
patterns-established:
  - "PollingScheduler owns whether idle is pending, whether countdowns are suspended, and when accountable elapsed time must be zero."
  - "TempoAppModel exposes derived idle labels and durations for menu-bar and prompt surfaces instead of letting views inspect persistence directly."
requirements-completed: [IDLE-01, IDLE-02, IDLE-03]
duration: 12min
completed: 2026-03-16
---

# Phase 4: Idle and Locked-Screen Reconciliation Summary

**Pending idle intervals now persist through inactivity, screen locks, wake/unlock transitions, and menu-bar status without resuming active tracking automatically**

## Performance

- **Duration:** 12 min
- **Started:** 2026-03-16T00:23:00+0100
- **Completed:** 2026-03-16T00:31:00+0100
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments
- Added persisted idle interval fields plus scheduler APIs that suspend accountable time and clear conflicting delay/silence state while idle is unresolved.
- Wired inactivity, lock, unlock, and wake events through `TempoAppModel` and exposed explicit idle-pending menu-bar copy.
- Added deterministic tests for idle start, lock handling, and idle-return behavior without rescheduling a normal poll.

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend scheduler state with explicit pending-idle intervals** - `36b76ac` (feat)
2. **Task 2: Wire inactivity and screen-lock events through the app model** - `2727dbb` (feat)
3. **Task 3: Add tests for idle detection, lock transitions, and suspended elapsed time** - `6743bae` (test)

## Files Created/Modified
- `Sources/TempoApp/Models/SchedulerStateRecord.swift` - Adds persisted idle markers and pending-idle interval fields.
- `Sources/TempoApp/Scheduler/SchedulerStateStore.swift` - Persists idle scheduler fields alongside existing poll state.
- `Sources/TempoApp/Scheduler/PollingScheduler.swift` - Adds idle-aware snapshots/results plus begin/return APIs that suspend active tracking.
- `Sources/TempoApp/App/TempoAppModel.swift` - Detects inactivity, handles screen lock/unlock, and derives idle-pending state for the UI.
- `Sources/TempoApp/Views/MenuBarRootView.swift` - Shows the unresolved idle state with explicit "Resolve idle time" copy.
- `Tests/TempoAppTests/PollingSchedulerTests.swift` - Covers idle begin, screen-lock, and idle-return scheduler behavior.
- `Tests/TempoAppTests/TempoAppBootstrapTests.swift` - Covers app-model idle detection and lock handling.

## Decisions Made
- Used persisted `idleResolvedAt` as the signal that the user has returned and the unresolved idle interval should be shown again.
- Kept prompt presentation hidden when idle first begins so detection does not force a UI while the user is away or the screen is locked.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- The prompt layer now has all scheduler and app-model state needed to offer assign, discard, and split idle-resolution actions.
- Idle return already preserves and surfaces the unresolved interval, so phase `04-02` can focus on ledger writes and prompt UX.

## Self-Check: PASSED

---
*Phase: 04-idle-and-locked-screen-reconciliation*
*Completed: 2026-03-16*
