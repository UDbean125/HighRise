import Testing
import Foundation
@testable import HighRise

/// The scheduling presets arm a real send, so their date math is pinned —
/// deterministically, with a fixed UTC calendar and reference date.
struct SendSchedulerTests {

    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// Reference: Monday, 6 Jul 2026, 14:30 UTC.
    private var reference: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 6,
                                           hour: 14, minute: 30))!
    }

    @Test("In 1 hour adds exactly 3600 seconds")
    func inOneHour() {
        let date = SendScheduler.date(for: .inOneHour, from: reference, calendar: calendar)
        #expect(date == reference.addingTimeInterval(3600))
    }

    @Test("Tomorrow morning is the next day at 09:00")
    func tomorrowMorning() {
        let date = SendScheduler.date(for: .tomorrowMorning, from: reference, calendar: calendar)
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(c.year == 2026)
        #expect(c.month == 7)
        #expect(c.day == 7)          // day after the 6th
        #expect(c.hour == 9)
        #expect(c.minute == 0)
    }

    @Test("Next Monday morning lands on a Monday at 09:00, in the future")
    func nextMondayMorning() {
        let date = SendScheduler.date(for: .nextMondayMorning, from: reference, calendar: calendar)
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        #expect(c.weekday == 2)      // Monday
        #expect(c.hour == 9)
        #expect(c.minute == 0)
        // Reference is itself Monday afternoon, so 9 AM has passed → next week.
        #expect(date > reference)
    }

    @Test("Every preset produces a strictly future date")
    func alwaysFuture() {
        for preset in SendSchedulePreset.allCases {
            let date = SendScheduler.date(for: preset, from: reference, calendar: calendar)
            #expect(date > reference, "\(preset.rawValue) should be in the future")
        }
    }
}
