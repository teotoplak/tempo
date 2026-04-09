import AppKit
import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

struct CheckInPromptState: Equatable {
    var isPresented: Bool
    var elapsedDuration: TimeInterval
    var isOverdue: Bool
    var promptTitle: String
    var supportingSubtitle: String

    static let hidden = CheckInPromptState(
        isPresented: false,
        elapsedDuration: 0,
        isOverdue: false,
        promptTitle: "What are you currently doing",
        supportingSubtitle: "Elapsed 0 min"
    )
}

struct DerivedRuntimeState: Equatable {
    var nextCheckInAt: Date?
    var isPromptOverdue: Bool
    var accountableElapsedInterval: TimeInterval
    var isSilenced: Bool
    var silenceEndsAt: Date?
    var isIdlePending: Bool
    var pendingIdleStartedAt: Date?
    var pendingIdleEndedAt: Date?
    var pendingIdleReason: String?
}

enum PromptProjectSelection: Equatable {
    case project(UUID)
    case createNew
}

enum IdleResolutionError: LocalizedError {
    case noPendingIdle

    var errorDescription: String? {
        switch self {
        case .noPendingIdle:
            return "No pending idle interval is available."
        }
    }
}

@MainActor
@Observable
final class TempoAppModel {
    private static let promptProjectDisplayLimit = 4
    private static let userActivityEventSamples: [(label: String, state: CGEventSourceStateID, event: CGEventType)] = [
        ("hid-mouse-moved", .hidSystemState, .mouseMoved),
        ("combined-mouse-moved", .combinedSessionState, .mouseMoved),
        ("hid-left-mouse-down", .hidSystemState, .leftMouseDown),
        ("combined-left-mouse-down", .combinedSessionState, .leftMouseDown),
        ("hid-left-mouse-up", .hidSystemState, .leftMouseUp),
        ("combined-left-mouse-up", .combinedSessionState, .leftMouseUp),
        ("hid-right-mouse-down", .hidSystemState, .rightMouseDown),
        ("combined-right-mouse-down", .combinedSessionState, .rightMouseDown),
        ("hid-right-mouse-up", .hidSystemState, .rightMouseUp),
        ("combined-right-mouse-up", .combinedSessionState, .rightMouseUp),
        ("hid-other-mouse-down", .hidSystemState, .otherMouseDown),
        ("combined-other-mouse-down", .combinedSessionState, .otherMouseDown),
        ("hid-other-mouse-up", .hidSystemState, .otherMouseUp),
        ("combined-other-mouse-up", .combinedSessionState, .otherMouseUp),
        ("hid-left-mouse-dragged", .hidSystemState, .leftMouseDragged),
        ("combined-left-mouse-dragged", .combinedSessionState, .leftMouseDragged),
        ("hid-right-mouse-dragged", .hidSystemState, .rightMouseDragged),
        ("combined-right-mouse-dragged", .combinedSessionState, .rightMouseDragged),
        ("hid-other-mouse-dragged", .hidSystemState, .otherMouseDragged),
        ("combined-other-mouse-dragged", .combinedSessionState, .otherMouseDragged),
        ("hid-scroll-wheel", .hidSystemState, .scrollWheel),
        ("combined-scroll-wheel", .combinedSessionState, .scrollWheel),
        ("hid-key-down", .hidSystemState, .keyDown),
        ("combined-key-down", .combinedSessionState, .keyDown),
        ("hid-key-up", .hidSystemState, .keyUp),
        ("combined-key-up", .combinedSessionState, .keyUp),
        ("hid-flags-changed", .hidSystemState, .flagsChanged),
        ("combined-flags-changed", .combinedSessionState, .flagsChanged)
    ]

    enum WindowSection: String, CaseIterable, Identifiable {
        case projects
        case analytics

        var id: String { rawValue }

        var title: String {
            switch self {
            case .projects:
                return "Projects"
            case .analytics:
                return "Analytics"
            }
        }
    }

    enum LaunchState: String {
        case launching
        case ready
    }

    let modelContainer: ModelContainer
    let modelContext: ModelContext

    var selectedWindow: WindowSection = .projects
    var launchState: LaunchState = .launching

    var settings: AppSettingsRecord
    var schedulerStateRecord: SchedulerStateRecord
    var nextCheckInAt: Date?
    var isPromptOverdue = false
    var accountableElapsedInterval: TimeInterval = 0
    var isSilenced = false
    var silenceEndsAt: Date?
    var isIdlePending = false
    var pendingIdleStartedAt: Date?
    var pendingIdleEndedAt: Date?
    var pendingIdleReason: String?
    var pendingIdleDuration: TimeInterval = 0
    var promptProjectSelection: PromptProjectSelection?
    var checkInPromptState = CheckInPromptState.hidden
    var promptSearchText = ""
    var selectedAnalyticsRange: AnalyticsRange = .day
    var analyticsPeriod: AnalyticsPeriod
    var analyticsTotalDuration: TimeInterval = 0
    var analyticsProjectSummaries: [AnalyticsProjectSummary] = []
    var analyticsFirstEntryStartDate: Date?
    var analyticsTimelineIntervals: [AnalyticsTimelineInterval] = []
    var analyticsAllocatedIntervals: [TimeAllocationInterval] = []
    var canShowNextAnalyticsPeriod = false
    var menuBarDayPeriod: AnalyticsPeriod
    var menuBarDayWorkedDuration: TimeInterval = 0
    var menuBarDayProjectSummaries: [AnalyticsProjectSummary] = []
    var menuBarDayCheckIns: [TimeAllocationCheckIn] = []
    var canShowNextMenuBarDay = false
    var analyticsExportStatusMessage: String?
    var analyticsExportErrorMessage: String?
    var diagnosticsStatusMessage: String?
    var launchAtLoginEnabled = false
    var launchAtLoginErrorMessage: String?
    private var lastSavedPollingIntervalMinutes = 25
    private var isMenuBarWindowVisible = false
    private var promptPresentedAt: Date?

    private let clock: any SchedulerClock
    private let calendar: Calendar
    private let checkInTriggerEngine: CheckInTriggerEngine
    private let analyticsStore: AnalyticsStore
    private let csvExportService: CSVExportService
    private let diagnosticsRecorder: TempoDiagnosticsRecorder
    private let launchAtLoginController: any LaunchAtLoginControlling
    private var hasHandledInitialLaunch = false
    private var analyticsReferenceDate: Date
    private var menuBarDayReferenceDate: Date
    private var workspaceObservers: [NSObjectProtocol] = []
    private var checkInPromptWindowController: CheckInPromptWindowController?
    private weak var analyticsWindow: NSWindow?
    private var priorAnalyticsActivationPolicy: NSApplication.ActivationPolicy?
    private var scheduledPromptTimer: Timer?
    private var hasQueuedImmediatePromptTimerFire = false

