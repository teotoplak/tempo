import Foundation
import SwiftData

@Model
final class TimeEntryRecord {
    var project: ProjectRecord?
    var startAt: Date
    var endAt: Date
    var source: String

    init(
        project: ProjectRecord? = nil,
        startAt: Date,
        endAt: Date,
        source: String
    ) {
        self.project = project
        self.startAt = startAt
        self.endAt = endAt
        self.source = source
    }
}
