---
phase: 01-foundation-and-timing-engine
plan: 03
subsystem: scheduler
tags: [scheduler, polling, lifecycle, wake, tests]
requires:
  - phase: 01-foundation-and-timing-engine
    provides: SwiftData models and app shell
provides:
  - Polling scheduler with first-launch, relaunch, and overdue semantics
  - Persisted scheduler state wiring in the shared app model
  - Launch and wake lifecycle integration for menu bar diagnostics
affects: [check-in-flow, idle-handling, menu-bar]
tech-stack:
  added: [Foundation notifications]
  patterns: [Pure scheduler service plus persisted state store]
key-files:
  created:
    - Sources/TempoApp/Scheduler/PollingScheduler.swift
    - Sources/TempoApp/Scheduler/SchedulerClock.swift
    - Sources/TempoApp/Scheduler/SchedulerStateStore.swift
    - Tests/TempoAppTests/PollingSchedulerTests.swift
  modified:
    - Sources/TempoApp/App/TempoAppModel.swift
    - Sources/TempoApp/App/TempoApp.swift
    - Sources/TempoApp/Views/MenuBarRootView.swift
key-decisions:
  - "Kept the scheduler as a pure computation layer that returns snapshots for the observable app model."
  - "Surfaced next check-in and overdue state in the menu bar for Phase 1 diagnostics only."
patterns-established:
  - "Lifecycle events call back into TempoAppModel instead of duplicating scheduler logic in views."
  - "Scheduler tests inject fixed dates for deterministic behavior."
requirements-completed: [POLL-01]
duration: 18min
completed: 2026-03-15
---

# Phase 1: Foundation and Timing Engine Summary

**Deterministic polling scheduler with persisted timing state and launch/wake lifecycle wiring**

## Performance

- **Duration:** 18 min
- **Started:** 2026-03-15T22:18:00Z
- **Completed:** 2026-03-15T22:28:00Z
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments
- Added a polling scheduler that handles first launch, future check-ins, and overdue relaunch/wake cases.
- Wired scheduler state into the shared app model and menu bar diagnostics.
- Added deterministic scheduler tests using fixed dates and clock injection.

## Task Commits

Plan implementation landed in the same consolidated implementation commit because lifecycle wiring and scheduler state share the same root files:

1. **Task 1: Implement the persisted polling scheduler core** - `01c737c`
2. **Task 2: Wire launch and wake behavior into the app lifecycle** - `01c737c`
3. **Task 3: Add deterministic scheduler tests for launch, relaunch, and overdue cases** - `01c737c`

**Plan metadata:** `01c737c` (consolidated implementation commit)

## Files Created/Modified
- `Sources/TempoApp/Scheduler/PollingScheduler.swift` - Encodes the scheduling rules and snapshot output.
- `Sources/TempoApp/Scheduler/SchedulerClock.swift` - Defines the injected clock protocol.
- `Sources/TempoApp/Scheduler/SchedulerStateStore.swift` - Wraps persisted scheduler state access.
- `Sources/TempoApp/App/TempoAppModel.swift` - Publishes next check-in and overdue state from persisted records.
- `Sources/TempoApp/App/TempoApp.swift` - Hooks launch and wake-related lifecycle transitions into the app.
- `Sources/TempoApp/Views/MenuBarRootView.swift` - Displays next check-in and overdue diagnostics.
- `Tests/TempoAppTests/PollingSchedulerTests.swift` - Covers first launch, future relaunch, and overdue wake cases.

## Decisions Made
- Kept the scheduler logic independent from SwiftUI so later prompt and idle phases can reuse it without rework.
- Preserved quiet launch behavior by surfacing scheduler state in the menu bar instead of opening windows automatically.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Lifecycle and scheduler state require the same app shell files**
- **Found during:** Plan execution
- **Issue:** The scheduler integration spans `TempoApp.swift`, `TempoAppModel.swift`, and `MenuBarRootView.swift`, which were already introduced earlier in the phase.
- **Fix:** Applied the final lifecycle wiring directly to the shared files and documented the overlap instead of splitting the same lines into noisy follow-up commits.
- **Files modified:** Sources/TempoApp/App/TempoApp.swift, Sources/TempoApp/App/TempoAppModel.swift, Sources/TempoApp/Views/MenuBarRootView.swift
- **Verification:** Static review against plan acceptance criteria
- **Committed in:** `01c737c`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** No scope change. The deviation only affects how the greenfield work was grouped in git.

## Issues Encountered
- `swift build` and `swift test` remain blocked by the missing local Swift toolchain.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- The timing model is available for the Phase 2 check-in prompt.
- Once Swift is installed, the scheduler and persistence tests should be executed before moving forward.

---
*Phase: 01-foundation-and-timing-engine*
*Completed: 2026-03-15*