    init(
        modelContainer: ModelContainer? = nil,
        clock: any SchedulerClock = SystemSchedulerClock(),
        calendar: Calendar = .current,
        diagnosticsRecorder: TempoDiagnosticsRecorder = TempoDiagnosticsRecorder.makeDefault(),
        launchAtLoginController: any LaunchAtLoginControlling = SMAppServiceLaunchAtLoginController()
    ) {
        let resolvedContainer = modelContainer ?? TempoModelContainer.live()
        self.modelContainer = resolvedContainer
        self.modelContext = ModelContext(resolvedContainer)
        self.clock = clock
        self.calendar = calendar
        self.checkInTriggerEngine = CheckInTriggerEngine(calendar: calendar)
        self.diagnosticsRecorder = diagnosticsRecorder
        self.launchAtLoginController = launchAtLoginController
        self.analyticsPeriod = AnalyticsPeriod(
            startDate: clock.now,
            endDate: clock.now,
            label: clock.now.formatted(date: .abbreviated, time: .omitted)
        )
        self.menuBarDayPeriod = AnalyticsPeriod(
            startDate: clock.now,
            endDate: clock.now,
            label: clock.now.formatted(date: .abbreviated, time: .omitted)
        )
        self.analyticsReferenceDate = clock.now
        self.menuBarDayReferenceDate = clock.now

        let settingsFetch = FetchDescriptor<AppSettingsRecord>()
        let schedulerFetch = FetchDescriptor<SchedulerStateRecord>()

        if let existingSettings = try? self.modelContext.fetch(settingsFetch).first {
            self.settings = existingSettings
        } else {
            let createdSettings = AppSettingsRecord()
            self.modelContext.insert(createdSettings)
            self.settings = createdSettings
        }

        if let existingState = try? self.modelContext.fetch(schedulerFetch).first {
            self.schedulerStateRecord = existingState
        } else {
            let createdState = SchedulerStateRecord()
            self.modelContext.insert(createdState)
            self.schedulerStateRecord = createdState
        }

        if self.modelContext.hasChanges {
            try? self.modelContext.save()
        }

        self.analyticsStore = AnalyticsStore(modelContext: self.modelContext)
        self.csvExportService = CSVExportService(modelContext: self.modelContext, calendar: calendar)
        self.launchAtLoginEnabled = launchAtLoginController.isEnabled
        self.lastSavedPollingIntervalMinutes = self.settings.pollingIntervalMinutes

        refreshRuntimeState(eventDate: clock.now)
        reloadAnalytics()
        refreshCheckInPromptState()
        trace("model-initialized", metadata: ["diagnosticsLogPath": diagnosticsLogPath])
    }

    func performInitialLaunchIfNeeded(activityDate: Date? = nil) {
        guard !hasHandledInitialLaunch else {
            return
        }

        hasHandledInitialLaunch = true
        trace("initial-launch-started")
        observeWorkspaceWake()
        reconcileLaunchAtLoginPreferenceWithSystem()
        recoverSchedulerState(
            eventDate: clock.now,
            activityDate: activityDate,
            allowScreenLockReturnFallback: true
        )
        reloadAnalytics()
        presentLaunchCheckInPrompt()
    }

    func reconcileLaunchAtLoginPreferenceWithSystem() {
        if settings.launchAtLoginEnabled && !launchAtLoginController.isEnabled {
            do {
                try launchAtLoginController.setEnabled(true)
            } catch {
                launchAtLoginErrorMessage = error.localizedDescription
            }
        }

        let isEnabled = launchAtLoginController.isEnabled
        launchAtLoginEnabled = isEnabled
        if isEnabled || !settings.launchAtLoginEnabled {
            settings.launchAtLoginEnabled = isEnabled
        }
        if isEnabled {
            launchAtLoginErrorMessage = nil
        }
        try? modelContext.save()
    }

    func saveLaunchAtLoginPreference(_ enabled: Bool) throws {
        do {
            try launchAtLoginController.setEnabled(enabled)
            launchAtLoginEnabled = enabled
            settings.launchAtLoginEnabled = enabled
            launchAtLoginErrorMessage = nil
            try modelContext.save()
        } catch {
            let systemState = launchAtLoginController.isEnabled
            launchAtLoginEnabled = systemState
            settings.launchAtLoginEnabled = systemState
            launchAtLoginErrorMessage = error.localizedDescription
            try? modelContext.save()
            throw error
        }
    }

    func handleSceneActivation(activityDate: Date? = nil) {
        let now = clock.now
        let resolvedActivityDate = activityDate ?? now
        trace("scene-activated", metadata: ["activityDate": Self.traceTimestamp(resolvedActivityDate)])
        recoverSchedulerState(eventDate: now, activityDate: resolvedActivityDate)
    }

    func handleAppWake() {
        trace("system-wake-detected")
        recoverSchedulerState(eventDate: clock.now, activityDate: clock.now)
    }

