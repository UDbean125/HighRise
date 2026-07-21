import SwiftUI

/// A grid of ready-made starter templates the user can load with one click,
/// grouped by category and filterable — the catalog is large enough now that a
/// single flat grid would be a wall of cards.
struct StarterTemplateGallery: View {
    let onSelect: (StarterTemplate) -> Void

    @State private var selectedCategory: String?
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 12)]

    /// Category groups after applying the category filter and search text.
    private var groups: [(category: String, templates: [StarterTemplate])] {
        StarterTemplateCatalog.byCategory
            .filter { selectedCategory == nil || $0.category == selectedCategory }
            .map { group in (group.category, group.templates.filter(matches)) }
            .filter { !$0.templates.isEmpty }
    }

    private func matches(_ template: StarterTemplate) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [template.name, template.blurb, template.category, template.subject]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            filterBar
            if groups.isEmpty {
                Text("No templates match “\(searchText)”.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(groups, id: \.category) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.category)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(group.templates) { template in
                            StarterTemplateCard(template: template) { onSelect(template) }
                        }
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Picker("Category", selection: $selectedCategory) {
                Text("All \(StarterTemplateCatalog.all.count)").tag(String?.none)
                ForEach(StarterTemplateCatalog.byCategory, id: \.category) { group in
                    Text("\(group.category) (\(group.templates.count))").tag(String?.some(group.category))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search templates", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            .frame(maxWidth: 260)
            Spacer()
        }
    }
}

/// One tappable card in the starter-template gallery.
struct StarterTemplateCard: View {
    let template: StarterTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: template.systemImage)
                        .font(.title3)
                        .foregroundStyle(Brand.accent)
                        .frame(width: 36, height: 36)
                        .background(Brand.accent.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Spacer()
                    Text(template.category)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text(template.name).font(.headline)
                Text(template.blurb)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Use the “\(template.name)” template")
    }
}
