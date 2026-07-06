import Foundation

/// A tiny live-typing aid for the subject line: how many characters it is, and
/// whether it's long enough to risk being clipped in a recipient's inbox
/// (~60 characters is the common cut-off). Pure, so the count and threshold are
/// unit-tested; counts grapheme clusters, so emoji and accents count as one.
enum SubjectStats {

    /// Where most inbox list views start truncating the subject.
    static let clipThreshold = 60

    struct Stats: Equatable {
        let characters: Int
        let isLong: Bool
    }

    static func of(_ subject: String) -> Stats {
        let count = subject.count
        return Stats(characters: count, isLong: count > clipThreshold)
    }
}
