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
    var selectedPromptProjectID: UUID?
    var checkInPromptState = CheckInPromptState.hidden
    var promptSearchText = ""
    var selectedAnalyticsRange: AnalyticsRange = .day
    var analyticsPeriod: AnalyticsPeriod
    var analyticsTotalDuration: TimeInterval = 0
    var analyticsProjectSummaries: [AnalyticsProjectSummary] = []
    var analyticsFirstEntryStartDate: Date?
    var analyticsTimelineIntervals: [AnalyticsTimelineInterval] = []
    var menuBarDayPeriod: AnalyticsPeriod
    var menuBarDayProjectSummaries: [AnalyticsProjectSummary] = []
    var menuBarDayCheckIns: [TimeAllocationCheckIn] = []
    var analyticsExportStatusMessage: String?
    var analyticsExportErrorMessage: String?
    var launchAtLoginEnabled = false
    var launchAtLoginErrorMessage: String?
    private var lastSavedPollingIntervalMinutes = 25
    private var isMenuBarWindowVisible = false
    private var promptPresentedAt: Date?

    private let clock: any SchedulerClock
    private let calendar: Calendar
    private let analyticsStore: AnalyticsStore
    private let csvExportService: CSVExportService
    private let launchAtLoginController: any LaunchAtLoginControlling
    private var hasHandledInitialLaunch = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var checkInPromptWindowController: CheckInPromptWindowController?
    private var scheduledPromptTimer: Timer?

    init(
        modelContainer: ModelContainer? = nil,
        clock: any SchedulerClock = SystemSchedulerClock(),
        calendar: Calendar = .current,
        launchAtLoginController: any LaunchAtLoginControlling = SMAppServiceLaunchAtLoginController()
    ) {
        let resolvedContainer = modelContainer ?? TempoModelContainer.live()
        self.modelContainer = resolvedContainer
        self.modelContext = ModelContext(resolvedContainer)
        self.clock = clock
        self.calendar = calendar
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
        refreshAnalytics(referenceDate: clock.now)
        refreshCheckInPromptState()
    }

    func performInitialLaunchIfNeeded() {
        guard !hasHandledInitialLaunch else {
            return
        }

        hasHandledInitialLaunch = true
        observeWorkspaceWake()
        syncLaunchAtLoginPreferenceFromSystem()
        recoverSchedulerState(eventDate: clock.now)
        refreshAnalytics(referenceDate: clock.now)
        presentLaunchCheckInPrompt()
    }

    func syncLaunchAtLoginPreferenceFromSystem() {
        let isEnabled = launchAtLoginController.isEnabled
        launchAtLoginEnabled = isEnabled
        settings.launchAtLoginEnabled = isEnabled
        launchAtLoginErrorMessage = nil
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
        let resolvedActivityDate = activityDate ?? currentUserActivityDate(referenceDate: now)
        recoverSchedulerState(eventDate: now, activityDate: resolvedActivityDate)
    }

    func handleAppWake() {
        recoverSchedulerState(eventDate: clock.now, activityDate: clock.now)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func attachCheckInPromptWindowController(_ controller: CheckInPromptWindowController) {
        checkInPromptWindowController = controller
        controller.bind(appModel: self)
        controller.update(with: checkInPromptState)
    }

    func setMenuBarWindowVisible(_ isVisible: Bool) {
        guard isMenuBarWindowVisible != isVisible else {
            return
        }

        isMenuBarWindowVisible = isVisible

        if isVisible {
            let now = clock.now
            let activityDate = currentUserActivityDate(referenceDate: now)
            recoverSchedulerState(eventDate: now, activityDate: activityDate)
        }

        checkInPromptWindowController?.update(with: checkInPromptState)
    }

    func refreshCheckInPromptState() {
        ensureIdleSelectionDefaults()
        let shouldPresent = isPromptOverdue || shouldPresentPendingIdlePrompt || shouldPresentUnansweredIdlePrompt
        let promptTitle = "What are you currently doing"
        let supportingSubtitle = promptSupportingSubtitle(at: clock.now)
        checkInPromptState = CheckInPromptState(
            isPresented: shouldPresent,
            elapsedDuration: accountableElapsedInterval,
            isOverdue: isPromptOverdue,
            promptTitle: promptTitle,
            supportingSubtitle: supportingSubtitle
        )
        checkInPromptWindowController?.update(with: checkInPromptState)
    }

    func presentCheckInPromptIfNeeded() {
        refreshCheckInPromptState()
        if checkInPromptState.isPresented,
           !isIdlePending,
           promptPresentedAt == nil {
            promptPresentedAt = clock.now
            refreshCheckInPromptState()
        }
        checkInPromptWindowController?.update(with: checkInPromptState)
    }

    func dismissCheckInPrompt() {
        checkInPromptState.isPresented = false
        checkInPromptWindowController?.hide()
        schedulePromptTimerIfNeeded()
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
            return "Silenced until \(Self.formattedClockTime(silenceEndsAt))"
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
            return "Resumes at daily cutoff (\(Self.formattedClockTime(silenceEndsAt)))"
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
        let trimmedQuery = promptSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return
        }

        if canCreatePromptProject(named: trimmedQuery) {
            try createAndSelectProjectForPrompt(named: trimmedQuery)
            return
        }

        if isIdlePending {
            if let selectedPromptProject {
                try assignPendingIdle(to: selectedPromptProject)
            }
            return
        }

        if let selectedPromptProject {
            try selectProjectForPrompt(selectedPromptProject)
        }
    }

    func createProject(named name: String) throws {
        _ = try createProjectRecord(named: name)
    }

    func selectAnalyticsRange(_ range: AnalyticsRange) {
        selectedAnalyticsRange = range
        refreshAnalytics(referenceDate: clock.now)
    }

    func selectProjectForPrompt(_ project: ProjectRecord) throws {
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
        let project = try createProjectRecord(named: name)
        if shouldTreatPromptSelectionAsFreshCheckIn {
            try persistFreshPromptSelection(for: project)
            return
        }

        if isIdlePending {
            selectedPromptProjectID = project.id
            promptSearchText = ""
            refreshCheckInPromptState()
            return
        }

        try selectProjectForPrompt(project)
    }

    func silenceForRestOfDay() throws {
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

    func endSilenceMode() throws {
        persistResumeCheckIn(at: clock.now, source: "unsilence")
        try modelContext.save()

        refreshRuntimeState(eventDate: clock.now, activityDate: clock.now)
        refreshCheckInPromptState()
    }

    func checkInNow() {
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
        refreshAnalytics(referenceDate: clock.now)
    }

    func discardPendingIdle() throws {
        guard pendingIdleStartedAt != nil, pendingIdleEndedAt != nil else {
            throw IdleResolutionError.noPendingIdle
        }

        persistResumeCheckIn(at: clock.now, source: "idle-discarded")
        try modelContext.save()
        refreshRuntimeState(eventDate: clock.now, activityDate: clock.now)
        refreshAnalytics(referenceDate: clock.now)
    }

    func handleScreenLock() {
        guard latestCheckInRecord()?.kind != "idle" else {
            refreshRuntimeState(eventDate: clock.now)
            return
        }

        persistIdleCheckIn(
            at: clock.now,
            idleKind: .automaticThreshold,
            source: "screen-locked"
        )
        try? modelContext.save()

        refreshRuntimeState(eventDate: clock.now)
        promptSearchText = ""
        refreshCheckInPromptState()
        dismissCheckInPrompt()
    }

    func handleIdleReturn() {
        refreshRuntimeState(eventDate: clock.now, activityDate: clock.now)
        refreshCheckInPromptState()
        presentCheckInPromptIfNeeded()
    }

    func renameProject(_ project: ProjectRecord, to newName: String) throws {
        project.name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        try modelContext.save()
        refreshAnalytics(referenceDate: clock.now)
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

        refreshCheckInPromptState()
    }

    func refreshAnalytics(referenceDate: Date) {
        let snapshot = analyticsStore.summary(
            range: selectedAnalyticsRange,
            referenceDate: referenceDate,
            calendar: calendar,
            dayCutoffHour: settings.analyticsDayCutoffHour
        )
        let daySnapshot = if selectedAnalyticsRange == .day {
            snapshot
        } else {
            analyticsStore.summary(
                range: .day,
                referenceDate: referenceDate,
                calendar: calendar,
                dayCutoffHour: settings.analyticsDayCutoffHour
            )
        }
        analyticsPeriod = snapshot.period
        analyticsTotalDuration = snapshot.totalDuration
        analyticsProjectSummaries = snapshot.projectSummaries
        analyticsFirstEntryStartDate = snapshot.firstEntryStartDate
        analyticsTimelineIntervals = snapshot.timelineIntervals
        menuBarDayPeriod = daySnapshot.period
        menuBarDayProjectSummaries = daySnapshot.projectSummaries
        menuBarDayCheckIns = daySnapshot.checkIns
    }

    func exportAnalyticsCSV() {
        analyticsExportStatusMessage = nil
        analyticsExportErrorMessage = nil

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
                referenceDate: clock.now,
                dayCutoffHour: settings.analyticsDayCutoffHour
            )
            try csv.write(to: destinationURL, atomically: true, encoding: .utf8)
            analyticsExportStatusMessage = "CSV exported"
        } catch {
            analyticsExportErrorMessage = error.localizedDescription
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
        let filteredProjects = filteredPromptProjects
        let trimmedQuery = promptSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if filteredProjects.isEmpty {
            selectedPromptProjectID = preferredPromptProject()?.id
            return
        }

        if trimmedQuery.isEmpty {
            let preferredProjectID = preferredPromptProject()?.id ?? filteredProjects.first?.id
            selectedPromptProjectID = preferredProjectID
            return
        }

        if let exactMatch = filteredProjects.first(where: { project in
            project.name.compare(trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            selectedPromptProjectID = exactMatch.id
            return
        }

        if let selectedPromptProjectID, filteredProjects.contains(where: { $0.id == selectedPromptProjectID }) {
            return
        }

        selectedPromptProjectID = filteredProjects.first?.id
    }

    private func ensureIdleSelectionDefaults() {
        guard isIdlePending else {
            return
        }

        let projects = filteredPromptProjects.isEmpty ? recentPromptProjects : filteredPromptProjects

        if selectedPromptProject == nil {
            selectedPromptProjectID = preferredPromptProject(in: projects)?.id
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
                self?.handleScreenLock()
            }
        })
        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenLock()
            }
        })
        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleIdleReturn()
            }
        })
    }

    func recoverSchedulerState(eventDate: Date, activityDate: Date? = nil) {
        refreshRuntimeState(eventDate: eventDate, activityDate: activityDate)
        refreshCheckInPromptState()
        launchState = .ready
    }

    private func refreshRuntimeState(eventDate: Date, activityDate: Date? = nil) {
        apply(runtimeState: deriveRuntimeState(eventDate: eventDate, activityDate: activityDate))
    }

    private func deriveRuntimeState(eventDate: Date, activityDate: Date? = nil) -> DerivedRuntimeState {
        let pollingInterval = TimeInterval(settings.pollingIntervalMinutes * 60)

        guard let latestCheckIn = latestCheckInRecord() else {
            if let scheduledCheckInAt = schedulerStateRecord.nextCheckInAt ?? nextCheckInAt {
                let isPromptOverdue = eventDate >= scheduledCheckInAt
                let referenceStart = scheduledCheckInAt.addingTimeInterval(-pollingInterval)
                let accountableElapsedInterval = isPromptOverdue
                    ? max(eventDate.timeIntervalSince(referenceStart), pollingInterval)
                    : pollingInterval

                return DerivedRuntimeState(
                    nextCheckInAt: scheduledCheckInAt,
                    isPromptOverdue: isPromptOverdue,
                    accountableElapsedInterval: accountableElapsedInterval,
                    isSilenced: false,
                    silenceEndsAt: nil,
                    isIdlePending: false,
                    pendingIdleStartedAt: nil,
                    pendingIdleEndedAt: nil,
                    pendingIdleReason: nil
                )
            }

            return DerivedRuntimeState(
                nextCheckInAt: eventDate.addingTimeInterval(pollingInterval),
                isPromptOverdue: false,
                accountableElapsedInterval: pollingInterval,
                isSilenced: false,
                silenceEndsAt: nil,
                isIdlePending: false,
                pendingIdleStartedAt: nil,
                pendingIdleEndedAt: nil,
                pendingIdleReason: nil
            )
        }

        if latestCheckIn.kind == "project" || latestCheckIn.kind == "resume" {
            let nextCheckInAt = latestCheckIn.timestamp.addingTimeInterval(pollingInterval)
            let isPromptOverdue = eventDate >= nextCheckInAt
            let accountableElapsedInterval = isPromptOverdue
                ? max(eventDate.timeIntervalSince(latestCheckIn.timestamp), pollingInterval)
                : pollingInterval

            return DerivedRuntimeState(
                nextCheckInAt: nextCheckInAt,
                isPromptOverdue: isPromptOverdue,
                accountableElapsedInterval: accountableElapsedInterval,
                isSilenced: false,
                silenceEndsAt: nil,
                isIdlePending: false,
                pendingIdleStartedAt: nil,
                pendingIdleEndedAt: nil,
                pendingIdleReason: nil
            )
        }

        guard
            latestCheckIn.kind == "idle",
            let idleKindRawValue = latestCheckIn.idleKind,
            let idleKind = TimeAllocationIdleKind(persistedValue: idleKindRawValue)
        else {
            return DerivedRuntimeState(
                nextCheckInAt: eventDate.addingTimeInterval(pollingInterval),
                isPromptOverdue: false,
                accountableElapsedInterval: pollingInterval,
                isSilenced: false,
                silenceEndsAt: nil,
                isIdlePending: false,
                pendingIdleStartedAt: nil,
                pendingIdleEndedAt: nil,
                pendingIdleReason: nil
            )
        }

        if idleKind == .doneForDay {
            let silenceEndsAt = nextDayCutoff(after: latestCheckIn.timestamp, dayCutoffHour: settings.analyticsDayCutoffHour)
            let isSilenced = eventDate < silenceEndsAt
            return DerivedRuntimeState(
                nextCheckInAt: nil,
                isPromptOverdue: false,
                accountableElapsedInterval: 0,
                isSilenced: isSilenced,
                silenceEndsAt: isSilenced ? silenceEndsAt : nil,
                isIdlePending: false,
                pendingIdleStartedAt: nil,
                pendingIdleEndedAt: nil,
                pendingIdleReason: nil
            )
        }

        let resolvedActivityDate = activityDate ?? currentUserActivityDate(referenceDate: eventDate)
        let pendingIdleEndedAt = resolvedActivityDate > latestCheckIn.timestamp ? resolvedActivityDate : nil

        return DerivedRuntimeState(
            nextCheckInAt: nil,
            isPromptOverdue: false,
            accountableElapsedInterval: 0,
            isSilenced: false,
            silenceEndsAt: nil,
            isIdlePending: true,
            pendingIdleStartedAt: latestCheckIn.timestamp,
            pendingIdleEndedAt: pendingIdleEndedAt,
            pendingIdleReason: latestCheckIn.source
        )
    }

    private func apply(runtimeState: DerivedRuntimeState) {
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
            selectedPromptProjectID = nil
        }

        schedulerStateRecord.nextCheckInAt = runtimeState.nextCheckInAt
        schedulerStateRecord.pendingIdleStartedAt = runtimeState.pendingIdleStartedAt
        schedulerStateRecord.pendingIdleEndedAt = runtimeState.pendingIdleEndedAt
        schedulerStateRecord.pendingIdleReason = runtimeState.pendingIdleReason
        schedulerStateRecord.silenceEndsAt = runtimeState.silenceEndsAt

        if modelContext.hasChanges {
            try? modelContext.save()
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

    private func nextDayCutoff(after date: Date, dayCutoffHour: Int) -> Date {
        let shiftedDate = calendar.date(byAdding: .hour, value: -dayCutoffHour, to: date) ?? date
        let shiftedStartOfDay = calendar.startOfDay(for: shiftedDate)
        let nextShiftedDay = calendar.date(byAdding: .day, value: 1, to: shiftedStartOfDay) ?? shiftedStartOfDay
        return calendar.date(byAdding: .hour, value: dayCutoffHour, to: nextShiftedDay) ?? nextShiftedDay
    }

    private var shouldPresentPendingIdlePrompt: Bool {
        isIdlePending && pendingIdleEndedAt != nil
    }

    private var shouldPresentUnansweredIdlePrompt: Bool {
        isIdlePending && pendingIdleEndedAt == nil && pendingIdleReason == "unanswered-prompt"
    }

    private var shouldTreatPromptSelectionAsFreshCheckIn: Bool {
        shouldPresentUnansweredIdlePrompt
    }

    private func schedulePromptTimerIfNeeded() {
        scheduledPromptTimer?.invalidate()
        scheduledPromptTimer = nil

        guard let nextRuntimeUpdateAt = nextRuntimeUpdateAt(referenceDate: clock.now) else {
            return
        }

        let interval = nextRuntimeUpdateAt.timeIntervalSince(clock.now)
        guard interval > 0 else {
            handleScheduledPromptTimerFired()
            return
        }

        scheduledPromptTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleScheduledPromptTimerFired()
            }
        }
    }

    private func handleScheduledPromptTimerFired() {
        scheduledPromptTimer?.invalidate()
        scheduledPromptTimer = nil
        if handlePromptIdleThresholdReachedIfNeeded(referenceDate: clock.now) {
            return
        }
        recoverSchedulerState(eventDate: clock.now)
        presentCheckInPromptIfNeeded()
    }

    func nextRuntimeUpdateAt(referenceDate: Date) -> Date? {
        if shouldPresentPendingIdlePrompt {
            return nil
        }

        if let promptIdleMarkAt, isPromptOverdue {
            return promptIdleMarkAt
        }

        let candidates = [nextCheckInAt, silenceEndsAt].compactMap { $0 }
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
        guard isPromptOverdue, !isIdlePending, let nextCheckInAt else {
            return nil
        }

        return nextCheckInAt.addingTimeInterval(TimeInterval(settings.idleThresholdMinutes * 60))
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

    @discardableResult
    private func handlePromptIdleThresholdReachedIfNeeded(referenceDate: Date) -> Bool {
        guard let promptIdleMarkAt, referenceDate >= promptIdleMarkAt else {
            return false
        }

        guard latestCheckInRecord()?.kind != "idle" else {
            refreshRuntimeState(eventDate: referenceDate)
            return false
        }

        persistIdleCheckIn(
            at: promptIdleMarkAt,
            idleKind: .unansweredPrompt,
            source: "unanswered-prompt"
        )
        try? modelContext.save()

        refreshRuntimeState(eventDate: referenceDate)
        promptSearchText = ""
        refreshCheckInPromptState()
        presentCheckInPromptIfNeeded()
        refreshAnalytics(referenceDate: referenceDate)
        return true
    }

    private func currentUserActivityDate(referenceDate: Date) -> Date {
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        guard idleSeconds.isFinite, idleSeconds >= 0 else {
            return referenceDate
        }

        return referenceDate.addingTimeInterval(-idleSeconds)
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
        refreshAnalytics(referenceDate: completionDate)
        promptSearchText = ""
        refreshCheckInPromptState()
        dismissCheckInPrompt()
    }

    nonisolated static func formattedElapsedText(for elapsedDuration: TimeInterval) -> String {
        let elapsedMinutes = max(Int(elapsedDuration / 60), 0)
        return "Elapsed \(elapsedMinutes) min"
    }

    nonisolated static func formattedClockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
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
