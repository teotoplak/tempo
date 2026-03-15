import Foundation

protocol SchedulerClock {
    var now: Date { get }
}

struct SystemSchedulerClock: SchedulerClock {
    var now: Date { Date() }
}
