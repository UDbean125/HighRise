import Testing
import Foundation
@testable import HighRise

struct ScheduledSendTests {
    @Test("secondsUntil is positive for the future, negative for the past")
    func secondsUntil() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ScheduledSend.secondsUntil(now.addingTimeInterval(60), from: now) == 60)
        #expect(ScheduledSend.secondsUntil(now.addingTimeInterval(-60), from: now) == -60)
    }

    @Test("Only future dates are schedulable")
    func schedulable() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ScheduledSend.isSchedulable(now.addingTimeInterval(1), from: now))
        #expect(!ScheduledSend.isSchedulable(now, from: now))
        #expect(!ScheduledSend.isSchedulable(now.addingTimeInterval(-1), from: now))
    }
}

/// Scheduling guards that resolve without touching a mail client.
@MainActor
struct ScheduleGuardTests {
    @Test("A past date does not schedule anything")
    func pastDateIgnored() {
        let coordinator = HighRiseCoordinator()
        coordinator.scheduleSend(at: Date().addingTimeInterval(-100))
        #expect(!coordinator.isScheduled)
    }

    @Test("Scheduling with nothing sendable is a no-op")
    func nothingToSchedule() {
        let coordinator = HighRiseCoordinator()   // no contacts imported
        coordinator.scheduleSend(at: Date().addingTimeInterval(3600))
        #expect(!coordinator.isScheduled)
    }
}
