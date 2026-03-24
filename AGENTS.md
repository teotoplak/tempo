# Agent Instructions

## Repo Context

- This repository contains the Tempo macOS app.
- The app is local-first and uses Swift, SwiftUI, AppKit, and SwiftData.
- Prefer small, targeted changes over broad refactors.
- Validate behavior with `swift test` after code changes when feasible.

## Troubleshooting Data

- Tempo now writes a rolling runtime trace for lock, wake, timer, scheduler, and check-in prompt window events.
- Primary trace file: `~/Library/Application Support/Tempo/Diagnostics/tempo-trace.jsonl`
- Previous rotated trace file: `~/Library/Application Support/Tempo/Diagnostics/tempo-trace.previous.jsonl`
- The app settings UI exposes the current trace path and a `Reveal Trace Log in Finder` action.

## When Debugging “Check-In Window Didn’t Appear”

- Collect both diagnostics files if they exist.
- Record the approximate wall-clock time of the incident and whether it happened after screen lock, sleep, wake, unlock, or app relaunch.
- Check whether the trace contains:
  - `workspace-notification` events such as `screensDidSleep`, `screensDidWake`, `sessionDidResignActive`, and `sessionDidBecomeActive`
  - `runtime-timer-scheduled`, `runtime-timer-fired`, or `runtime-timer-cleared`
  - `runtime-state-applied` and `prompt-state-updated`
  - prompt window events from `CheckInPromptWindowController` such as `show`, `bring-to-front`, and `hide`
- If the trace shows state transitions into a presented prompt but no matching prompt window events, suspect presentation/focus issues.
- If the trace never reaches a presented prompt state, suspect notification delivery, idle sampling, or scheduler state recovery.

## Safety

- Do not delete or reset user-local app data unless explicitly requested.
- Treat diagnostics files as local troubleshooting artifacts, not source-controlled files.
