---
phase: 03-deferrals-silence-and-menu-bar-control
plan: 03
subsystem: ui
tags: [menubar, swiftui, analytics, projects, tests]
requires:
  - phase: 03-deferrals-silence-and-menu-bar-control
    provides: Delay and silence state exposed through TempoAppModel
provides:
  - Rich menu-bar status cards for scheduling, current context, and daily totals
  - Quick actions for check-in, analytics, projects, settings, quit, and unsilence
  - Deterministic model/source checks for menu-bar derived state and actions
affects: [menu-bar, analytics, navigation]
tech-stack:
  added: []
  patterns: [Menu-bar views consume derived strings and totals from TempoAppModel instead of querying persistence directly]
key-files:
  created: []
  modified:
    - Sources/TempoApp/App/TempoAppModel.swift
    - Sources/TempoApp/Views/MenuBarRootView.swift
    - Tests/TempoAppTests/PersistenceModelTests.swift
    - Tests/TempoAppTests/TempoAppBootstrapTests.swift
key-decisions:
  - "Derived today's total from entries whose endAt falls on the current local day to match the user's day-boundary expectation."
  - "Kept quick-action validation partly source-based so menu labels remain covered even if the SwiftUI layout shifts later."
patterns-established:
  - "Menu-bar countdown/status copy adapts to delayed, silenced, overdue, and ordinary scheduled states from one model API."
  - "Quick actions switch appModel.selectedWindow before opening the main window so navigation remains state-driven."
requirements-completed: [MENU-02, MENU-03, MENU-04, MENU-05]
duration: 7min
completed: 2026-03-16
---

# Phase 3: Deferrals, Silence, and Menu Bar Control Summary

**The menu bar now shows live scheduling state, latest project context, today's total, and the daily-use actions needed to control Tempo**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-16T00:10:00+0100
- **Completed:** 2026-03-16T00:17:16+0100
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- Added model-derived menu-bar status strings, latest project context, and current-day tracked totals.
- Replaced the placeholder menu bar with status cards and quick actions for check-in, analytics, projects, settings, quit, and unsilence.
- Added deterministic tests for current-day totals, current project context, prompt forcing, and quick-action availability.

## Task Commits

Plan implementation landed in one consolidated commit because model derivations, menu-bar presentation, and action tests all share the same UI contract:

1. **Task 1: Derive menu-bar status, current context, and today's total in the app model** - `dbfb975`
2. **Task 2: Replace the placeholder menu bar with status cards and quick actions** - `dbfb975`
3. **Task 3: Add deterministic tests for menu-bar derived state and actions** - `dbfb975`

## Files Created/Modified
- `Sources/TempoApp/App/TempoAppModel.swift` - Adds derived menu-bar strings, totals, latest-project context, and the `checkInNow()` action.
- `Sources/TempoApp/Views/MenuBarRootView.swift` - Replaces the placeholder menu content with status cards and quick actions.
- `Tests/TempoAppTests/PersistenceModelTests.swift` - Verifies current-day totals and latest-project context derivation.
- `Tests/TempoAppTests/TempoAppBootstrapTests.swift` - Verifies prompt forcing and menu-bar quick-action labels.

## Decisions Made
- Centralized menu-bar-facing text and totals in `TempoAppModel` so the SwiftUI view stays declarative and thin.
- Used a `TimelineView` in the menu bar for minute-level countdown refresh without introducing a separate timer service.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 4 can build idle-state messaging on top of the same menu-bar status surfaces added here.
- Analytics navigation now has an always-on entry point from the menu bar before the full analytics feature lands.

---
*Phase: 03-deferrals-silence-and-menu-bar-control*
*Completed: 2026-03-16*
