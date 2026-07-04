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

    init(baseDelay: Double = 0.4, jitter: Double = 0, batchSize: Int = 0, batchPause: Double = 0) {
        self.baseDelay = max(0, baseDelay)
        self.jitter = max(0, jitter)
        self.batchSize = max(0, batchSize)
        self.batchPause = max(0, batchPause)
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
