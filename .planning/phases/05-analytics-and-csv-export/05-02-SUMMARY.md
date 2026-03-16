---
phase: 05-analytics-and-csv-export
plan: 02
subsystem: ui
tags: [analytics, charts, swiftui, window-shell, tests]
requires:
  - phase: 05-analytics-and-csv-export
    provides: Shared analytics snapshot state in TempoAppModel
provides:
  - Main-window analytics screen with period switching and summary cards
  - Charted project allocation and percentage breakdown UI
  - Source-level presentation tests for the analytics entry point and copy
affects: [analytics-ui, app-window, charts]
tech-stack:
  added: []
  patterns: [AnalyticsView renders only app-model snapshot state and avoids direct persistence reads]
key-files:
  created:
    - Sources/TempoApp/Features/Analytics/AnalyticsView.swift
    - Sources/TempoApp/Features/Analytics/AnalyticsChartSection.swift
    - Tests/TempoAppTests/AnalyticsPresentationTests.swift
  modified:
    - Sources/TempoApp/Views/AppWindowShellView.swift
    - Sources/TempoApp/App/TempoAppModel.swift
    - Tests/TempoAppTests/TempoAppBootstrapTests.swift
key-decisions:
  - "Replaced the shell placeholder with a dedicated analytics screen instead of embedding reporting into the menu bar."
  - "Kept the UI order review-first: period selector, headline metrics, chart, then breakdown rows."
patterns-established:
  - "AnalyticsView binds through TempoAppModel.selectAnalyticsRange(_:) so snapshot refresh stays centralized."
  - "Project allocation rows always pair formatted duration with percent-of-total and entry counts."
requirements-completed: [ANLY-01, ANLY-02, ANLY-03, ANLY-04, ANLY-05, ANLY-06]
duration: 10min
completed: 2026-03-16
---

# Phase 5: Analytics and CSV Export Summary

**Tempo now has a real analytics screen in the main window with period switching, summary metrics, project allocation charts, and breakdown rows**

## Performance

- **Duration:** 10 min
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments
- Replaced the analytics placeholder in `AppWindowShellView` with a dedicated `AnalyticsView`.
- Added segmented range switching, period labels, total tracked and top-project summary cards, and a donut-style project allocation chart.
- Added presentation tests that lock in the analytics entry point, critical picker labels, section title, and empty-state copy.

## Task Commits

This plan was executed in one verified implementation pass in the current workspace without task-level git commits.

## Files Created/Modified
- `Sources/TempoApp/Features/Analytics/AnalyticsView.swift` - Renders the analytics screen, summary cards, empty state, and project breakdown.
- `Sources/TempoApp/Features/Analytics/AnalyticsChartSection.swift` - Renders project allocation with `Charts`.
- `Sources/TempoApp/Views/AppWindowShellView.swift` - Routes `.analytics` to the finished analytics screen.
- `Sources/TempoApp/App/TempoAppModel.swift` - Exposes formatted analytics helper text for UI rendering.
- `Tests/TempoAppTests/AnalyticsPresentationTests.swift` - Verifies analytics screen copy and shell wiring at the source level.
- `Tests/TempoAppTests/TempoAppBootstrapTests.swift` - Verifies the analytics window section remains part of the app model.

## Decisions Made
- Used a segmented picker with explicit Daily/Weekly/Monthly/Yearly labels to make the reporting range visible at a glance.
- Kept chart rendering isolated in `AnalyticsChartSection` so the screen composition stays simple and CSV work can extend the header controls cleanly.

## Deviations from Plan

None.

## Issues Encountered

None.

## Next Phase Readiness
- The analytics screen has a stable header area where CSV export controls can live without redesign.
- The view now consumes a shared analytics snapshot, so export can mirror the same visible period and totals.

## Self-Check: PASSED

---
*Phase: 05-analytics-and-csv-export*
*Completed: 2026-03-16*
