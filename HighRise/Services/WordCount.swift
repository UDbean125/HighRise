import Foundation

/// Word count and a rough reading-time estimate for the email body — a light
/// signal that a message is drifting long (short emails get more replies).
/// Pure, so the counting and rounding are unit-tested.
enum WordCount {

    /// Average adult reading speed; used for the minute estimate.
    static let wordsPerMinute = 200

    struct Stats: Equatable {
        let words: Int
        /// Reading minutes, rounded, floored at 1 once there's any text.
        let minutes: Int
    }

    static func of(_ text: String) -> Stats {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        let minutes = words == 0
            ? 0
            : max(1, Int((Double(words) / Double(wordsPerMinute)).rounded()))
        return Stats(words: words, minutes: minutes)
    }

    /// A caption like "128 words · ~1 min read"; empty when there are no words.
    static func caption(_ stats: Stats) -> String {
        guard stats.words > 0 else { return "" }
        return "\(stats.words) word\(stats.words == 1 ? "" : "s") · ~\(stats.minutes) min read"
    }
}
