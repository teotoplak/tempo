import Foundation
import SwiftData

@Model
final class ProjectRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var sortOrder: Int

    var checkIns: [CheckInRecord]
    var timeEntries: [TimeEntryRecord]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        sortOrder: Int = 0,
        checkIns: [CheckInRecord] = [],
        timeEntries: [TimeEntryRecord] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.checkIns = checkIns
        self.timeEntries = timeEntries
    }
}
