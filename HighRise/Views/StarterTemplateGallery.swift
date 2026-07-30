import SwiftUI

/// A grid of ready-made starter templates the user can load with one click.
///
/// Two levels of grouping: choosing an industry splits the gallery into
/// "Made for <industry>" and "Works for any industry" bands, and inside each
/// band the task groups (Grow, Connect, Get paid, …) are the subsections. With
/// no industry chosen it's just the task groups, as before.
struct StarterTemplateGallery: View {
    let onSelect: (StarterTemplate) -> Void

    /// How the cards inside each task group are ordered.
    enum SortOrder: String, CaseIterable, Identifiable {
        case recommended = "Recommended"
        case nameAZ = "Name (A–Z)"
        case nameZA = "Name (Z–A)"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .recommended: return "sparkles"
            case .nameAZ:      return "arrow.up"
            case .nameZA:      return "arrow.down"
            }
        }
    }

    @State private var selectedCategory: String?
    @State private var selectedIndustry: TemplateIndustry?
    @State private var selectedAudience: TemplateAudience?
    @State private var sortOrder: SortOrder = .recommended
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 12)]

    /// Sections after the industry/audience dropdowns, then narrowed by the
    /// category picker and search text. Empty subsections and bands drop out.
    private var sections: [StarterTemplateCatalog.Section] {
        StarterTemplateCatalog.sections(industry: selectedIndustry, audience: selectedAudience)
            .compactMap { section in
                let groups = section.groups
                    .filter { selectedCategory == nil || $0.category == selectedCategory }
                    .map { (category: $0.category, templates: sorted($0.templates.filter(matches))) }
                    .filter { !$0.templates.isEmpty }
                guard !groups.isEmpty else { return nil }
                return StarterTemplateCatalog.Section(industry: section.industry,
                                                      title: section.title,
                                                      systemImage: section.systemImage,
                                                      groups: groups)
            }
    }

    private func sorted(_ templates: [StarterTemplate]) -> [StarterTemplate] {
        switch sortOrder {
        case .recommended: return templates            // catalog's authored order
        case .nameAZ:      return templates.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .nameZA:      return templates.sorted { $0.name.localizedCompare($1.name) == .orderedDescending }
        }
    }

    private func matches(_ template: StarterTemplate) -> Bool {
        StarterTemplateCatalog.matches(template, query: searchText)
    }

    private var resultCount: Int {
        sections.reduce(0) { $0 + $1.count }
    }

    private var hasActiveFilters: Bool {
        selectedCategory != nil || selectedIndustry != nil || selectedAudience != nil
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func clearAllFilters() {
        selectedCategory = nil
        selectedIndustry = nil
        selectedAudience = nil
        searchText = ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            filterBar
            if sections.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "No templates match those filters."
                         : "No templates match “\(searchText)”.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Clear all filters", action: clearAllFilters)
                        .controlSize(.small)
                }
                .padding(.vertical, 8)
            }
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    // The band header is only meaningful once an industry
                    // splits the gallery in two.
                    if selectedIndustry != nil {
                        sectionHeader(section)
                    }
                    ForEach(section.groups, id: \.category) { group in
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
        }
    }

    private func sectionHeader(_ section: StarterTemplateCatalog.Section) -> some View {
        HStack(spacing: 8) {
            Image(systemName: section.systemImage)
                .font(.callout)
                .foregroundStyle(section.industry == nil ? Color.secondary : Brand.accent)
            Text(section.title).font(.headline)
            Text("\(section.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Spacer()
        }
        .padding(.top, 4)
    }

    /// Search first (it's the fastest way to find a known template), then the
    /// dropdowns, then a chip row showing exactly what's currently narrowing
    /// the list — each chip removable, so no filter can be left on by accident.
    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                searchField
                Text("\(resultCount) of \(StarterTemplateCatalog.all.count)")
                    .font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { order in
                        Label(order.rawValue, systemImage: order.systemImage).tag(order)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 170)
                .help("Order the cards inside each group")
            }

            HStack(spacing: 8) {
                Picker("Industry", selection: $selectedIndustry) {
                    Text("All industries").tag(TemplateIndustry?.none)
                    ForEach(TemplateIndustry.allCases) { industry in
                        Text("\(industry.rawValue) (\(StarterTemplateCatalog.tailoredCount(for: industry)))")
                            .tag(TemplateIndustry?.some(industry))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 250)
                .help("Put the templates written for your industry first — the general ones stay below")

                Picker("Audience", selection: $selectedAudience) {
                    Text("All audiences").tag(TemplateAudience?.none)
                    ForEach(TemplateAudience.allCases) { audience in
                        Text("\(audience.rawValue) (\(StarterTemplateCatalog.count(for: audience)))")
                            .tag(TemplateAudience?.some(audience))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 210)
                .help("Show templates written for who you're emailing")

                Picker("Task", selection: $selectedCategory) {
                    Text("Any task").tag(String?.none)
                    ForEach(StarterTemplateCatalog.byCategory, id: \.category) { group in
                        Text("\(group.category) (\(group.templates.count))").tag(String?.some(group.category))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 165)
                .help("Narrow to one task group")
                Spacer()
            }

            if hasActiveFilters {
                HStack(spacing: 6) {
                    if let industry = selectedIndustry {
                        filterChip(industry.rawValue, systemImage: industry.systemImage) {
                            selectedIndustry = nil
                        }
                    }
                    if let audience = selectedAudience {
                        filterChip(audience.rawValue, systemImage: "person.2") { selectedAudience = nil }
                    }
                    if let category = selectedCategory {
                        filterChip(category, systemImage: "square.grid.2x2") { selectedCategory = nil }
                    }
                    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !query.isEmpty {
                        filterChip("“\(query)”", systemImage: "magnifyingglass") { searchText = "" }
                    }
                    Button("Clear all", action: clearAllFilters)
                        .buttonStyle(.link)
                        .font(.caption)
                    Spacer()
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search by name, industry, or who you're emailing", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .frame(maxWidth: 380)
    }

    private func filterChip(_ title: String, systemImage: String,
                            remove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.caption2)
            Text(title).font(.caption)
            Button(action: remove) {
                Image(systemName: "xmark").font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .help("Remove this filter")
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Brand.accent.opacity(0.14), in: Capsule())
        .foregroundStyle(Brand.accent)
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
