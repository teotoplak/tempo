import Foundation
import SwiftData

@Model
final class CheckInRecord {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var kind: String
    var source: String
    var idleKind: String?
    var project: ProjectRecord?
    /// End of the window this check-in commits to, when the user picked a fixed length.
    /// Tempo stays quiet until then and attributes the whole window to this check-in.
    var committedWindowEndsAt: Date?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        kind: String,
        source: String,
        idleKind: String? = nil,
        project: ProjectRecord? = nil,
        committedWindowEndsAt: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.source = source
        self.idleKind = idleKind
        self.project = project
        self.committedWindowEndsAt = committedWindowEndsAt
    }
}
