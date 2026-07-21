import SwiftUI

/// The iOS starter-template picker: the same `StarterTemplateCatalog` the Mac
/// gallery shows, presented as a searchable, category-grouped list.
///
/// This is arguably *more* valuable on iPhone than on the Mac — nobody wants to
/// type a full outreach email on a phone keyboard, so "pick one and edit" is
/// the natural mobile flow.
struct StarterTemplateSheet: View {
    let onSelect: (StarterTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var groups: [(category: String, templates: [StarterTemplate])] {
        StarterTemplateCatalog.byCategory
            .map { ($0.category, $0.templates.filter(matches)) }
            .filter { !$0.templates.isEmpty }
    }

    private func matches(_ template: StarterTemplate) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [template.name, template.blurb, template.category, template.subject]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.templates) { template in
                            Button {
                                onSelect(template)
                                dismiss()
                            } label: {
                                row(for: template)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if groups.isEmpty {
                    Text("No templates match “\(searchText)”.")
                        .foregroundStyle(.secondary)
                }
            }
            .searchable(text: $searchText, prompt: "Search templates")
            .navigationTitle("\(StarterTemplateCatalog.all.count) Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(for template: StarterTemplate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: template.systemImage)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).font(.body.weight(.medium))
                Text(template.blurb)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
