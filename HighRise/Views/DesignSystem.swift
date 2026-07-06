import SwiftUI
import AppKit

/// Shared visual language for HighRise: one brand accent plus a small set of
/// reusable containers (cards, section headers, stat tiles, step badges) so
/// every screen reads as one system. Refined-native first — standard materials
/// and system colors — with a single confident accent on top.
enum Brand {
    /// The HighRise accent: a confident blue, a touch lighter in dark mode so it
    /// stays legible on dark surfaces. Adaptive via an AppKit dynamic provider.
    static let accent = Color(nsColor: NSColor(name: "HighRiseAccent") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.46, green: 0.63, blue: 1.00, alpha: 1)
            : NSColor(srgbRed: 0.16, green: 0.36, blue: 0.84, alpha: 1)
    })

    /// Corner radius used across cards and tiles.
    static let cornerRadius: CGFloat = 12
}

// MARK: - Card container

private struct CardModifier: ViewModifier {
    var padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: Brand.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Brand.cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
            )
    }
}

extension View {
    /// Wraps content in a subtle raised card — the standard grouping surface.
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

// MARK: - Section card (titled group)

/// A card with an accented icon + title header and arbitrary content beneath —
/// the workhorse for grouping a screen's options.
struct SectionCard<Content: View>: View {
    let title: String
    var systemImage: String?
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String, systemImage: String? = nil, subtitle: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(Brand.accent)
                        .font(.headline)
                        .frame(width: 20)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content()
        }
        .card()
    }
}

// MARK: - Stat tile

/// A compact metric chip (value + label + icon), used for the review/send
/// summaries. Colour-coded by meaning.
struct StatTile: View {
    let value: String
    let label: String
    let systemImage: String
    var tint: Color = Brand.accent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Step badge

/// The numbered/checkmarked circle used in the sidebar progress rail.
struct StepBadge: View {
    enum State { case done, current, upcoming }
    let number: Int
    let state: State

    var body: some View {
        ZStack {
            Circle().fill(fill).frame(width: 24, height: 24)
            switch state {
            case .done:
                Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
            case .current:
                Text("\(number)").font(.caption.bold()).foregroundStyle(.white)
            case .upcoming:
                Text("\(number)").font(.caption.bold()).foregroundStyle(.secondary)
            }
        }
    }

    private var fill: Color {
        switch state {
        case .done:     return Brand.accent
        case .current:  return Brand.accent
        case .upcoming: return Color(nsColor: .quaternaryLabelColor)
        }
    }
}
