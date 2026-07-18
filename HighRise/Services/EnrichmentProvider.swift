import Foundation

/// What the app knows about one recipient when asking an online provider for
/// more — assembled from the row's existing cells, nothing else.
struct EnrichmentQuery: Equatable, Sendable {
    var firstName: String?
    var lastName: String?
    var fullName: String?
    var company: String?
    /// A work domain taken from the email address or website column.
    var domain: String?
    var title: String?
    /// The row's current email value (may be blank or invalid — that's
    /// usually why we're asking).
    var email: String?

    /// Whether the row identifies a specific person (vs. just a company).
    var identifiesPerson: Bool {
        (firstName != nil && lastName != nil) || fullName != nil
    }

    /// Whether there's anything at all worth sending to a provider.
    var isAskable: Bool {
        identifiesPerson || company != nil || domain != nil
    }
}

/// What a provider found for one query. All fields optional — a provider
/// returns whatever it has and the engine decides what's usable.
struct EnrichmentFinding: Equatable, Sendable {
    var firstName: String?
    var lastName: String?
    var fullName: String?
    var email: String?
    var title: String?
    var company: String?
    var website: String?
}

/// A pluggable online data source for contact enrichment. `ApolloEnrichmentProvider`
/// is the first implementation; a future web-search or other-vendor provider
/// conforms to the same protocol and slots into the same engine + UI.
///
/// Providers are the *only* place recipient data leaves the machine, and they
/// run only from the explicit "Find & Fill Online" flow — never automatically.
protocol EnrichmentProvider: Sendable {
    /// Shown in the UI ("Search with Apollo") and result attributions.
    var displayName: String { get }

    /// Looks up one recipient. Returns nil when the provider has nothing;
    /// throws for transport/auth failures (surfaced to the user once, not
    /// per-row).
    func enrich(_ query: EnrichmentQuery) async throws -> EnrichmentFinding?
}
