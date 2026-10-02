import Foundation

/// Two-way hand-off with Hen Contacts (`com.hensolutions.contacts`), the Hen
/// Solutions relationship CRM.
///
/// - **Inbound** — Hen Contacts opens `highrise://import?source=…&csv=…`
///   (base64url-encoded UTF-8 CSV) or, for very large lists,
///   `highrise://import?source=…&from=pasteboard` after placing the CSV on the
///   pasteboard. It can also hand HighRise a `.csv` file (HighRise declares
///   CSV as an "Alternate" document type). Either way the CSV goes through
///   the normal `CSVParser` → import pipeline, so cleanup, email-column
///   detection, do-not-contact and merge behave exactly as for any import.
/// - **Outbound** — after a run, HighRise opens
///   `hencontacts://highrise/log?payload=…` with a base64url JSON `Campaign`
///   so Hen Contacts can journal one "email" interaction per recipient.
///
/// Foundation-only and shared by the macOS and iOS targets. Nothing here
/// touches the network: data moves between the two apps on the device only.
enum HenContactsBridge {
    static let highRiseScheme = "highrise"
    static let henScheme = "hencontacts"
    static let henBundleIdentifier = "com.hensolutions.contacts"
    static let defaultSourceLabel = "Hen Contacts"

    /// A recipient list handed over by Hen Contacts.
    struct InboundImport: Equatable {
        let csvText: String
        let sourceLabel: String
        /// Optional subject suggestion (e.g. the deal or campaign name).
        let subjectHint: String?
    }

    enum BridgeError: LocalizedError, Equatable {
        case missingPayload
        case unreadablePayload

        var errorDescription: String? {
            switch self {
            case .missingPayload:
                return "Hen Contacts didn't include a recipient list. Try “Mail Merge in HighRise” again."
            case .unreadablePayload:
                return "The recipient list from Hen Contacts couldn't be read. Try again, or share the list as a CSV file instead."
            }
        }
    }

    /// Parses a `highrise://import…` link. Returns nil for any URL that isn't
    /// an import link (callers then fall through to their other handling).
    /// `pasteboardText` is only consulted for `from=pasteboard` links, so the
    /// pasteboard is never read unless Hen Contacts asked for it.
    static func inboundImport(from url: URL, pasteboardText: () -> String?) throws -> InboundImport? {
        guard url.scheme?.lowercased() == highRiseScheme, url.host?.lowercased() == "import" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        let source = value("source") ?? defaultSourceLabel
        let subject = value("subject")
        let text: String
        if let encoded = value("csv") {
            guard let data = base64URLDecode(encoded), let decoded = String(data: data, encoding: .utf8) else {
                throw BridgeError.unreadablePayload
            }
            text = decoded
        } else if value("from") == "pasteboard" {
            guard let pasted = pasteboardText(), !pasted.isEmpty else { throw BridgeError.missingPayload }
            text = pasted
        } else {
            throw BridgeError.missingPayload
        }
        return InboundImport(csvText: text, sourceLabel: source, subjectHint: subject)
    }

    /// True when the list came from Hen Contacts, so the results screen can
    /// offer to journal the emails back there.
    static func isHenSource(_ label: String?) -> Bool {
        guard let label else { return false }
        return label.hasPrefix(defaultSourceLabel)
    }

    // MARK: - Outbound

    /// One mail-merge run, as Hen Contacts records it.
    struct Campaign: Codable, Equatable {
        struct Recipient: Codable, Equatable {
            let email: String
            let name: String
            /// "sent" / "drafted" / "skipped" / "failed"
            let status: String
        }

        var app = "HighRise"
        var subject: String
        /// "send" or "draft"
        var mode: String
        var sentAt: Date
        var sourceLabel: String?
        var recipients: [Recipient]

        var deliveredCount: Int { recipients.filter { $0.status == "sent" || $0.status == "drafted" }.count }
    }

    /// Builds a campaign from run outcomes. Only recipients with an address are included.
    static func campaign(subject: String, mode: String, sourceLabel: String?, sentAt: Date = Date(),
                         outcomes: [(email: String, name: String, status: String)]) -> Campaign {
        Campaign(subject: subject, mode: mode, sentAt: sentAt, sourceLabel: sourceLabel,
                 recipients: outcomes.filter { !$0.email.isEmpty }
                    .map { Campaign.Recipient(email: $0.email, name: $0.name, status: $0.status) })
    }

    /// Maps a `SendOutcome.Status` to the journal's status string.
    static func statusString(_ status: SendOutcome.Status) -> String {
        switch status {
        case .sent: return "sent"
        case .drafted: return "drafted"
        case .skipped: return "skipped"
        case .failed: return "failed"
        }
    }

    /// `hencontacts://highrise/log?payload=…` for a campaign.
    static func logURL(for campaign: Campaign) -> URL? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(campaign) else { return nil }
        var components = URLComponents()
        components.scheme = henScheme
        components.host = "highrise"
        components.path = "/log"
        components.queryItems = [URLQueryItem(name: "payload", value: base64URLEncode(data))]
        return components.url
    }

    /// Decodes a campaign payload (used by tests, and mirrors Hen's decoder).
    static func campaign(fromLogURL url: URL) -> Campaign? {
        guard url.scheme == henScheme, url.host == "highrise",
              let payload = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "payload" })?.value,
              let data = base64URLDecode(payload) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Campaign.self, from: data)
    }

    // MARK: - base64url (RFC 4648 §5, unpadded)

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder > 0 { s += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: s)
    }
}
