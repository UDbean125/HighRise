import SwiftUI

/// The iOS starter-template picker: the same `StarterTemplateCatalog` the Mac
/// gallery shows, presented as a searchable, grouped list.
///
/// This is arguably *more* valuable on iPhone than on the Mac — nobody wants to
/// type a full outreach email on a phone keyboard, so "pick one and edit" is
/// the natural mobile flow.
///
/// Same two-level grouping as the Mac: choosing an industry splits the list
/// into "Made for <industry>" and "Works for any industry", with the task
/// groups (Grow, Connect, …) as the sections inside each.
struct StarterTemplateSheet: View {
    let onSelect: (StarterTemplate) -> Void

    /// Matches the Mac gallery's sort control.
    enum SortOrder: String, CaseIterable, Identifiable {
        case recommended = "Recommended"
        case nameAZ = "Name (A–Z)"
        case nameZA = "Name (Z–A)"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedIndustry: TemplateIndustry?
    @State private var selectedAudience: TemplateAudience?
    @State private var selectedCategory: String?
    @State private var sortOrder: SortOrder = .recommended

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
        case .recommended: return templates
        case .nameAZ:      return templates.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .nameZA:      return templates.sorted { $0.name.localizedCompare($1.name) == .orderedDescending }
        }
    }

    private func matches(_ template: StarterTemplate) -> Bool {
        StarterTemplateCatalog.matches(template, query: searchText)
    }

    private var resultCount: Int { sections.reduce(0) { $0 + $1.count } }

    private var hasActiveFilters: Bool {
        selectedIndustry != nil || selectedAudience != nil || selectedCategory != nil
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func clearAllFilters() {
        selectedIndustry = nil
        selectedAudience = nil
        selectedCategory = nil
        searchText = ""
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Industry", selection: $selectedIndustry) {
                        Text("All industries").tag(TemplateIndustry?.none)
                        ForEach(TemplateIndustry.allCases) { industry in
                            Label("\(industry.rawValue) (\(StarterTemplateCatalog.tailoredCount(for: industry)))",
                                  systemImage: industry.systemImage)
                                .tag(TemplateIndustry?.some(industry))
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Audience", selection: $selectedAudience) {
                        Text("All audiences").tag(TemplateAudience?.none)
                        ForEach(TemplateAudience.allCases) { audience in
                            Text("\(audience.rawValue) (\(StarterTemplateCatalog.count(for: audience)))")
                                .tag(TemplateAudience?.some(audience))
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Task", selection: $selectedCategory) {
                        Text("Any task").tag(String?.none)
                        ForEach(StarterTemplateCatalog.byCategory, id: \.category) { group in
                            Text("\(group.category) (\(group.templates.count))")
                                .tag(String?.some(group.category))
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Find a template")
                } footer: {
                    HStack {
                        Text("\(resultCount) of \(StarterTemplateCatalog.all.count) shown")
                        if hasActiveFilters {
                            Spacer()
                            Button("Clear all", action: clearAllFilters).font(.footnote)
                        }
                    }
                }

                ForEach(sections) { section in
                    ForEach(section.groups, id: \.category) { group in
                        Section {
                            ForEach(group.templates) { template in
                                Button {
                                    onSelect(template)
                                    dismiss()
                                } label: {
                                    row(for: template)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            // With an industry chosen, each task group is
                            // labeled with the band it belongs to so the two
                            // "Grow" sections can't be confused.
                            if selectedIndustry == nil {
                                Text(group.category)
                            } else {
                                Label("\(section.industry == nil ? "Any industry" : "Made for you") · \(group.category)",
                                      systemImage: section.systemImage)
                            }
                        }
                    }
                }

                if sections.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? "No templates match those filters."
                             : "No templates match “\(searchText)”.")
                            .foregroundStyle(.secondary)
                        Button("Clear all filters", action: clearAllFilters)
                    }
                }
            }
            .searchable(text: $searchText,
                        prompt: "Search by name, industry, or audience")
            .navigationTitle("\(StarterTemplateCatalog.all.count) Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
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
