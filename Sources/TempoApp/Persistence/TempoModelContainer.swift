import SwiftData

enum TempoModelContainer {
    static func live() -> ModelContainer {
        makeContainer(isStoredInMemoryOnly: false)
    }

    static func inMemory() -> ModelContainer {
        makeContainer(isStoredInMemoryOnly: true)
    }

    private static func makeContainer(isStoredInMemoryOnly: Bool) -> ModelContainer {
        let schema = Schema([
            ProjectRecord.self,
            AppSettingsRecord.self,
            SchedulerStateRecord.self,
            TimeEntryRecord.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create Tempo model container: \(error.localizedDescription)")
        }
    }
}
