import Foundation

/// Works out the single most useful next action from the current state, so the
/// Home dashboard can lead with one clear "do this next" call-to-action instead
/// of leaving the user to figure out where they are in the flow. Pure and
/// deterministic; the priority order and wording are unit-tested.
enum NextStep {

    /// The stage the suggestion points at. `done` means there's nothing pressing
    /// to do — the last run finished.
    enum Action: Equatable { case compose, contacts, review, send, done }

    struct Suggestion: Equatable {
        let action: Action
        let title: String
        let detail: String
    }

    /// Priority, highest first: you can't import before there's a message, can't
    /// review before there's a list, can't send before rows are ready.
    static func suggest(hasTemplate: Bool, contactCount: Int,
                        readyCount: Int, hasSent: Bool) -> Suggestion {
        if !hasTemplate {
            return Suggestion(action: .compose,
                              title: "Write your email",
                              detail: "Compose a message with merge fields, or start from a ready-made template.")
        }
        if contactCount == 0 {
            return Suggestion(action: .contacts,
                              title: "Import your contacts",
                              detail: "Add the list of people you're emailing — a CSV or Excel file, or your address book.")
        }
        if readyCount == 0 {
            return Suggestion(action: .review,
                              title: "A few recipients need attention",
                              detail: "Your list is in, but no rows are ready yet. Review shows exactly what's holding each one back.")
        }
        if !hasSent {
            let count = readyCount == 1 ? "1 message is ready" : "\(readyCount) messages are ready"
            return Suggestion(action: .review,
                              title: "Review & send",
                              detail: "\(count) to go out. Preview them, then send or save as drafts.")
        }
        return Suggestion(action: .done,
                          title: "You're all set",
                          detail: "Your last run is complete — start a new email whenever you're ready.")
    }
}
