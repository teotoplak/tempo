import Foundation
import SwiftData

@MainActor
final class SchedulerStateStore: SchedulerStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func load() -> SchedulerStateRecord? {
        let descriptor = FetchDescriptor<SchedulerStateRecord>()
        return try? modelContext.fetch(descriptor).first
    }

    func save(_ schedulerState: SchedulerStateRecord) throws {
        try modelContext.save()
    }
}
