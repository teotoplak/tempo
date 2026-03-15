# Tempo

## What This Is

Tempo is a native macOS menu bar application for polling-based personal time tracking. Instead of asking the user to start and stop timers manually, it periodically interrupts with a prominent check-in asking what they are working on, then attributes the elapsed time to the selected project. The first release is optimized for fast delivery of a reliable local-only app for one user, not for broader distribution or long-term multi-user scale.

## Core Value

Tempo must prompt at the correct time and assign time accurately enough that the user can trust the tracking log without having to reconstruct their day manually.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] A native macOS app polls the user on the configured schedule and records elapsed work time accurately.
- [ ] Users can manage a flat project list and classify active time, delayed time, and idle time without leaving the app.
- [ ] Users can review analytics and export their local tracking history without any network dependency.

### Out of Scope

- Team, sharing, or cloud sync features — the product is explicitly for personal local use only.
- Automatic tracking by application or website — the product intentionally uses manual check-ins instead of passive surveillance.
- Mobile or cross-platform clients — v1 is native macOS only to minimize delivery time.
- Public distribution concerns like onboarding, account systems, or remote infrastructure — the goal is a usable personal tool, not a general-market product.

## Context

Tempo is inspired by Daily Time Tracking and adopts the same polling-based model: periodically ask what the user is doing, then log elapsed time against a project. The user wants a native macOS implementation built with Swift and SwiftUI, with all persistence on-device and no cloud connectivity. Accuracy matters more than breadth: polling must fire on time, elapsed durations must be trustworthy, idle and locked-screen periods must not contaminate active work totals, and analytics must make it easy to understand how time was spent by day, week, month, and year.

The user clarified the practical release boundary:
- Personal use only, so implementation speed and local usefulness take priority over future scale.
- Retroactive editing is not part of the first usable release and should be deferred.
- Analytics are required in v1, not optional polish.
- The app should remain silent: no audio notifications.

## Constraints

- **Platform**: Native macOS only — fastest path to a useful personal app.
- **Tech stack**: Swift + SwiftUI — explicitly preferred by the user and aligned with native UX.
- **Persistence**: Local-only storage — no cloud sync, accounts, or required network access.
- **Product scope**: Personal-use MVP — optimize for correctness and usability over scale or extensibility.
- **Primary quality bar**: Polling cadence and time accounting must be trustworthy — this is the core value and priority for tradeoffs.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Build as a native macOS app using Swift and SwiftUI | Matches user preference and avoids cross-platform overhead | — Pending |
| Optimize for a personal local-first MVP | Fastest route to a usable product; no need to design for teams or cloud scale yet | — Pending |
| Keep retroactive timeline editing out of v1 | User wants the first release focused on live tracking correctness and analytics | — Pending |
| Include analytics in v1 | Time breakdown by project and period is a must-have outcome for the user | — Pending |
| Keep the product silent (no audio cues) | Explicit product requirement and reduces annoyance for a polling app | — Pending |

---
*Last updated: 2026-03-15 after initialization*
