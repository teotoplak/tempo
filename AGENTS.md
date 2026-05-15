# Agent Instructions

## Repo Context

- This repository contains the Tempo macOS app.
- The app is local-first and uses Swift, SwiftUI, AppKit, and SwiftData.
- Prefer small, targeted changes over broad refactors.
- Validate behavior with `swift test` after code changes when feasible.

## Local Development Run Loop

- Use `scripts/dev-run` to rebuild and relaunch the latest local version of Tempo without opening Xcode.
- Run `scripts/dev-run` after finishing a code change when the user should manually test the latest behavior, or whenever the running app needs to pick up recently completed changes.
- `scripts/dev-run` builds with `swift build`, stops the currently running `TempoApp` process if present, and starts `.build/arm64-apple-macosx/debug/TempoApp` through `launchctl`.
- Do not use this workflow to install Tempo as a persistent `.app` bundle; it is only for local development relaunches.
- Do not delete or reset `~/Library/Application Support/Tempo` as part of rebuilding or relaunching the app.

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
