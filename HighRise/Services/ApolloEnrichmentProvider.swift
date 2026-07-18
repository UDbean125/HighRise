import Foundation

/// Contact enrichment backed by Apollo.io's REST API — the sanctioned way to
/// get the business emails/titles Apollo aggregates (including from public
/// LinkedIn data), as opposed to scraping LinkedIn directly, which its terms
/// prohibit and which breaks without warning.
///
/// Strategy per row:
/// - A row that already names a **person** (first+last or full name, ideally
///   with a company/domain) goes straight to `people/match`, which returns
///   the person's business email when Apollo has it.
/// - A row that names only a **company** (plus, ideally, a title like
///   "Director of Engineering") first runs a one-result `mixed_people/search`
///   scoped to that company/title to pick a person, then `people/match` on
///   that person to reveal the email.
///
/// Requires the user's own Apollo API key (Settings → Integrations → API in
/// Apollo). Results and rate limits depend on their Apollo plan; a match
/// consumes Apollo credits like any other Apollo export.
struct ApolloEnrichmentProvider: EnrichmentProvider {
    var displayName: String { "Apollo" }

    let apiKey: String
    var session: URLSession = .shared

    enum ProviderError: LocalizedError {
        case badKey
        case rateLimited
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .badKey:
                return "Apollo rejected the API key. Check it in Apollo under Settings → Integrations → API."
            case .rateLimited:
                return "Apollo's rate limit was hit — wait a minute and run the search again; already-found rows are kept."
            case .http(let code):
                return "Apollo returned an unexpected error (HTTP \(code))."
            }
        }
    }

    func enrich(_ query: EnrichmentQuery) async throws -> EnrichmentFinding? {
        if query.identifiesPerson {
            return try await match(query)
        }
        // Company-only row: pick the best person at that company first.
        guard let person = try await searchPerson(query) else { return nil }
        var refined = query
        refined.firstName = person.firstName
        refined.lastName = person.lastName
        refined.fullName = person.fullName
        if refined.domain == nil { refined.domain = person.domain }
        // A match reveals the email; fall back to the search result itself
        // if match comes back empty.
        return try await match(refined) ?? person.finding
    }

    // MARK: - Endpoints

    private func match(_ query: EnrichmentQuery) async throws -> EnrichmentFinding? {
        var body: [String: Any] = ["reveal_personal_emails": false]
        if let v = query.firstName { body["first_name"] = v }
        if let v = query.lastName { body["last_name"] = v }
        if let v = query.fullName, query.firstName == nil { body["name"] = v }
        if let v = query.company { body["organization_name"] = v }
        if let v = query.domain { body["domain"] = v }
        if let v = query.email, !v.isEmpty { body["email"] = v }

        let data = try await post(path: "people/match", body: body)
        let decoded = try JSONDecoder().decode(MatchResponse.self, from: data)
        return decoded.person?.finding
    }

    private func searchPerson(_ query: EnrichmentQuery) async throws -> Person? {
        var body: [String: Any] = ["page": 1, "per_page": 1]
        if let company = query.company { body["q_organization_name"] = company }
        if let domain = query.domain { body["q_organization_domains_list"] = [domain] }
        if let title = query.title, !title.isEmpty { body["person_titles"] = [title] }

        let data = try await post(path: "mixed_people/search", body: body)
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.people?.first
    }

    private func post(path: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.apollo.io/api/v1/\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200...299: break
            case 401, 403:  throw ProviderError.badKey
            case 429:       throw ProviderError.rateLimited
            default:        throw ProviderError.http(http.statusCode)
            }
        }
        return data
    }

    // MARK: - Response models

    struct MatchResponse: Decodable {
        let person: Person?
    }

    struct SearchResponse: Decodable {
        let people: [Person]?
    }

    struct Person: Decodable {
        let firstName: String?
        let lastName: String?
        let fullName: String?
        let email: String?
        let title: String?
        let organization: Organization?

        struct Organization: Decodable {
            let name: String?
            let primaryDomain: String?
            let websiteURL: String?

            enum CodingKeys: String, CodingKey {
                case name
                case primaryDomain = "primary_domain"
                case websiteURL = "website_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case firstName = "first_name"
            case lastName = "last_name"
            case fullName = "name"
            case email, title, organization
        }

        var domain: String? { organization?.primaryDomain }

        /// Apollo returns a placeholder for emails your plan hasn't unlocked —
        /// that's not an address anyone can send to, so it reads as "none".
        var usableEmail: String? {
            guard let email, EmailValidator.isValid(email),
                  !email.lowercased().hasPrefix("email_not_unlocked@")
            else { return nil }
            return email
        }

        var finding: EnrichmentFinding {
            EnrichmentFinding(firstName: firstName, lastName: lastName,
                              fullName: fullName, email: usableEmail,
                              title: title, company: organization?.name,
                              website: organization?.websiteURL)
        }
    }
}
