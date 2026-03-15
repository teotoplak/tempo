import Foundation
import SwiftData

@Model
final class ProjectRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var sortOrder: Int

    @Relationship(deleteRule: .nullify, inverse: \TimeEntryRecord.project)
    var timeEntries: [TimeEntryRecord]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        sortOrder: Int = 0,
        timeEntries: [TimeEntryRecord] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.timeEntries = timeEntries
    }
}
