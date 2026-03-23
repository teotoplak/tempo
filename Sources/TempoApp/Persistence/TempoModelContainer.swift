import Foundation
import SQLite3
import SwiftData

enum TempoModelContainer {
    static let storeDirectoryName = "Tempo"
    static let storeFileName = "tempo.store"
    static let legacyStoreFileName = "default.store"

    private static let legacyStoreDirectoryNames = [
        "Tempo",
        "TempoApp",
    ]
    private static let storeFileSuffixes = [
        "",
        "-shm",
        "-wal",
    ]
    private static let requiredTempoTableNames: Set<String> = [
        "ZAPPSETTINGSRECORD",
        "ZCHECKINRECORD",
        "ZPROJECTRECORD",
        "ZSCHEDULERSTATERECORD",
    ]

    static func live() -> ModelContainer {
        makeContainer(isStoredInMemoryOnly: false)
    }

    static func inMemory() -> ModelContainer {
        makeContainer(isStoredInMemoryOnly: true)
    }

    private static func makeContainer(isStoredInMemoryOnly: Bool) -> ModelContainer {
        let schema = makeSchema()

        do {
            let configuration = try makeConfiguration(schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            guard !isStoredInMemoryOnly else {
                fatalError("Failed to create Tempo model container: \(error.localizedDescription)")
            }

            do {
                let storeURL = try persistentStoreURL()
                deleteStoreFilesIfPresent(at: storeURL)
                let configuration = try makeConfiguration(schema: schema, isStoredInMemoryOnly: false)
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

    private static func makeConfiguration(schema: Schema, isStoredInMemoryOnly: Bool) throws -> ModelConfiguration {
        guard !isStoredInMemoryOnly else {
            return ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
        }

        let storeURL = try persistentStoreURL()
        copyLegacyStoreIfNeeded(to: storeURL)

        return ModelConfiguration(
            schema: schema,
            url: storeURL
        )
    }

    static func persistentStoreURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupportURL = try applicationSupportDirectoryURL(fileManager: fileManager)
        let storeDirectoryURL = applicationSupportURL.appending(path: storeDirectoryName, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)
        return persistentStoreURL(applicationSupportURL: applicationSupportURL)
    }

    static func persistentStoreURL(applicationSupportURL: URL) -> URL {
        applicationSupportURL
            .appending(path: storeDirectoryName, directoryHint: .isDirectory)
            .appending(path: storeFileName, directoryHint: .notDirectory)
    }

    static func legacyStoreURLs(applicationSupportURL: URL) -> [URL] {
        var urls = [
            applicationSupportURL.appending(path: legacyStoreFileName, directoryHint: .notDirectory),
        ]

        urls.append(
            contentsOf: legacyStoreDirectoryNames.map { directoryName in
                applicationSupportURL
                    .appending(path: directoryName, directoryHint: .isDirectory)
                    .appending(path: legacyStoreFileName, directoryHint: .notDirectory)
            }
        )

        return urls
    }

    static func copyLegacyStoreIfNeeded(
        to destinationStoreURL: URL,
        fileManager: FileManager = .default
    ) {
        guard let applicationSupportURL = try? applicationSupportDirectoryURL(fileManager: fileManager) else {
            return
        }

        copyLegacyStoreIfNeeded(
            to: destinationStoreURL,
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
    }

    static func copyLegacyStoreIfNeeded(
        to destinationStoreURL: URL,
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) {
        guard !fileManager.fileExists(atPath: destinationStoreURL.path) else {
            return
        }

        for legacyStoreURL in legacyStoreURLs(applicationSupportURL: applicationSupportURL) {
            guard legacyStoreURL.standardizedFileURL != destinationStoreURL.standardizedFileURL else {
                continue
            }

            guard fileManager.fileExists(atPath: legacyStoreURL.path) else {
                continue
            }

            guard appearsToBeTempoStore(at: legacyStoreURL) else {
                continue
            }

            try? fileManager.createDirectory(
                at: destinationStoreURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            deleteStoreFilesIfPresent(at: destinationStoreURL, fileManager: fileManager)

            for suffix in storeFileSuffixes {
                let sourceURL = relatedStoreFileURL(for: legacyStoreURL, suffix: suffix)
                guard fileManager.fileExists(atPath: sourceURL.path) else {
                    continue
                }

                let destinationURL = relatedStoreFileURL(for: destinationStoreURL, suffix: suffix)
                try? fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
            return
        }
    }

    static func appearsToBeTempoStore(at storeURL: URL) -> Bool {
        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let database {
                sqlite3_close(database)
            }
            return false
        }
        defer {
            sqlite3_close(database)
        }

        let query = "SELECT name FROM sqlite_master WHERE type = 'table';"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer {
            sqlite3_finalize(statement)
        }

        var tableNames = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawName = sqlite3_column_text(statement, 0) else {
                continue
            }

            tableNames.insert(String(cString: rawName))
        }

        return requiredTempoTableNames.isSubset(of: tableNames)
    }

    private static func applicationSupportDirectoryURL(fileManager: FileManager) throws -> URL {
        guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        return applicationSupportURL
    }

    private static func deleteStoreFilesIfPresent(at storeURL: URL, fileManager: FileManager = .default) {
        for fileURL in relatedStoreFileURLs(for: storeURL) where fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private static func relatedStoreFileURLs(for storeURL: URL) -> [URL] {
        storeFileSuffixes.map { relatedStoreFileURL(for: storeURL, suffix: $0) }
    }

    private static func relatedStoreFileURL(for storeURL: URL, suffix: String) -> URL {
        guard !suffix.isEmpty else {
            return storeURL
        }

        return URL(fileURLWithPath: storeURL.path + suffix)
    }
}
