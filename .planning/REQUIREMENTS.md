# Requirements: Tempo

**Defined:** 2026-03-15
**Core Value:** Tempo must prompt at the correct time and assign time accurately enough that the user can trust the tracking log without having to reconstruct their day manually.

## v1 Requirements

### Projects

- [ ] **PROJ-01**: User can create a project from the main app interface.
- [ ] **PROJ-02**: User can select from existing projects during a check-in.
- [ ] **PROJ-03**: User can create a new project inline during a check-in without leaving the popup.
- [ ] **PROJ-04**: Projects are stored and presented as a flat list with no hierarchy.

### Polling Check-In

- [ ] **POLL-01**: App shows a check-in prompt at the configured interval, with a default interval of 25 minutes.
- [ ] **POLL-02**: Check-in prompt appears as a full-screen UI intended to capture attention.
- [ ] **POLL-03**: Check-in prompt does not block normal keyboard or mouse input outside its own controls.
- [ ] **POLL-04**: Check-in prompt displays the existing project list.
- [ ] **POLL-05**: Check-in prompt shows the elapsed time since the last completed check-in.
- [ ] **POLL-06**: Selecting a project logs the elapsed time block to that project.
- [ ] **POLL-07**: Check-in prompt includes a delay action.
- [ ] **POLL-08**: Check-in prompt includes a silence-for-rest-of-day action.

### Delay

- [ ] **DELY-01**: User can postpone a check-in by choosing a delay duration.
- [ ] **DELY-02**: Delay duration options are configurable in settings.
- [ ] **DELY-03**: App re-prompts automatically when the selected delay period ends.

### Silence

- [ ] **SILN-01**: User can silence the app for the rest of the current day from the check-in prompt.
- [ ] **SILN-02**: While silenced, app stops logging tracked work time completely.
- [ ] **SILN-03**: Silence mode ends automatically at local midnight.
- [ ] **SILN-04**: User can disable silence mode manually from the menu bar.

### Idle Handling

- [ ] **IDLE-01**: App detects when the user has been idle past the configured keyboard/mouse inactivity threshold.
- [ ] **IDLE-02**: App detects when the screen is locked.
- [ ] **IDLE-03**: Idle or locked-screen time is excluded from active work logging by default.
- [ ] **IDLE-04**: When the user returns from idle, app prompts them to account for the idle period.
- [ ] **IDLE-05**: User can assign idle time to a project, discard it, or split it across projects.

### Analytics

- [ ] **ANLY-01**: User can open an analytics view showing tracked time broken down by project.
- [ ] **ANLY-02**: Analytics support daily, weekly, monthly, and yearly time periods.
- [ ] **ANLY-03**: Analytics show visual charts or graphs for time allocation.
- [ ] **ANLY-04**: Analytics show total tracked time for the selected period.
- [ ] **ANLY-05**: Analytics show percentage breakdown by project for the selected period.
- [ ] **ANLY-06**: Analytics presentation follows the Daily Time Tracking style direction closely enough to preserve the intended workflow.

### Export

- [ ] **EXPT-01**: User can export tracked time data to CSV.
- [ ] **EXPT-02**: CSV export includes date, start time, end time, duration, and project name for each exported entry.

### Menu Bar

- [ ] **MENU-01**: App runs as a menu bar application.
- [ ] **MENU-02**: Menu bar UI shows a countdown until the next check-in.
- [ ] **MENU-03**: Menu bar dropdown shows the current active project context.
- [ ] **MENU-04**: Menu bar dropdown shows total time tracked for today.
- [ ] **MENU-05**: Menu bar dropdown provides quick access to check in now, silence controls, analytics, settings, and quit.

### Settings

- [ ] **SETG-01**: User can configure the polling interval, defaulting to 25 minutes.
- [ ] **SETG-02**: User can configure the idle detection threshold, defaulting to 5 minutes.
- [ ] **SETG-03**: User can configure the set of delay duration options.
- [ ] **SETG-04**: User can enable or disable launch at login.

### Local Data and UX

- [ ] **DATA-01**: All projects, settings, and tracked time are stored locally on the user’s Mac.
- [ ] **DATA-02**: App does not require cloud sync or any network connectivity to function.
- [ ] **UX-01**: App does not play sounds for prompts, confirmations, or alerts.

## v2 Requirements

### Retroactive Editing

- **EDIT-01**: User can view tracked time as a timeline.
- **EDIT-02**: User can reassign an existing time block to a different project.
- **EDIT-03**: User can adjust the start and end times of an existing time entry.
- **EDIT-04**: User can split an existing time block between projects.
- **EDIT-05**: User can delete a time entry.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Pomodoro mode | Explicitly deferred by the PRD to a future iteration |
| Automatic tracking by application or website | Conflicts with the intended polling-based interaction model |
| Cloud synchronization | Product is local-only in v1 |
| Mobile companion app | Native macOS focus keeps scope tight |
| Team or sharing features | Product is for personal use only |
| External service integrations | Not required for the local MVP |
| Public distribution workflows | Distribution outside personal use is explicitly excluded |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| PROJ-01 | Phase 1 | Pending |
| PROJ-02 | Phase 2 | Pending |
| PROJ-03 | Phase 2 | Pending |
| PROJ-04 | Phase 1 | Pending |
| POLL-01 | Phase 1 | Pending |
| POLL-02 | Phase 2 | Pending |
| POLL-03 | Phase 2 | Pending |
| POLL-04 | Phase 2 | Pending |
| POLL-05 | Phase 2 | Pending |
| POLL-06 | Phase 2 | Pending |
| POLL-07 | Phase 3 | Pending |
| POLL-08 | Phase 3 | Pending |
| DELY-01 | Phase 3 | Pending |
| DELY-02 | Phase 1 | Pending |
| DELY-03 | Phase 3 | Pending |
| SILN-01 | Phase 3 | Pending |
| SILN-02 | Phase 3 | Pending |
| SILN-03 | Phase 3 | Pending |
| SILN-04 | Phase 3 | Pending |
| IDLE-01 | Phase 4 | Pending |
| IDLE-02 | Phase 4 | Pending |
| IDLE-03 | Phase 4 | Pending |
| IDLE-04 | Phase 4 | Pending |
| IDLE-05 | Phase 4 | Pending |
| ANLY-01 | Phase 5 | Pending |
| ANLY-02 | Phase 5 | Pending |
| ANLY-03 | Phase 5 | Pending |
| ANLY-04 | Phase 5 | Pending |
| ANLY-05 | Phase 5 | Pending |
| ANLY-06 | Phase 5 | Pending |
| EXPT-01 | Phase 5 | Pending |
| EXPT-02 | Phase 5 | Pending |
| MENU-01 | Phase 1 | Pending |
| MENU-02 | Phase 3 | Pending |
| MENU-03 | Phase 3 | Pending |
| MENU-04 | Phase 3 | Pending |
| MENU-05 | Phase 3 | Pending |
| SETG-01 | Phase 1 | Pending |
| SETG-02 | Phase 1 | Pending |
| SETG-03 | Phase 1 | Pending |
| SETG-04 | Phase 6 | Pending |
| DATA-01 | Phase 1 | Pending |
| DATA-02 | Phase 1 | Pending |
| UX-01 | Phase 2 | Pending |

**Coverage:**
- v1 requirements: 43 total
- Mapped to phases: 43
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-15*
*Last updated: 2026-03-15 after initial definition*
