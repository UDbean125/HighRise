import Foundation

/// One-click starting points for the "Schedule for later" picker, so the common
/// choices ("tomorrow morning", "Monday at 9") don't need manual date fiddling.
enum SendSchedulePreset: String, CaseIterable, Identifiable {
    case inOneHour = "In 1 hour"
    case tomorrowMorning = "Tomorrow, 9 AM"
    case nextMondayMorning = "Monday, 9 AM"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .inOneHour:         return "hourglass"
        case .tomorrowMorning:   return "sunrise"
        case .nextMondayMorning: return "calendar"
        }
    }
}

/// Pure date math for the scheduling presets. `reference` and `calendar` are
/// injectable so the "next 9 AM" / "next Monday" logic is deterministic to test
/// across timezones.
enum SendScheduler {

    /// The concrete fire date a preset resolves to, relative to `reference`.
    static func date(for preset: SendSchedulePreset,
                     from reference: Date,
                     calendar: Calendar = .current) -> Date {
        switch preset {
        case .inOneHour:
            return reference.addingTimeInterval(3600)

        case .tomorrowMorning:
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1,
                                                to: calendar.startOfDay(for: reference))
                ?? reference.addingTimeInterval(86_400)
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: startOfTomorrow)
                ?? startOfTomorrow

        case .nextMondayMorning:
            var components = DateComponents()
            components.weekday = 2   // Gregorian: Sunday = 1, Monday = 2
            components.hour = 9
            components.minute = 0
            return calendar.nextDate(after: reference, matching: components,
                                     matchingPolicy: .nextTime)
                ?? reference.addingTimeInterval(86_400)
        }
    }
}
