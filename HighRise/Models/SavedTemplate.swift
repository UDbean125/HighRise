import Foundation

/// A named, reusable template in the user's local library.
struct SavedTemplate: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var template: EmailTemplate
    var savedAt: Date

    init(id: UUID = UUID(), name: String, template: EmailTemplate, savedAt: Date) {
        self.id = id
        self.name = name
        self.template = template
        self.savedAt = savedAt
    }
}
