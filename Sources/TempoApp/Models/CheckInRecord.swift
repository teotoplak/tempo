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

    init(
        id: UUID = UUID(),
        timestamp: Date,
        kind: String,
        source: String,
        idleKind: String? = nil,
        project: ProjectRecord? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.source = source
        self.idleKind = idleKind
        self.project = project
    }
}
