---
status: testing
phase: 06-launch-and-correctness-hardening
source:
  - .planning/phases/06-launch-and-correctness-hardening/06-01-SUMMARY.md
  - .planning/phases/06-launch-and-correctness-hardening/06-02-SUMMARY.md
started: 2026-03-16T08:04:45Z
updated: 2026-03-16T08:04:45Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

number: 2
name: Launch-at-Login State Persists Across Relaunch
expected: |
  After enabling or disabling launch at login, quitting and reopening Tempo shows the same setting state rather than reverting unexpectedly.
awaiting: user response

## Tests

### 1. Launch-at-Login Toggle Visibility
expected: In Tempo settings, there is a launch-at-login section with a toggle such as "Launch Tempo when I sign in". Toggling it updates the setting immediately instead of being a placeholder.
result: issue
reported: "The pop-up window sucks. This UX, I can't see anything. Look at the image."
severity: major

### 2. Launch-at-Login State Persists Across Relaunch
expected: After enabling or disabling launch at login, quitting and reopening Tempo shows the same setting state rather than reverting unexpectedly.
result: pending

### 3. Launch-at-Login Failure Surfaces Clearly
expected: If macOS refuses the login-item change, Tempo shows a clear error message and does not leave the toggle claiming the wrong final state.
result: pending

### 4. Relaunch Gap Does Not Inflate Prompt Elapsed Time
expected: If Tempo is quit for a while and reopened after a prompt would have been due, the next prompt or timing copy does not count the entire closed-app gap as tracked active work.
result: pending

### 5. Silence Expires Cleanly After Midnight
expected: If Tempo is silenced for the rest of the day before midnight, then reopened or woken after midnight, silence is cleared and the next check-in is scheduled from the post-midnight recovery time instead of carrying prior downtime forward.
result: pending

## Summary

total: 5
passed: 0
issues: 1
pending: 4
skipped: 0

## Gaps

- truth: "In Tempo settings, there is a launch-at-login section with a toggle such as \"Launch Tempo when I sign in\" and it is clearly visible and usable."
  status: failed
  reason: "User reported: The pop-up window sucks. This UX, I can't see anything. Look at the image."
  severity: major
  test: 1
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""
