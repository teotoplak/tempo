# Roadmap: Tempo

## Overview

The roadmap starts by establishing a reliable native macOS foundation for local persistence, scheduling, and settings, then layers in the core check-in flow that logs time against projects. Once the basic polling loop is trustworthy, the next phases add day-to-day usability controls, protect tracking accuracy during idle periods, surface analytics and export, and finish with launch behavior and end-to-end correctness hardening for a dependable personal tool.

## Phases

- [x] **Phase 1: Foundation and Timing Engine** - Build the native menu bar shell, local data model, settings, and polling engine that define the product’s correctness baseline.
- [ ] **Phase 2: Check-In Logging Flow** - Deliver the full-screen prompt and project-based time attribution flow that turns polling into actual tracked entries.
- [ ] **Phase 3: Deferrals, Silence, and Menu Bar Control** - Add postponement, silence controls, and menu bar status/actions for daily usability.
- [ ] **Phase 4: Idle and Locked-Screen Reconciliation** - Prevent incorrect active tracking during inactivity and let the user resolve idle time explicitly.
- [ ] **Phase 5: Analytics and CSV Export** - Provide reporting views and portable export so tracked data becomes useful for reflection.
- [ ] **Phase 6: Launch and Correctness Hardening** - Finish launch-at-login support and tighten timing and workflow reliability across day boundaries.

## Phase Details

### Phase 1: Foundation and Timing Engine
**Goal**: Establish the native macOS app shell, local persistence, project/settings models, and a dependable polling scheduler that can determine when the next check-in should fire.
**Depends on**: Nothing (first phase)
**Requirements**: [PROJ-01, PROJ-04, POLL-01, DELY-02, MENU-01, SETG-01, SETG-02, SETG-03, DATA-01, DATA-02]
**Success Criteria** (what must be TRUE):
  1. User can launch a native macOS menu bar app that persists projects and settings locally.
  2. User can create projects and manage a flat project list outside the check-in popup.
  3. Polling interval, idle threshold, and delay options are configurable and survive app restarts.
  4. App computes the next scheduled check-in using the configured polling interval with a default of 25 minutes.
**Plans**: 3 plans

Plans:
- [x] 01-01: Set up the SwiftUI menu bar app shell and local persistence foundation.
- [x] 01-02: Implement project and settings data models with editing UI.
- [x] 01-03: Build the polling scheduler and persisted timing state.

### Phase 2: Check-In Logging Flow
**Goal**: Turn the scheduler into a usable check-in experience that captures current work accurately and records elapsed time against projects.
**Depends on**: Phase 1
**Requirements**: [PROJ-02, PROJ-03, POLL-02, POLL-03, POLL-04, POLL-05, POLL-06, UX-01]
**Success Criteria** (what must be TRUE):
  1. When a check-in is due, user sees a prominent full-screen prompt that does not seize overall system input.
  2. Prompt shows the elapsed time since the last completed check-in and the available projects.
  3. User can pick an existing project or create a new one inline from the prompt.
  4. Selecting a project writes the elapsed time block correctly without playing any sound.
**Plans**: 3 plans

Plans:
- [ ] 02-01: Implement the full-screen check-in presentation and timing context display.
- [ ] 02-02: Add project selection and inline project creation inside the prompt.
- [ ] 02-03: Persist completed time entries from check-ins and verify silent behavior.

### Phase 3: Deferrals, Silence, and Menu Bar Control
**Goal**: Add daily-use controls that let the user delay or silence polling while keeping current status visible and accessible from the menu bar.
**Depends on**: Phase 2
**Requirements**: [POLL-07, POLL-08, DELY-01, DELY-03, SILN-01, SILN-02, SILN-03, SILN-04, MENU-02, MENU-03, MENU-04, MENU-05]
**Success Criteria** (what must be TRUE):
  1. User can delay a prompt and the app re-prompts automatically after the chosen duration.
  2. User can silence tracking for the rest of the day from the prompt or turn silence off from the menu bar.
  3. While silenced, app stops counting tracked work and automatically resumes normal behavior at midnight.
  4. Menu bar UI shows next check-in countdown, current project context, today’s total, and quick actions.
**Plans**: 3 plans

Plans:
- [ ] 03-01: Implement delay actions and rescheduling behavior.
- [ ] 03-02: Implement silence mode lifecycle, midnight reset, and manual unsilence.
- [ ] 03-03: Build menu bar status, totals, and quick actions.

### Phase 4: Idle and Locked-Screen Reconciliation
**Goal**: Detect inactivity and locked-screen periods, exclude them from active tracking, and let the user resolve that time intentionally.
**Depends on**: Phase 3
**Requirements**: [IDLE-01, IDLE-02, IDLE-03, IDLE-04, IDLE-05]
**Success Criteria** (what must be TRUE):
  1. App detects keyboard/mouse inactivity using the configured threshold and notices locked-screen transitions.
  2. Idle and locked-screen periods do not inflate active tracked work time automatically.
  3. When the user returns, app presents the idle duration and resolution choices.
  4. User can assign, discard, or split idle time and the resulting time ledger remains internally consistent.
**Plans**: 2 plans

Plans:
- [ ] 04-01: Implement idle and lock detection with suspended active tracking.
- [ ] 04-02: Build the idle-resolution flow for assign, discard, and split actions.

### Phase 5: Analytics and CSV Export
**Goal**: Make tracked data reviewable through analytics views and exportable for use outside the app.
**Depends on**: Phase 4
**Requirements**: [ANLY-01, ANLY-02, ANLY-03, ANLY-04, ANLY-05, ANLY-06, EXPT-01, EXPT-02]
**Success Criteria** (what must be TRUE):
  1. User can open analytics and inspect time breakdown by project for daily, weekly, monthly, and yearly ranges.
  2. Analytics show totals, percentages, and charts that match the intended Daily Time Tracking-inspired workflow.
  3. Export generates a CSV containing date, start time, end time, duration, and project for each entry.
**Plans**: 3 plans

Plans:
- [ ] 05-01: Build aggregation queries for analytics periods and project totals.
- [ ] 05-02: Implement charts and analytics presentation.
- [ ] 05-03: Implement CSV export from tracked entries.

### Phase 6: Launch and Correctness Hardening
**Goal**: Finish launch-at-login support and harden timing behavior across restarts and edge cases so the app is dependable for daily use.
**Depends on**: Phase 5
**Requirements**: [SETG-04]
**Success Criteria** (what must be TRUE):
  1. User can enable or disable launch at login from settings.
  2. Polling, silence reset, and elapsed-time calculations recover correctly across app relaunches and date boundaries.
  3. The end-to-end workflow is stable enough for daily personal use without manual bookkeeping workarounds.
**Plans**: 2 plans

Plans:
- [ ] 06-01: Implement launch-at-login integration and settings wiring.
- [ ] 06-02: Validate and harden scheduler correctness across restart and midnight edge cases.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation and Timing Engine | 3/3 | Complete | 2026-03-15 |
| 2. Check-In Logging Flow | 0/3 | Not started | - |
| 3. Deferrals, Silence, and Menu Bar Control | 0/3 | Not started | - |
| 4. Idle and Locked-Screen Reconciliation | 0/2 | Not started | - |
| 5. Analytics and CSV Export | 0/3 | Not started | - |
| 6. Launch and Correctness Hardening | 0/2 | Not started | - |