    func handleScreenWake(activityDate: Date? = nil) {
        let referenceDate = clock.now
        let sampledActivityDate = activityDate ?? currentUserActivityDate(referenceDate: referenceDate)
        let shouldFallbackToImmediateReturn: Bool
        if
            let latestCheckIn = latestCheckInRecord(),
            latestCheckIn.kind == "idle",
            latestCheckIn.source == "screen-locked",
            sampledActivityDate <= latestCheckIn.timestamp
        {
            shouldFallbackToImmediateReturn = true
        } else {
            shouldFallbackToImmediateReturn = false
        }

        let resolvedActivityDate = shouldFallbackToImmediateReturn ? referenceDate : sampledActivityDate
        trace(
            "screen-wake-detected",
            metadata: [
                "activityDate": Self.traceTimestamp(resolvedActivityDate),
                "usedExplicitActivityDate": "\(activityDate != nil)",
                "usedScreenLockReturnFallback": "\(shouldFallbackToImmediateReturn)"
            ]
        )
        recoverSchedulerState(
            eventDate: referenceDate,
            activityDate: resolvedActivityDate,
            allowScreenLockReturnFallback: true
        )
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func attachCheckInPromptWindowController(_ controller: CheckInPromptWindowController) {
        checkInPromptWindowController = controller
        controller.bind(appModel: self)
        controller.update(with: checkInPromptState)
        trace("prompt-window-controller-attached")
    }

    func setMenuBarWindowVisible(_ isVisible: Bool) {
        guard isMenuBarWindowVisible != isVisible else {
            return
        }

        isMenuBarWindowVisible = isVisible
        trace("menu-bar-window-visibility-changed", metadata: ["isVisible": "\(isVisible)"])

        if isVisible {
            let now = clock.now
            // Opening the menu is explicit user input, so treat it as the return moment
            // rather than relying on CGEvent idle sampling, which can stay stale across
            // screen-lock recovery.
            recoverSchedulerState(eventDate: now, activityDate: now)
            menuBarDayReferenceDate = now
            reloadAnalytics()
        }

        checkInPromptWindowController?.update(with: checkInPromptState)
    }

    func refreshCheckInPromptState() {
        ensureIdleSelectionDefaults()
        let shouldPresent = isPromptOverdue || shouldPresentPendingIdlePrompt || shouldPresentUnansweredIdlePrompt
        let promptTitle = "What are you currently doing"
        let supportingSubtitle = promptSupportingSubtitle(at: clock.now)
        let previousState = checkInPromptState
        checkInPromptState = CheckInPromptState(
            isPresented: shouldPresent,
            elapsedDuration: accountableElapsedInterval,
            isOverdue: isPromptOverdue,
            promptTitle: promptTitle,
            supportingSubtitle: supportingSubtitle
        )
        if previousState != checkInPromptState {
            trace(
                "prompt-state-updated",
                metadata: [
                    "previous": previousState.traceSummary,
                    "current": checkInPromptState.traceSummary
                ]
            )
        }
        checkInPromptWindowController?.update(with: checkInPromptState)
    }

    func presentCheckInPromptIfNeeded() {
        trace("present-check-in-prompt-if-needed")
        refreshCheckInPromptState()
        if checkInPromptState.isPresented,
           !isIdlePending,
           promptPresentedAt == nil {
            promptPresentedAt = clock.now
            refreshCheckInPromptState()
            schedulePromptTimerIfNeeded()
        }
        checkInPromptWindowController?.update(with: checkInPromptState)
    }

    func dismissCheckInPrompt() {
        checkInPromptState.isPresented = false
        trace("dismiss-check-in-prompt")
        checkInPromptWindowController?.hide()
        schedulePromptTimerIfNeeded()
    }

    var diagnosticsLogPath: String {
        diagnosticsRecorder.logFilePath ?? "Diagnostics log is unavailable in this runtime."
    }

    func revealDiagnosticsLogInFinder() {
        let didReveal = diagnosticsRecorder.revealLogInFinder()
        diagnosticsStatusMessage = didReveal
            ? "Revealed diagnostics log in Finder."
            : "Diagnostics log is unavailable in this runtime."
        trace("reveal-diagnostics-log", metadata: ["didReveal": "\(didReveal)"])
    }

    var currentProjectContextLabel: String {
        latestProjectCheckIn()?.project?.name ?? "No recent project"
    }

    var todaysTrackedDuration: TimeInterval {
        analyticsStore.summary(
            range: .day,
            referenceDate: clock.now,
            calendar: calendar,
            dayCutoffHour: settings.analyticsDayCutoffHour
        ).totalDuration
    }

    func menuBarCountdownMinutesText(at date: Date) -> String? {
        guard !isSilenced, let nextCheckInAt else {
            return nil
        }

        let remainingMinutes = max(Int(nextCheckInAt.timeIntervalSince(date) / 60), 0)
        return "\(remainingMinutes)"
    }

    func menuBarPrimaryStatus(at date: Date) -> String {
        if isSilenced, let silenceEndsAt {
            return silencePrimaryStatus(at: date, silenceEndsAt: silenceEndsAt)
        }

        if isPromptOverdue {
            return "Check-in overdue"
        }

        guard let nextCheckInAt else {
            return "Not scheduled"
        }

        let remaining = max(nextCheckInAt.timeIntervalSince(date), 0)
        return "Next check-in in \(Self.formattedCompactDuration(remaining))"
    }

    func menuBarSecondaryStatus(at date: Date) -> String {
        if isSilenced, let silenceEndsAt {
            return silenceSecondaryStatus(at: date, silenceEndsAt: silenceEndsAt)
        }

        if isPromptOverdue {
            return promptSupportingSubtitle(at: date)
        }

        guard let nextCheckInAt else {
            return "Open Tempo to reset scheduling."
        }

        return "Scheduled for \(Self.formattedClockTime(nextCheckInAt))"
    }

    var pendingIdleStatusText: String {
        Self.idleSupportingSubtitle(duration: pendingIdleDuration, reason: pendingIdleReasonLabel)
    }

    var analyticsTotalDurationText: String {
        Self.formattedTrackedDuration(analyticsTotalDuration)
    }

    var analyticsTopProjectSummaryText: String {
        guard
            let topProject = analyticsProjectSummaries.first
        else {
            return "No tracked time"
        }

        return "\(topProject.projectName) · \(Self.formattedTrackedDuration(topProject.totalDuration))"
    }

    var analyticsFirstEntryStartText: String {
        guard let analyticsFirstEntryStartDate else {
            return "No input yet"
        }

        return Self.formattedClockTime(analyticsFirstEntryStartDate)
    }

    var selectedPromptProjectID: UUID? {
        guard case let .project(projectID) = promptProjectSelection else {
            return nil
        }

        return projectID
    }

    var isCreatePromptProjectSelected: Bool {
        promptProjectSelection == .createNew
    }

    var selectedPromptProject: ProjectRecord? {
        guard let selectedPromptProjectID else {
            return nil
        }

        return fetchProjects().first { $0.id == selectedPromptProjectID }
    }

    var pendingIdleReasonDisplayText: String {
        pendingIdleReasonLabel
    }

    var recentPromptProjects: [ProjectRecord] {
        let projects = fetchProjects()
        let recentEndDates = recentPromptProjectEndDates()

        return projects.sorted { lhs, rhs in
            let lhsRecent = recentEndDates[lhs.id]
            let rhsRecent = recentEndDates[rhs.id]

            switch (lhsRecent, rhsRecent) {
            case let (lhsDate?, rhsDate?):
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }

            return lhs.sortOrder < rhs.sortOrder
        }
    }

    var filteredPromptProjects: [ProjectRecord] {
        let query = promptSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return recentPromptProjects
        }

        return recentPromptProjects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
        }
    }

    var visiblePromptProjects: [ProjectRecord] {
        Array(filteredPromptProjects.prefix(Self.promptProjectDisplayLimit))
    }

    var hasVisiblePromptCreateAction: Bool {
        canCreatePromptProject(named: promptSearchText)
    }

    func canCreatePromptProject(named rawName: String) -> Bool {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return false
        }

        return !fetchProjects().contains { project in
            project.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    func updatePromptSearchText(_ rawText: String) {
        promptSearchText = rawText
        syncPromptSelection()
    }

    func submitPromptSearch() throws {
        guard isPromptInteractionActive else {
            return
        }

        let trimmedQuery = promptSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            if let selectedPromptProject {
                try selectProjectForPrompt(selectedPromptProject)
            }
            return
        }

        switch promptProjectSelection {
        case let .project(projectID):
            if let project = fetchProjects().first(where: { $0.id == projectID }) {
                try selectProjectForPrompt(project)
            }
        case .createNew:
            if canCreatePromptProject(named: trimmedQuery) {
                try createAndSelectProjectForPrompt(named: trimmedQuery)
            }
        case nil:
            if let selectedPromptProject {
                try selectProjectForPrompt(selectedPromptProject)
                return
            }

            if canCreatePromptProject(named: trimmedQuery) {
                try createAndSelectProjectForPrompt(named: trimmedQuery)
            }
        }
    }

    func movePromptSelection(by offset: Int) {
        let selectionItems = visiblePromptSelectionItems
        guard !selectionItems.isEmpty, offset != 0 else {
            return
        }

        let currentIndex = promptProjectSelection.flatMap { currentSelection in
            selectionItemIndex(for: currentSelection, in: selectionItems)
        }
        let baseIndex = currentIndex ?? (offset > 0 ? -1 : selectionItems.count)
        let nextIndex = min(max(baseIndex + offset, 0), selectionItems.count - 1)
        promptProjectSelection = selection(for: selectionItems[nextIndex])
    }

    func createProject(named name: String) throws {
        _ = try createProjectRecord(named: name)
    }

    func selectAnalyticsRange(_ range: AnalyticsRange) {
        selectedAnalyticsRange = range
        reloadAnalytics()
    }

    func prepareWeeklyAnalyticsPresentation(resetReferenceDate: Bool = true) {
        recordAnalyticsWindowEvent(
            "prepare-weekly-presentation",
            metadata: ["resetReferenceDate": "\(resetReferenceDate)"]
        )
        selectedAnalyticsRange = .week
        if resetReferenceDate {
            refreshAnalytics(referenceDate: clock.now)
        } else {
            reloadAnalytics()
        }
    }

    func showPreviousAnalyticsPeriod() {
        recordAnalyticsWindowEvent("navigate-previous-period")
        refreshAnalytics(referenceDate: analyticsPeriod.startDate.addingTimeInterval(-1))
    }

    func showNextAnalyticsPeriod() {
        guard canShowNextAnalyticsPeriod else {
            recordAnalyticsWindowEvent("navigate-next-period-blocked")
            return
        }

        recordAnalyticsWindowEvent("navigate-next-period")
        refreshAnalytics(referenceDate: analyticsPeriod.endDate)
    }

    func showPreviousMenuBarDay() {
        menuBarDayReferenceDate = menuBarDayPeriod.startDate.addingTimeInterval(-1)
        refreshMenuBarDayAnalytics()
    }

    func showNextMenuBarDay() {
        guard canShowNextMenuBarDay else {
            return
        }

        menuBarDayReferenceDate = menuBarDayPeriod.endDate
        refreshMenuBarDayAnalytics()
    }

    func selectProjectForPrompt(_ project: ProjectRecord) throws {
        guard isPromptInteractionActive else {
            return
        }

        if shouldTreatPromptSelectionAsFreshCheckIn {
            try persistFreshPromptSelection(for: project)
            return
        }

        if isIdlePending {
            try assignPendingIdle(to: project)
            return
        }

        try persistFreshPromptSelection(for: project)
    }

    func createAndSelectProjectForPrompt(named name: String) throws {
        guard isPromptInteractionActive else {
            return
        }

        let project = try createProjectRecord(named: name)
        if shouldTreatPromptSelectionAsFreshCheckIn {
            try persistFreshPromptSelection(for: project)
            return
        }

        if isIdlePending {
            try assignPendingIdle(to: project)
            return
        }

        try selectProjectForPrompt(project)
    }

    func silenceForRestOfDay(trigger: String = "unknown") throws {
        trace("done-for-day-requested", metadata: ["source": trigger])
        persistIdleCheckIn(
            at: clock.now,
            idleKind: .doneForDay,
            source: "done-for-day"
        )
        try modelContext.save()

        refreshRuntimeState(eventDate: clock.now)
        promptSearchText = ""
        refreshCheckInPromptState()
        dismissCheckInPrompt()
    }

    func endSilenceMode(trigger: String = "unknown") throws {
        trace("unsilence-requested", metadata: ["source": trigger])
        persistResumeCheckIn(at: clock.now, source: "unsilence")
        try modelContext.save()

        refreshRuntimeState(eventDate: clock.now, activityDate: clock.now)
        refreshCheckInPromptState()
    }

    func checkInNow(trigger: String = "unknown") {
        trace("check-in-now-requested", metadata: ["source": trigger])
        if isIdlePending {
            handleIdleReturn()
            return
        }

        let pollingInterval = TimeInterval(settings.pollingIntervalMinutes * 60)
        let promptReference = nextCheckInAt ?? clock.now
        let referenceStart = latestSchedulingAnchorDate() ?? promptReference.addingTimeInterval(-pollingInterval)
        accountableElapsedInterval = max(clock.now.timeIntervalSince(referenceStart), pollingInterval)
        isPromptOverdue = true
        promptPresentedAt = nil
        refreshCheckInPromptState()
        presentCheckInPromptIfNeeded()
    }

    func assignPendingIdle(to project: ProjectRecord) throws {
        guard pendingIdleStartedAt != nil, let pendingIdleEndedAt else {
            throw IdleResolutionError.noPendingIdle
        }

        let completionDate = max(clock.now, pendingIdleEndedAt)
        persistProjectCheckIn(project, at: completionDate, source: "idle-return")
        try modelContext.save()
        refreshRuntimeState(eventDate: completionDate, activityDate: completionDate)
        reloadAnalytics()
        promptSearchText = ""
        refreshCheckInPromptState()
        dismissCheckInPrompt()
    }

    func discardPendingIdle() throws {
        guard pendingIdleStartedAt != nil, pendingIdleEndedAt != nil else {
            throw IdleResolutionError.noPendingIdle
        }

        persistResumeCheckIn(at: clock.now, source: "idle-discarded")
        try modelContext.save()
        refreshRuntimeState(eventDate: clock.now, activityDate: clock.now)
        reloadAnalytics()
    }

    func handleScreenLock(activityDate: Date? = nil) {
        let referenceDate = clock.now
        let sampledActivityDate = activityDate ?? currentUserActivityDate(referenceDate: referenceDate)
        trace("handle-screen-lock")
        guard latestCheckInRecord()?.kind != "idle" else {
            refreshRuntimeState(eventDate: referenceDate)
            return
        }
        let decision = checkInTriggerEngine.decide(
            signal: .screenLocked(at: referenceDate, activityDate: sampledActivityDate),
            context: makeCheckInTriggerContext()
        )
        applyTriggerEffects(decision.effects)
        apply(runtimeState: decision.runtimeState)
        promptSearchText = ""
        refreshCheckInPromptState()
        dismissCheckInPrompt()
    }

    func handleIdleReturn() {
        trace("handle-idle-return")
        refreshRuntimeState(eventDate: clock.now, activityDate: clock.now)
        refreshCheckInPromptState()
        presentCheckInPromptIfNeeded()
    }

    func renameProject(_ project: ProjectRecord, to newName: String) throws {
        project.name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        try modelContext.save()
        reloadAnalytics()
    }

    func deleteProject(_ project: ProjectRecord) throws {
        if !project.checkIns.isEmpty || !project.timeEntries.isEmpty {
            throw ProjectDeletionError.hasTrackedTime(project.name)
        }

        modelContext.delete(project)
        try modelContext.save()
    }

    func saveSettings() throws {
        try modelContext.save()
        defer {
            lastSavedPollingIntervalMinutes = settings.pollingIntervalMinutes
        }

        guard settings.pollingIntervalMinutes != lastSavedPollingIntervalMinutes else {
            recoverSchedulerState(eventDate: clock.now)
            return
        }

        if isSilenced || isIdlePending {
            recoverSchedulerState(eventDate: clock.now)
        } else {
            rescheduleNextCheckInFromSettingsChange(at: clock.now)
        }

        reloadAnalytics()
        refreshCheckInPromptState()
    }

    func reloadAnalytics() {
        refreshAnalytics(referenceDate: analyticsReferenceDate)
    }

    func refreshAnalytics(referenceDate: Date) {
        analyticsReferenceDate = referenceDate
        let snapshot = analyticsStore.summary(
            range: selectedAnalyticsRange,
            referenceDate: referenceDate,
            calendar: calendar,
            dayCutoffHour: settings.analyticsDayCutoffHour
        )
        analyticsPeriod = snapshot.period
        analyticsTotalDuration = snapshot.totalDuration
        analyticsProjectSummaries = snapshot.projectSummaries
        analyticsFirstEntryStartDate = snapshot.firstEntryStartDate
        analyticsTimelineIntervals = snapshot.timelineIntervals
        analyticsAllocatedIntervals = snapshot.allocatedIntervals
        let currentPeriod = analyticsStore.period(
            for: selectedAnalyticsRange,
            referenceDate: clock.now,
            calendar: calendar,
            dayCutoffHour: settings.analyticsDayCutoffHour
        )
        canShowNextAnalyticsPeriod = snapshot.period.startDate < currentPeriod.startDate
        recordAnalyticsWindowEvent(
            "snapshot-refreshed",
            metadata: [
                "referenceDate": Self.traceTimestamp(referenceDate),
                "projectSummaryCount": "\(snapshot.projectSummaries.count)",
                "allocatedIntervalCount": "\(snapshot.allocatedIntervals.count)",
                "totalTrackedSeconds": Self.traceInterval(snapshot.totalDuration)
            ]
        )
        refreshMenuBarDayAnalytics()
    }

    func exportAnalyticsCSV() {
        analyticsExportStatusMessage = nil
        analyticsExportErrorMessage = nil
        recordAnalyticsWindowEvent("export-csv-clicked")

        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "tempo-analytics.csv"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false

        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            return
        }

        do {
            let csv = csvExportService.csvString(
                range: selectedAnalyticsRange,
                referenceDate: analyticsReferenceDate,
                dayCutoffHour: settings.analyticsDayCutoffHour
            )
            try csv.write(to: destinationURL, atomically: true, encoding: .utf8)
            analyticsExportStatusMessage = "CSV exported"
            recordAnalyticsWindowEvent(
                "export-csv-succeeded",
                metadata: ["destinationPath": destinationURL.path]
            )
        } catch {
            analyticsExportErrorMessage = error.localizedDescription
            recordAnalyticsWindowEvent(
                "export-csv-failed",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    private func nextProjectSortOrder() -> Int {
        let descriptor = FetchDescriptor<ProjectRecord>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        let currentHighest = try? modelContext.fetch(descriptor).first?.sortOrder
        return (currentHighest ?? -1) + 1
    }

    private func createProjectRecord(named name: String) throws -> ProjectRecord {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProjectValidationError.emptyName
        }

        let nextSortOrder = nextProjectSortOrder()
        let project = ProjectRecord(name: trimmedName, sortOrder: nextSortOrder)
        modelContext.insert(project)
        try modelContext.save()
        return project
    }

    private func fetchProjects() -> [ProjectRecord] {
        let descriptor = FetchDescriptor<ProjectRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func recentPromptProjectEndDates() -> [UUID: Date] {
        let descriptor = FetchDescriptor<CheckInRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        var latestEndDateByProjectID: [UUID: Date] = [:]

        for entry in entries {
            guard let project = entry.project, latestEndDateByProjectID[project.id] == nil else {
                continue
            }

            latestEndDateByProjectID[project.id] = entry.timestamp
        }

        return latestEndDateByProjectID
    }

    private func latestProjectCheckIn() -> CheckInRecord? {
        let descriptor = FetchDescriptor<CheckInRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return try? modelContext.fetch(descriptor).first(where: { $0.project != nil })
    }

    private func latestCheckInRecord() -> CheckInRecord? {
        let descriptor = FetchDescriptor<CheckInRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return try? modelContext.fetch(descriptor).first
    }

    private func persistProjectCheckIn(_ project: ProjectRecord, at timestamp: Date, source: String) {
        modelContext.insert(
            CheckInRecord(
                timestamp: timestamp,
                kind: "project",
                source: source,
                project: project
            )
        )
    }

    private func persistResumeCheckIn(at timestamp: Date, source: String) {
        modelContext.insert(
            CheckInRecord(
                timestamp: timestamp,
                kind: "resume",
                source: source
            )
        )
    }

    private func persistIdleCheckIn(at timestamp: Date, idleKind: TimeAllocationIdleKind, source: String) {
        modelContext.insert(
            CheckInRecord(
                timestamp: timestamp,
                kind: "idle",
                source: source,
                idleKind: idleKind.rawValue
            )
        )
    }

    private func syncPromptSelection() {
        let filteredProjects = visiblePromptProjects
        let trimmedQuery = promptSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if filteredProjects.isEmpty {
            promptProjectSelection = canCreatePromptProject(named: trimmedQuery) ? .createNew : nil
            return
        }

        if trimmedQuery.isEmpty {
            let preferredProjectID = preferredPromptProject()?.id ?? filteredProjects.first?.id
            promptProjectSelection = preferredProjectID.map(PromptProjectSelection.project)
            return
        }

        if let exactMatch = filteredProjects.first(where: { project in
            project.name.compare(trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            promptProjectSelection = .project(exactMatch.id)
            return
        }

        if let promptProjectSelection {
            switch promptProjectSelection {
            case let .project(projectID) where filteredProjects.contains(where: { $0.id == projectID }):
                return
            case .createNew where canCreatePromptProject(named: trimmedQuery):
                return
            default:
                break
            }
        }

        promptProjectSelection = .project(filteredProjects[0].id)
    }

    private func ensureIdleSelectionDefaults() {
        guard isIdlePending else {
            return
        }

        let projects = filteredPromptProjects.isEmpty ? recentPromptProjects : filteredPromptProjects

        if promptProjectSelection == nil {
            promptProjectSelection = preferredPromptProject(in: projects).map { .project($0.id) }
        }
    }

    private enum PromptSelectionItem {
        case project(ProjectRecord)
        case createNew
    }

    private var visiblePromptSelectionItems: [PromptSelectionItem] {
        var items = visiblePromptProjects.map(PromptSelectionItem.project)
        if hasVisiblePromptCreateAction {
            items.append(.createNew)
        }
        return items
    }

    private func selectionItemIndex(
        for selection: PromptProjectSelection,
        in items: [PromptSelectionItem]
    ) -> Int? {
        items.firstIndex { item in
            switch (selection, item) {
            case let (.project(projectID), .project(project)):
                return projectID == project.id
            case (.createNew, .createNew):
                return true
            default:
                return false
            }
        }
    }

    private func selection(for item: PromptSelectionItem) -> PromptProjectSelection {
        switch item {
        case let .project(project):
            return .project(project.id)
        case .createNew:
            return .createNew
        }
    }

    private func preferredPromptProject(in projects: [ProjectRecord]? = nil) -> ProjectRecord? {
        let candidates = projects ?? recentPromptProjects
        guard !candidates.isEmpty else {
            return nil
        }

        if let latestProjectID = latestProjectCheckIn()?.project?.id,
           let latestProject = candidates.first(where: { $0.id == latestProjectID }) {
            return latestProject
        }

        return candidates.first
    }

    private func observeWorkspaceWake() {
        guard workspaceObservers.isEmpty else {
            return
        }

        let notificationCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.trace("workspace-notification", metadata: ["name": "didWake"])
                self?.handleAppWake()
            }
        }
        )
        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.trace("workspace-notification", metadata: ["name": "sessionDidResignActive"])
                self?.handleScreenLock()
            }
        })
        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.trace("workspace-notification", metadata: ["name": "screensDidSleep"])
                self?.handleScreenLock()
            }
        })
        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.trace("workspace-notification", metadata: ["name": "screensDidWake"])
                self?.handleScreenWake()
            }
        })
        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.trace("workspace-notification", metadata: ["name": "sessionDidBecomeActive"])
                self?.handleIdleReturn()
            }
        })
        trace("workspace-observers-installed")
    }

    func recoverSchedulerState(
        eventDate: Date,
        activityDate: Date? = nil,
        allowScreenLockReturnFallback: Bool = false
    ) {
        trace(
            "recover-scheduler-state",
            metadata: [
                "eventDate": Self.traceTimestamp(eventDate),
                "activityDate": Self.traceTimestamp(activityDate),
                "allowScreenLockReturnFallback": "\(allowScreenLockReturnFallback)"
            ]
        )
        refreshRuntimeState(
            eventDate: eventDate,
            activityDate: activityDate,
            allowScreenLockReturnFallback: allowScreenLockReturnFallback
        )
        refreshCheckInPromptState()
        launchState = .ready
    }

    private func refreshRuntimeState(
        eventDate: Date,
        activityDate: Date? = nil,
        allowScreenLockReturnFallback: Bool = false
    ) {
        apply(
            runtimeState: deriveRuntimeState(
                eventDate: eventDate,
                activityDate: activityDate,
                allowScreenLockReturnFallback: allowScreenLockReturnFallback
            )
        )
    }

    private func deriveRuntimeState(
        eventDate: Date,
        activityDate: Date? = nil,
        allowScreenLockReturnFallback: Bool = false
    ) -> DerivedRuntimeState {
        let decision = checkInTriggerEngine.decide(
            signal: .recover(
                eventDate: eventDate,
                activityDate: activityDateForTriggerRecovery(
                    eventDate: eventDate,
                    explicitActivityDate: activityDate
                ),
                allowScreenLockReturnFallback: allowScreenLockReturnFallback
            ),
            context: makeCheckInTriggerContext()
        )

        return decision.runtimeState
    }

    private func makeCheckInTriggerContext() -> CheckInTriggerContext {
        CheckInTriggerContext(
            settings: CheckInTriggerSettings(settings),
            latestCheckIn: latestCheckInForTrigger(),
            knownNextCheckInAt: schedulerStateRecord.nextCheckInAt ?? nextCheckInAt,
            runtimeState: DerivedRuntimeState(
                nextCheckInAt: nextCheckInAt,
                isPromptOverdue: isPromptOverdue,
                accountableElapsedInterval: accountableElapsedInterval,
                isSilenced: isSilenced,
                silenceEndsAt: silenceEndsAt,
                isIdlePending: isIdlePending,
                pendingIdleStartedAt: pendingIdleStartedAt,
                pendingIdleEndedAt: pendingIdleEndedAt,
                pendingIdleReason: pendingIdleReason
            ),
            promptPresentedAt: promptPresentedAt
        )
    }

    private func latestCheckInForTrigger() -> CheckInTriggerLatestCheckIn? {
        let descriptor = FetchDescriptor<CheckInRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        guard let latestRecord = try? modelContext.fetch(descriptor).first else {
            return nil
        }

        guard
            latestRecord.kind == "idle",
            let latestIdleKindRawValue = latestRecord.idleKind,
            let latestIdleKind = TimeAllocationIdleKind(persistedValue: latestIdleKindRawValue),
            latestIdleKind != .doneForDay
        else {
            return Self.checkInTriggerLatestCheckIn(from: latestRecord)
        }

        let records = (try? modelContext.fetch(descriptor)) ?? [latestRecord]
        var idleStartedAt = latestRecord.timestamp
        for record in records {
            guard record.kind == "idle" else {
                break
            }

            guard
                let idleKindRawValue = record.idleKind,
                let idleKind = TimeAllocationIdleKind(persistedValue: idleKindRawValue),
                idleKind == latestIdleKind
            else {
                break
            }

            idleStartedAt = min(idleStartedAt, record.timestamp)
        }

        return CheckInTriggerLatestCheckIn(
            timestamp: idleStartedAt,
            kind: .idle(latestIdleKind),
            source: latestRecord.source
        )
    }

    private func activityDateForTriggerRecovery(
        eventDate: Date,
        explicitActivityDate: Date?
    ) -> Date? {
        if let explicitActivityDate {
            return explicitActivityDate
        }

        guard
            let latestCheckIn = latestCheckInRecord(),
            latestCheckIn.kind == "idle",
            let idleKindRawValue = latestCheckIn.idleKind,
            let idleKind = TimeAllocationIdleKind(persistedValue: idleKindRawValue),
            idleKind != .doneForDay
        else {
            return nil
        }

        return currentUserActivityDate(referenceDate: eventDate)
    }

    private static func checkInTriggerLatestCheckIn(
        from record: CheckInRecord
    ) -> CheckInTriggerLatestCheckIn? {
        let kind: CheckInTriggerLatestCheckIn.Kind

        switch record.kind {
        case "project":
            kind = .project
        case "resume":
            kind = .resume
        case "idle":
            guard
                let idleKindRawValue = record.idleKind,
                let idleKind = TimeAllocationIdleKind(persistedValue: idleKindRawValue)
            else {
                return nil
            }
            kind = .idle(idleKind)
        default:
            return nil
        }

        return CheckInTriggerLatestCheckIn(
            timestamp: record.timestamp,
            kind: kind,
            source: record.source
        )
    }

    private func applyTriggerEffects(_ effects: [CheckInTriggerEffect]) {
        guard !effects.isEmpty else {
            return
        }

        for effect in effects {
            switch effect {
            case let .persistIdleCheckIn(timestamp, idleKind, source):
                persistIdleCheckIn(at: timestamp, idleKind: idleKind, source: source)
            }
        }

        try? modelContext.save()
    }

    private func tracePromptIdleThresholdReachedIfNeeded(
        from decision: CheckInTriggerDecision
    ) {
        guard
            decision.triggeredUnansweredPromptIdle,
            let promptIdleMarkAt = decision.runtimeState.pendingIdleStartedAt
        else {
            return
        }

        trace(
            "prompt-idle-threshold-reached",
            metadata: ["promptIdleMarkAt": Self.traceTimestamp(promptIdleMarkAt)]
        )
    }

    private func apply(runtimeState: DerivedRuntimeState) {
        let previousState = DerivedRuntimeState(
            nextCheckInAt: nextCheckInAt,
            isPromptOverdue: isPromptOverdue,
            accountableElapsedInterval: accountableElapsedInterval,
            isSilenced: isSilenced,
            silenceEndsAt: silenceEndsAt,
            isIdlePending: isIdlePending,
            pendingIdleStartedAt: pendingIdleStartedAt,
            pendingIdleEndedAt: pendingIdleEndedAt,
            pendingIdleReason: pendingIdleReason
        )

        nextCheckInAt = runtimeState.nextCheckInAt
        isPromptOverdue = runtimeState.isPromptOverdue
        accountableElapsedInterval = runtimeState.accountableElapsedInterval
        isSilenced = runtimeState.isSilenced
        silenceEndsAt = runtimeState.silenceEndsAt
        isIdlePending = runtimeState.isIdlePending
        pendingIdleStartedAt = runtimeState.pendingIdleStartedAt
        pendingIdleEndedAt = runtimeState.pendingIdleEndedAt
        pendingIdleReason = runtimeState.pendingIdleReason
        pendingIdleDuration = max(
            (runtimeState.pendingIdleEndedAt ?? runtimeState.pendingIdleStartedAt ?? clock.now)
                .timeIntervalSince(runtimeState.pendingIdleStartedAt ?? clock.now),
            0
        )
        if !runtimeState.isPromptOverdue {
            promptPresentedAt = nil
        }
        if !runtimeState.isIdlePending {
            promptProjectSelection = nil
        }

        schedulerStateRecord.nextCheckInAt = runtimeState.nextCheckInAt
        schedulerStateRecord.pendingIdleStartedAt = runtimeState.pendingIdleStartedAt
        schedulerStateRecord.pendingIdleEndedAt = runtimeState.pendingIdleEndedAt
        schedulerStateRecord.pendingIdleReason = runtimeState.pendingIdleReason
        schedulerStateRecord.silenceEndsAt = runtimeState.silenceEndsAt

        if modelContext.hasChanges {
            try? modelContext.save()
        }

        if previousState != runtimeState {
            trace(
                "runtime-state-applied",
                metadata: [
                    "previous": previousState.traceSummary,
                    "current": runtimeState.traceSummary
                ]
            )
        }

        schedulePromptTimerIfNeeded()
    }

    private func rescheduleNextCheckInFromSettingsChange(at referenceDate: Date) {
        let pollingInterval = TimeInterval(settings.pollingIntervalMinutes * 60)
        apply(runtimeState: DerivedRuntimeState(
            nextCheckInAt: referenceDate.addingTimeInterval(pollingInterval),
            isPromptOverdue: false,
            accountableElapsedInterval: pollingInterval,
            isSilenced: false,
            silenceEndsAt: nil,
            isIdlePending: false,
            pendingIdleStartedAt: nil,
            pendingIdleEndedAt: nil,
            pendingIdleReason: nil
        ))
    }

    private func latestSchedulingAnchorDate() -> Date? {
        latestCheckInRecord()?.timestamp
    }

    private var shouldPresentPendingIdlePrompt: Bool {
        isIdlePending && pendingIdleEndedAt != nil
    }

    private var shouldPresentUnansweredIdlePrompt: Bool {
        isIdlePending && pendingIdleEndedAt == nil && pendingIdleReason == "unanswered-prompt"
    }

    private var isPromptInteractionActive: Bool {
        checkInPromptState.isPresented || isIdlePending
    }

    private var shouldTreatPromptSelectionAsFreshCheckIn: Bool {
        shouldPresentUnansweredIdlePrompt
    }

    private func schedulePromptTimerIfNeeded() {
        scheduledPromptTimer?.invalidate()
        scheduledPromptTimer = nil

        guard let nextRuntimeUpdateAt = nextRuntimeUpdateAt(referenceDate: clock.now) else {
            trace("runtime-timer-cleared", metadata: ["reason": "no-next-update"])
            return
        }

        let interval = nextRuntimeUpdateAt.timeIntervalSince(clock.now)
        guard interval > 0 else {
            trace(
                "runtime-timer-fired-immediately",
                metadata: [
                    "fireAt": Self.traceTimestamp(nextRuntimeUpdateAt),
                    "intervalSeconds": Self.traceInterval(interval)
                ]
            )
            guard !hasQueuedImmediatePromptTimerFire else {
                return
            }

            hasQueuedImmediatePromptTimerFire = true
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.hasQueuedImmediatePromptTimerFire = false
                self.handleScheduledPromptTimerFired()
            }
            return
        }

        trace(
            "runtime-timer-scheduled",
            metadata: [
                "fireAt": Self.traceTimestamp(nextRuntimeUpdateAt),
                "intervalSeconds": Self.traceInterval(interval)
            ]
        )
        scheduledPromptTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleScheduledPromptTimerFired()
            }
        }
    }

    private func handleScheduledPromptTimerFired() {
        hasQueuedImmediatePromptTimerFire = false
        scheduledPromptTimer?.invalidate()
        scheduledPromptTimer = nil
        trace("runtime-timer-fired")
        let decision = checkInTriggerEngine.decide(
            signal: .timerElapsed(
                at: clock.now,
                activityDate: currentUserActivityDate(referenceDate: clock.now)
            ),
            context: makeCheckInTriggerContext()
        )
        applyTriggerEffects(decision.effects)
        apply(runtimeState: decision.runtimeState)
        tracePromptIdleThresholdReachedIfNeeded(from: decision)
        if decision.triggeredUnansweredPromptIdle {
            promptSearchText = ""
            reloadAnalytics()
        }
        refreshCheckInPromptState()
        if decision.shouldPresentPrompt {
            presentCheckInPromptIfNeeded()
        }
    }

    func nextRuntimeUpdateAt(referenceDate: Date) -> Date? {
        if shouldPresentPendingIdlePrompt {
            return nil
        }

        let candidates = [nextCheckInAt, silenceEndsAt].compactMap { $0 }
        if
            !isPromptOverdue,
            let earliestCandidate = candidates.min(),
            earliestCandidate <= referenceDate
        {
            // If a timer fires a few milliseconds early and the runtime state has not yet
            // transitioned to overdue, queue an immediate retry instead of dropping the
            // scheduler on the floor until some unrelated recovery event occurs.
            return earliestCandidate
        }

        if let promptIdleMarkAt, isPromptOverdue {
            return promptIdleMarkAt
        }

        return candidates.filter { $0 > referenceDate }.min()
    }

    private var pendingIdleReasonLabel: String {
        switch pendingIdleReason {
        case "unanswered-prompt":
            return "Unanswered prompt"
        case "screen-locked":
            return "Screen locked"
        default:
            return "Inactive"
        }
    }

    private var promptIdleMarkAt: Date? {
        guard isPromptOverdue, !isIdlePending, let promptPresentedAt else {
            return nil
        }

        return promptPresentedAt.addingTimeInterval(TimeInterval(settings.idleThresholdMinutes * 60))
    }

    func promptSupportingSubtitle(at date: Date) -> String {
        if shouldPresentPendingIdlePrompt {
            return Self.idleSupportingSubtitle(
                duration: pendingIdleDuration(at: date),
                reason: pendingIdleReasonLabel
            )
        }

        if shouldPresentUnansweredIdlePrompt {
            return "Idle is on · unanswered prompt for \(Self.formattedCompactDuration(pendingIdleDuration(at: date)))"
        }

        let elapsed = Self.formattedElapsedText(for: accountableElapsedInterval)
        guard isPromptOverdue else {
            return elapsed
        }

        guard let promptIdleMarkAt else {
            return "\(elapsed) · awaiting response"
        }

        let remaining = max(promptIdleMarkAt.timeIntervalSince(date), 0)
        if remaining <= 0 {
            return "\(elapsed) · marking idle"
        }

        return "\(elapsed) · idle in \(Self.formattedCompactDuration(remaining))"
    }

    private func presentLaunchCheckInPrompt() {
        guard !isSilenced, !isIdlePending else {
            return
        }

        checkInNow()
    }

    private func currentUserActivityDate(referenceDate: Date) -> Date {
        let samples: [(label: String, idleSeconds: TimeInterval)] = Self.userActivityEventSamples.compactMap { sample in
            let idleSeconds = CGEventSource.secondsSinceLastEventType(sample.state, eventType: sample.event)
            guard idleSeconds.isFinite, idleSeconds >= 0 else {
                return nil
            }

            return (label: sample.label, idleSeconds: idleSeconds)
        }
        guard let sample = samples.min(by: { lhs, rhs in lhs.idleSeconds < rhs.idleSeconds }) else {
            trace("activity-sample-invalid", metadata: ["reason": "no-valid-event-samples"])
            return referenceDate
        }

        let activityDate = referenceDate.addingTimeInterval(-sample.idleSeconds)
        trace(
            "activity-sampled",
            metadata: [
                "idleSeconds": Self.traceInterval(sample.idleSeconds),
                "activityDate": Self.traceTimestamp(activityDate),
                "sampleSource": sample.label
            ]
        )
        return activityDate
    }

    private func pendingIdleDuration(at date: Date) -> TimeInterval {
        guard let pendingIdleStartedAt else {
            return 0
        }

        let pendingIdleEndReference = pendingIdleEndedAt ?? date
        return max(pendingIdleEndReference.timeIntervalSince(pendingIdleStartedAt), 0)
    }

    private func persistFreshPromptSelection(for project: ProjectRecord) throws {
        let completionDate = clock.now
        persistProjectCheckIn(project, at: completionDate, source: "check-in")
        try modelContext.save()

        refreshRuntimeState(eventDate: completionDate, activityDate: completionDate)
        reloadAnalytics()
        promptSearchText = ""
        refreshCheckInPromptState()
        dismissCheckInPrompt()
    }

    func recordPromptWindowEvent(_ event: String, metadata: [String: String] = [:]) {
        diagnosticsRecorder.record(component: "CheckInPromptWindowController", event: event, metadata: metadata)
    }

    func recordAnalyticsWindowEvent(_ event: String, metadata: [String: String] = [:]) {
        diagnosticsRecorder.record(
            component: "AnalyticsWindow",
            event: event,
            metadata: metadata.merging(analyticsTraceMetadata()) { _, new in new }
        )
    }

    func registerAnalyticsWindow(_ window: NSWindow) {
        analyticsWindow = window
        window.identifier = NSUserInterfaceItemIdentifier(AppSceneID.analyticsWindow.rawValue)
        recordAnalyticsWindowEvent(
            "window-registered",
            metadata: [
                "windowNumber": "\(window.windowNumber)",
                "title": window.title,
                "isVisible": "\(window.isVisible)"
            ]
        )
    }

    func bringAnalyticsWindowToFront(reason: String) {
        guard let analyticsWindow else {
            recordAnalyticsWindowEvent(
                "window-front-request-missed",
                metadata: ["reason": reason]
            )
            return
        }

        promoteAppForAnalyticsWindowIfNeeded()
        if analyticsWindow.isMiniaturized {
            analyticsWindow.deminiaturize(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        analyticsWindow.orderFrontRegardless()
        analyticsWindow.makeKeyAndOrderFront(nil)
        analyticsWindow.level = .normal

        recordAnalyticsWindowEvent(
            "window-brought-to-front",
            metadata: [
                "reason": reason,
                "windowNumber": "\(analyticsWindow.windowNumber)",
                "isVisible": "\(analyticsWindow.isVisible)",
                "isKeyWindow": "\(analyticsWindow.isKeyWindow)",
                "isMainWindow": "\(analyticsWindow.isMainWindow)",
                "activationPolicy": NSApplication.shared.activationPolicy().rawValue.description
            ]
        )
    }

    func analyticsWindowDidDisappear() {
        recordAnalyticsWindowEvent("window-disappeared")
        restoreAnalyticsActivationPolicyIfNeeded()
    }

    private func promoteAppForAnalyticsWindowIfNeeded() {
        let app = NSApplication.shared
        if priorAnalyticsActivationPolicy == nil {
            priorAnalyticsActivationPolicy = app.activationPolicy()
        }

        if app.activationPolicy() != .regular {
            app.setActivationPolicy(.regular)
            recordAnalyticsWindowEvent(
                "activation-policy-promoted",
                metadata: ["previousPolicy": priorAnalyticsActivationPolicy?.rawValue.description ?? "nil"]
            )
        }
    }

    private func restoreAnalyticsActivationPolicyIfNeeded() {
        guard let priorAnalyticsActivationPolicy else {
            return
        }

        NSApplication.shared.setActivationPolicy(priorAnalyticsActivationPolicy)
        recordAnalyticsWindowEvent(
            "activation-policy-restored",
            metadata: ["restoredPolicy": priorAnalyticsActivationPolicy.rawValue.description]
        )
        self.priorAnalyticsActivationPolicy = nil
    }

    private func trace(_ event: String, metadata: [String: String] = [:]) {
        diagnosticsRecorder.record(
            component: "TempoAppModel",
            event: event,
            metadata: metadata.merging(runtimeTraceMetadata()) { _, new in new }
        )
    }

    private func runtimeTraceMetadata() -> [String: String] {
        [
            "launchState": launchState.rawValue,
            "nextCheckInAt": Self.traceTimestamp(nextCheckInAt),
            "isPromptOverdue": "\(isPromptOverdue)",
            "accountableElapsedSeconds": Self.traceInterval(accountableElapsedInterval),
            "isSilenced": "\(isSilenced)",
            "silenceEndsAt": Self.traceTimestamp(silenceEndsAt),
            "isIdlePending": "\(isIdlePending)",
            "pendingIdleStartedAt": Self.traceTimestamp(pendingIdleStartedAt),
            "pendingIdleEndedAt": Self.traceTimestamp(pendingIdleEndedAt),
            "pendingIdleReason": pendingIdleReason ?? "nil",
            "promptPresented": "\(checkInPromptState.isPresented)"
        ]
    }

    private func analyticsTraceMetadata() -> [String: String] {
        [
            "selectedAnalyticsRange": selectedAnalyticsRange.rawValue,
            "analyticsReferenceDate": Self.traceTimestamp(analyticsReferenceDate),
            "analyticsPeriodStart": Self.traceTimestamp(analyticsPeriod.startDate),
            "analyticsPeriodEnd": Self.traceTimestamp(analyticsPeriod.endDate),
            "analyticsPeriodLabel": analyticsPeriod.label,
            "analyticsProjectSummaryCount": "\(analyticsProjectSummaries.count)",
            "analyticsAllocatedIntervalCount": "\(analyticsAllocatedIntervals.count)",
            "analyticsTotalDurationSeconds": Self.traceInterval(analyticsTotalDuration),
            "canShowNextAnalyticsPeriod": "\(canShowNextAnalyticsPeriod)"
        ]
    }

    private func refreshMenuBarDayAnalytics() {
        let daySnapshot = analyticsStore.summary(
            range: .day,
            referenceDate: menuBarDayReferenceDate,
            calendar: calendar,
            dayCutoffHour: settings.analyticsDayCutoffHour
        )
        let workedProjectSummaries = daySnapshot.projectSummaries.filter { $0.projectID != nil }
        let workedDuration = workedProjectSummaries.reduce(into: 0.0) { total, summary in
            total += summary.totalDuration
        }
        let normalizedWorkedSummaries = workedProjectSummaries.map { summary in
            AnalyticsProjectSummary(
                projectID: summary.projectID,
                projectName: summary.projectName,
                totalDuration: summary.totalDuration,
                percentageOfTotal: workedDuration > 0 ? summary.totalDuration / workedDuration : 0,
                entryCount: summary.entryCount
            )
        }
        let currentDayPeriod = analyticsStore.period(
            for: .day,
            referenceDate: clock.now,
            calendar: calendar,
            dayCutoffHour: settings.analyticsDayCutoffHour
        )

        menuBarDayPeriod = daySnapshot.period
        menuBarDayWorkedDuration = workedDuration
        menuBarDayProjectSummaries = normalizedWorkedSummaries
        menuBarDayCheckIns = daySnapshot.checkIns
        canShowNextMenuBarDay = daySnapshot.period.startDate < currentDayPeriod.startDate
    }

    private func silencePrimaryStatus(at referenceDate: Date, silenceEndsAt: Date) -> String {
        let cutoffTime = Self.formattedClockTime(silenceEndsAt)
        guard let silenceDayDescriptor = silenceDayDescriptor(for: silenceEndsAt, relativeTo: referenceDate) else {
            return "Silenced until \(cutoffTime)"
        }

        return "Silenced until \(silenceDayDescriptor) at \(cutoffTime)"
    }

    private func silenceSecondaryStatus(at referenceDate: Date, silenceEndsAt: Date) -> String {
        let cutoffTime = Self.formattedClockTime(silenceEndsAt)
        guard let silenceDayDescriptor = silenceDayDescriptor(for: silenceEndsAt, relativeTo: referenceDate) else {
            return "Resumes at daily cutoff (\(cutoffTime))"
        }

        if silenceDayDescriptor == "tomorrow" {
            return "Resumes at tomorrow's daily cutoff (\(cutoffTime))"
        }

        return "Resumes at daily cutoff on \(silenceDayDescriptor) (\(cutoffTime))"
    }

    private func silenceDayDescriptor(for silenceEndsAt: Date, relativeTo referenceDate: Date) -> String? {
        if calendar.isDate(silenceEndsAt, inSameDayAs: referenceDate) {
            return nil
        }

        if
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate),
            calendar.isDate(silenceEndsAt, inSameDayAs: tomorrow)
        {
            return "tomorrow"
        }

        return Self.formattedMonthDay(silenceEndsAt)
    }

    nonisolated static func formattedElapsedText(for elapsedDuration: TimeInterval) -> String {
        let elapsedMinutes = max(Int(elapsedDuration / 60), 0)
        return "Elapsed \(elapsedMinutes) min"
    }

    nonisolated static func formattedClockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    nonisolated static func formattedMonthDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    nonisolated static func formattedCompactDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(Int(duration / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }

        return "\(minutes)m"
    }

    nonisolated static func formattedTrackedDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(Int(duration / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    nonisolated static func traceTimestamp(_ date: Date?) -> String {
        guard let date else {
            return "nil"
        }

        return String(format: "%.3f", date.timeIntervalSince1970)
    }

    nonisolated static func traceInterval(_ interval: TimeInterval) -> String {
        String(format: "%.3f", interval)
    }

    nonisolated private static func supportingSubtitle(
        elapsedDuration: TimeInterval,
        isOverdue: Bool
    ) -> String {
        let elapsed = formattedElapsedText(for: elapsedDuration)
        guard isOverdue else {
            return elapsed
        }

        return "\(elapsed) · overdue"
    }

    nonisolated private static func idleSupportingSubtitle(
        duration: TimeInterval,
        reason: String
    ) -> String {
        "\(reason) for \(formattedCompactDuration(duration))"
    }
}

private extension DerivedRuntimeState {
    var traceSummary: String {
        [
            "nextCheckInAt=\(TempoAppModel.traceTimestamp(nextCheckInAt))",
            "isPromptOverdue=\(isPromptOverdue)",
            "accountableElapsedSeconds=\(TempoAppModel.traceInterval(accountableElapsedInterval))",
            "isSilenced=\(isSilenced)",
            "silenceEndsAt=\(TempoAppModel.traceTimestamp(silenceEndsAt))",
            "isIdlePending=\(isIdlePending)",
            "pendingIdleStartedAt=\(TempoAppModel.traceTimestamp(pendingIdleStartedAt))",
            "pendingIdleEndedAt=\(TempoAppModel.traceTimestamp(pendingIdleEndedAt))",
            "pendingIdleReason=\(pendingIdleReason ?? "nil")"
        ].joined(separator: ",")
    }
}

private extension CheckInPromptState {
    var traceSummary: String {
        [
            "isPresented=\(isPresented)",
            "elapsedSeconds=\(TempoAppModel.traceInterval(elapsedDuration))",
            "isOverdue=\(isOverdue)",
            "subtitle=\(supportingSubtitle)"
        ].joined(separator: ",")
    }
}

enum ProjectDeletionError: LocalizedError {
    case hasTrackedTime(String)

    var errorDescription: String? {
        switch self {
        case let .hasTrackedTime(projectName):
            return "Tempo keeps local time entries attached to \(projectName), so it cannot be deleted yet."
        }
    }
}

enum ProjectValidationError: LocalizedError {
    case emptyName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Project names must contain at least one visible character."
        }
    }
}
