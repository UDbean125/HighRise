import Foundation

/// How HighRise paces a live send so bursting through the user's own mailbox
/// doesn't trip spam heuristics or provider rate limits — the worst outcome for
/// a send-through-your-own-account tool is getting the user's primary mailbox
/// throttled or suspended.
///
/// Pure and deterministic apart from jitter, which is supplied by an injectable
/// random source so the schedule can be unit-tested.
struct ThrottlePolicy: Equatable {
    /// Fixed seconds to wait after each message.
    var baseDelay: Double
    /// Maximum extra random seconds added on top of `baseDelay`, to avoid a
    /// perfectly regular cadence (a "humanized" pause, à la Thunderbird).
    var jitter: Double
    /// Pause after every `batchSize` messages; `0` disables batching.
    var batchSize: Int
    /// Seconds to pause once a full batch completes.
    var batchPause: Double
    /// When true, a run stops itself after several consecutive delivery
    /// failures rather than working through an entire list while every
    /// attempt is failing (the mail client crashed, lost its account, or
    /// started rejecting the automation). This reacts to failures the send
    /// loop can see directly — AppleScript exposes no way to read bounces or
    /// spam complaints after a message leaves the Mac, so those downstream
    /// signals aren't and can't be part of this.
    var stopOnRepeatedFailures: Bool

    /// Consecutive failures that trigger an early stop.
    static let consecutiveFailureStopThreshold = 3

    init(baseDelay: Double = 0.4, jitter: Double = 0, batchSize: Int = 0, batchPause: Double = 0,
         stopOnRepeatedFailures: Bool = true) {
        self.baseDelay = max(0, baseDelay)
        self.jitter = max(0, jitter)
        self.batchSize = max(0, batchSize)
        self.batchPause = max(0, batchPause)
        self.stopOnRepeatedFailures = stopOnRepeatedFailures
    }

    /// Whether a run should stop itself given a streak of `consecutiveFailures`.
    func shouldStopEarly(consecutiveFailures: Int) -> Bool {
        stopOnRepeatedFailures && consecutiveFailures >= Self.consecutiveFailureStopThreshold
    }

    /// No pacing at all — send as fast as the client accepts scripts.
    static let immediate = ThrottlePolicy(baseDelay: 0)
    /// A light, slightly irregular gap; a sensible default for small runs.
    static let gentle = ThrottlePolicy(baseDelay: 1, jitter: 1)
    /// Spaced out with a pause every 50 messages, for large lists.
    static let careful = ThrottlePolicy(baseDelay: 2, jitter: 2, batchSize: 50, batchPause: 300)

    /// The delay to wait *after* sending the message at `index` (0-based) before
    /// starting the next, in a run of `count` messages. Zero after the last
    /// message (nothing follows it).
    ///
    /// - Parameter randomFraction: supplies a value in `0..<1` for the jitter
    ///   term; defaults to a real random draw. Injected in tests for determinism.
    func delayAfter(index: Int, count: Int,
                    randomFraction: () -> Double = { Double.random(in: 0..<1) }) -> Double {
        guard index >= 0, index < count - 1 else { return 0 }
        var delay = baseDelay + jitter * randomFraction()
        if batchSize > 0 && (index + 1) % batchSize == 0 {
            delay += batchPause
        }
        return delay
    }

    /// The expected wall-clock seconds a run of `count` messages spends *paused*
    /// (the scripted send itself is near-instant per message). Uses the mean
    /// jitter — half its maximum — since each real per-message draw is random.
    /// Matches the sum of `delayAfter` in expectation, so the Send screen's
    /// estimate lines up with what actually happens.
    func expectedDuration(forCount count: Int) -> Double {
        guard count > 1 else { return 0 }
        let gaps = count - 1
        var total = Double(gaps) * (baseDelay + jitter / 2)
        if batchSize > 0 {
            total += Double(gaps / batchSize) * batchPause
        }
        return total
    }

    /// A compact human label for a duration in seconds ("instant", "~45s",
    /// "~3 min", "~1 hr 5 min").
    static func humanDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total <= 0 { return "instant" }
        if total < 60 { return "~\(total)s" }
        let minutes = total / 60
        if minutes < 60 {
            let rem = total % 60
            return rem == 0 ? "~\(minutes) min" : "~\(minutes) min \(rem)s"
        }
        let hours = minutes / 60
        let remMin = minutes % 60
        return remMin == 0 ? "~\(hours) hr" : "~\(hours) hr \(remMin) min"
    }
}

/// The mail provider behind the user's account, used only to warn when a run
/// looks likely to exceed the provider's rough daily sending cap. Caps are
/// approximate and change over time — the point is a heads-up, not enforcement.
enum SendingProvider: String, CaseIterable, Identifiable {
    case gmailPersonal = "Gmail (personal)"
    case googleWorkspace = "Google Workspace"
    case iCloud = "iCloud Mail"
    case outlookCom = "Outlook.com"
    case microsoft365 = "Microsoft 365"
    case other = "Other / not sure"

    var id: String { rawValue }

    /// Approximate messages-per-day the provider allows before rejecting or
    /// throttling. `nil` when unknown (no warning is shown).
    var approximateDailyCap: Int? {
        switch self {
        case .gmailPersonal:  return 500
        case .googleWorkspace: return 2000
        case .iCloud:         return 1000
        case .outlookCom:     return 300
        case .microsoft365:   return 10000
        case .other:          return nil
        }
    }

    /// A warning when `recipientCount` exceeds this provider's daily cap, or
    /// `nil` when it's within limits or the cap is unknown.
    func quotaWarning(forRecipientCount recipientCount: Int) -> String? {
        guard let cap = approximateDailyCap, recipientCount > cap else { return nil }
        return "\(recipientCount) recipients is over \(rawValue)'s roughly \(cap)/day limit. "
            + "Split the run across days, or your provider may reject or temporarily suspend sending."
    }
}
