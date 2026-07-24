import Foundation
@testable import HighRise

@MainActor
extension HighRiseCoordinator {
    /// A coordinator whose persistence is inert (`directory: nil` for both
    /// the session store and the template library), so tests never read a
    /// session or draft left behind by the real app on the developer's
    /// machine — and never write one either.
    static func hermetic() -> HighRiseCoordinator {
        HighRiseCoordinator(sessionStore: SessionStore(directory: nil),
                            library: TemplateLibraryStore(directory: nil))
    }
}
