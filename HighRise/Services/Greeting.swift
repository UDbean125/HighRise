import Foundation

/// A small time-of-day greeting for the Home header, so opening the app feels a
/// little more personal than a static title. Pure — the view passes the current
/// hour — so the wording and the hour boundaries are unit-tested.
enum Greeting {

    /// A greeting for a 24-hour clock hour (0–23):
    /// morning 5–11, afternoon 12–16, evening 17–21, and a neutral "Welcome"
    /// for the late-night hours in between.
    static func forHour(_ hour: Int) -> String {
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Welcome"
        }
    }
}
