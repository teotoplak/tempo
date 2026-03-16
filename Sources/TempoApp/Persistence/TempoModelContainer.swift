import Foundation
import SwiftData

enum TempoModelContainer {
    static func live() -> ModelContainer {
        makeContainer(isStoredInMemoryOnly: false)
    }

    static func inMemory() -> ModelContainer {
        makeContainer(isStoredInMemoryOnly: true)
    }

    private static func makeContainer(isStoredInMemoryOnly: Bool) -> ModelContainer {
        let schema = makeSchema()
        let configuration = makeConfiguration(schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            guard !isStoredInMemoryOnly else {
                fatalError("Failed to create Tempo model container: \(error.localizedDescription)")
            }

            deleteDefaultStoreFilesIfPresent()

            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Failed to recover Tempo model container: \(error.localizedDescription)")
            }
        }
    }

    private static func makeSchema() -> Schema {
        let models: [any PersistentModel.Type] = [
            ProjectRecord.self,
            CheckInRecord.self,
            AppSettingsRecord.self,
            SchedulerStateRecord.self,
            TimeEntryRecord.self,
        ]
        return Schema(models)
    }

    private static func makeConfiguration(schema: Schema, isStoredInMemoryOnly: Bool) -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
    }

    private static func deleteDefaultStoreFilesIfPresent() {
        let fileManager = FileManager.default
        guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let candidateDirectories = [
            applicationSupportURL,
            applicationSupportURL.appending(path: "TempoApp", directoryHint: .isDirectory),
        ]

        for directoryURL in candidateDirectories {
            guard let fileURLs = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for fileURL in fileURLs where fileURL.lastPathComponent.hasPrefix("default.store") {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
}
