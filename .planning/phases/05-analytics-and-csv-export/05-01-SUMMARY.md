---
phase: 05-analytics-and-csv-export
plan: 01
subsystem: analytics
tags: [analytics, aggregation, swiftdata, app-model, tests]
requires:
  - phase: 04-idle-and-locked-screen-reconciliation
    provides: Idle-adjusted time entries and explicit idle entry sources
provides:
  - Shared analytics domain models for range, period, and project summaries
  - SwiftData-backed aggregation logic for day, week, month, and year snapshots
  - App-model refresh hooks and deterministic aggregation tests
affects: [analytics, app-model, time-ledger]
tech-stack:
  added: []
  patterns: [AnalyticsStore is the single source of truth for analytics period boundaries and grouped summaries]
key-files:
  created:
    - Sources/TempoApp/Features/Analytics/AnalyticsModels.swift
    - Sources/TempoApp/Features/Analytics/AnalyticsStore.swift
    - Tests/TempoAppTests/AnalyticsAggregationTests.swift
  modified:
    - Sources/TempoApp/App/TempoAppModel.swift
key-decisions:
  - "Centralized analytics period math and grouping in AnalyticsStore so later UI and CSV export stay aligned."
  - "Kept analytics snapshot state in TempoAppModel instead of letting views fetch SwiftData directly."
patterns-established:
  - "Analytics range selection updates one cached snapshot with total duration, per-project percentages, and top-project metadata."
  - "Analytics summaries treat nil project links as `Unassigned` so exported and visual totals remain consistent."
requirements-completed: [ANLY-02, ANLY-04, ANLY-05]
duration: 12min
completed: 2026-03-16
---

# Phase 5: Analytics and CSV Export Summary

**Tempo can now compute deterministic local analytics snapshots for daily, weekly, monthly, and yearly reporting from one shared aggregation layer**

## Performance

- **Duration:** 12 min
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- Added analytics domain models for ranges, periods, project summaries, and snapshot payloads.
- Implemented `AnalyticsStore` to derive shared period boundaries, grouped project totals, and percentages from `TimeEntryRecord` rows.
- Wired `TempoAppModel` to refresh analytics after check-ins, idle reconciliation, and project renames, with deterministic aggregation tests covering totals and boundaries.

## Task Commits

This plan was executed in one verified implementation pass in the current workspace without task-level git commits.

## Files Created/Modified
- `Sources/TempoApp/Features/Analytics/AnalyticsModels.swift` - Defines analytics range, period, project summary, and snapshot types.
- `Sources/TempoApp/Features/Analytics/AnalyticsStore.swift` - Computes day/week/month/year periods and grouped project totals from SwiftData.
- `Sources/TempoApp/App/TempoAppModel.swift` - Stores analytics selection state and refreshes snapshots after time-ledger mutations.
- `Tests/TempoAppTests/AnalyticsAggregationTests.swift` - Verifies grouped totals, percentages, and range-refresh behavior.

## Decisions Made
- Kept analytics filtering keyed off `endAt` within a closed-open period window so later consumers share identical inclusion rules.
- Refreshed analytics from app-model mutation points instead of only at window open, preventing stale totals after check-ins or idle resolution.

## Deviations from Plan

None.

## Issues Encountered

None.

## Next Phase Readiness
- The app model now exposes stable analytics snapshot state for a real review screen.
- CSV export can reuse `AnalyticsStore.period(for:referenceDate:calendar:)` so file contents match the visible report.

## Self-Check: PASSED

---
*Phase: 05-analytics-and-csv-export*
*Completed: 2026-03-16*
