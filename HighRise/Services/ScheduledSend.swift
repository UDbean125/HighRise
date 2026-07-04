import Foundation

/// Helpers for app-side scheduled sending.
///
/// Scheduling runs **inside the app**: HighRise holds the messages and fires the
/// send loop at the chosen time. Neither Apple Mail's native Send Later nor
/// Outlook for Mac exposes a scriptable deferred-delivery hook, so there's no
/// way to hand a future-dated message to the client. The upside is that a
/// scheduled run stays fully editable and cancelable until it fires — but the
/// Mac must be awake and HighRise running at that time.
enum ScheduledSend {

    /// Seconds from `now` until `date` (negative if already past).
    static func secondsUntil(_ date: Date, from now: Date) -> Double {
        date.timeIntervalSince(now)
    }

    /// Whether `date` is far enough in the future to schedule (must be ahead of
    /// `now`).
    static func isSchedulable(_ date: Date, from now: Date) -> Bool {
        secondsUntil(date, from: now) > 0
    }
}
