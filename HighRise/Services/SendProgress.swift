import Foundation

/// The live caption for the Send progress bar — turns the coordinator's 0…1
/// `sendProgress` fraction and the run size into "Sending 12 of 42…" (or
/// "Drafting 5 of 10…"), so a long throttled run shows how far along it is, not
/// just an anonymous bar. Pure; the rounding, clamping, and wording are
/// unit-tested.
enum SendProgress {

    static func caption(fraction: Double, total: Int, mode: SendMode) -> String {
        let verb = mode == .send ? "Sending" : "Drafting"
        guard total > 0 else { return "\(verb)…" }
        let raw = Int((fraction * Double(total)).rounded())
        let done = min(total, max(0, raw))
        return "\(verb) \(done) of \(total)…"
    }
}
