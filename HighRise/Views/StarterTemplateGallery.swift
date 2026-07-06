import SwiftUI

/// A grid of ready-made starter templates the user can load with one click.
struct StarterTemplateGallery: View {
    let onSelect: (StarterTemplate) -> Void

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(StarterTemplateCatalog.all) { template in
                StarterTemplateCard(template: template) { onSelect(template) }
            }
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
