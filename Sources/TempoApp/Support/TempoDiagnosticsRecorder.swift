import AppKit
import Foundation

final class TempoDiagnosticsRecorder: @unchecked Sendable {
    private struct Entry: Encodable {
        let timestamp: String
        let component: String
        let event: String
        let metadata: [String: String]
    }

    private let lock = NSLock()
    private let maxFileSizeBytes: UInt64

    let logDirectoryURL: URL?
    let logFileURL: URL?
    let archivedLogFileURL: URL?

    init(baseDirectoryURL: URL?, maxFileSizeBytes: UInt64 = 512_000) {
        self.maxFileSizeBytes = maxFileSizeBytes

        guard let baseDirectoryURL else {
            self.logDirectoryURL = nil
            self.logFileURL = nil
            self.archivedLogFileURL = nil
            return
        }

        let diagnosticsDirectoryURL = baseDirectoryURL.appendingPathComponent("Diagnostics", isDirectory: true)
        self.logDirectoryURL = diagnosticsDirectoryURL
        self.logFileURL = diagnosticsDirectoryURL.appendingPathComponent("tempo-trace.jsonl")
        self.archivedLogFileURL = diagnosticsDirectoryURL.appendingPathComponent("tempo-trace.previous.jsonl")
        prepareLogDirectoryIfNeeded()
    }

    static func makeDefault() -> TempoDiagnosticsRecorder {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return TempoDiagnosticsRecorder(baseDirectoryURL: nil)
        }

        let baseDirectoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Tempo", isDirectory: true)
        return TempoDiagnosticsRecorder(baseDirectoryURL: baseDirectoryURL)
    }

    var logFilePath: String? {
        logFileURL?.path
    }

    func record(component: String, event: String, metadata: [String: String] = [:]) {
        guard let logFileURL else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        autoreleasepool {
            let fileManager = FileManager()
            prepareLogDirectoryIfNeeded(fileManager: fileManager)
            rotateLogIfNeeded(fileManager: fileManager)

            let entry = Entry(
                timestamp: Self.traceTimestamp(Date()),
                component: component,
                event: event,
                metadata: metadata
            )

            let encoder = JSONEncoder()
            guard var data = try? encoder.encode(entry) else {
                return
            }

            data.append(0x0A)

            if !fileManager.fileExists(atPath: logFileURL.path) {
                fileManager.createFile(atPath: logFileURL.path, contents: nil)
            }

            guard let fileHandle = try? FileHandle(forWritingTo: logFileURL) else {
                return
            }

            defer {
                try? fileHandle.close()
            }

            do {
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: data)
            } catch {
                return
            }
        }
    }

    @discardableResult
    func revealLogInFinder() -> Bool {
        guard let logFileURL else {
            return false
        }

        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager()
        prepareLogDirectoryIfNeeded(fileManager: fileManager)
        if !fileManager.fileExists(atPath: logFileURL.path) {
            fileManager.createFile(atPath: logFileURL.path, contents: nil)
        }

        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
        return true
    }

    private func prepareLogDirectoryIfNeeded() {
        prepareLogDirectoryIfNeeded(fileManager: FileManager())
    }

    private func prepareLogDirectoryIfNeeded(fileManager: FileManager) {
        guard let logDirectoryURL else {
            return
        }

        try? fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }

    private func rotateLogIfNeeded() {
        rotateLogIfNeeded(fileManager: FileManager())
    }

    private func rotateLogIfNeeded(fileManager: FileManager) {
        guard
            let logFileURL,
            let archivedLogFileURL,
            let fileAttributes = try? fileManager.attributesOfItem(atPath: logFileURL.path),
            let fileSize = fileAttributes[.size] as? NSNumber,
            fileSize.uint64Value >= maxFileSizeBytes
        else {
            return
        }

        try? fileManager.removeItem(at: archivedLogFileURL)
        try? fileManager.moveItem(at: logFileURL, to: archivedLogFileURL)
        fileManager.createFile(atPath: logFileURL.path, contents: nil)
    }

    private static func traceTimestamp(_ date: Date) -> String {
        String(format: "%.3f", date.timeIntervalSince1970)
    }
}
