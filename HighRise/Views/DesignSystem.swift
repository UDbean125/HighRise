import SwiftUI
import AppKit

/// Shared visual language for HighRise: one brand accent plus a small set of
/// reusable containers (cards, section headers, stat tiles, step badges) so
/// every screen reads as one system. Refined-native first — standard materials
/// and system colors — with a single confident accent on top.
enum Brand {
    /// The HighRise accent — the azure sampled straight from the app icon, a
    /// touch lighter in dark mode so it stays legible on dark surfaces. Adaptive
    /// via an AppKit dynamic provider.
    static let accent = Color(nsColor: NSColor(name: "HighRiseAccent") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.44, green: 0.75, blue: 0.96, alpha: 1)   // #6FC0F4
            : NSColor(srgbRed: 0.18, green: 0.56, blue: 0.85, alpha: 1)   // #2E8FD6
    })

    /// The deep end of the logo's blue gradient — for gradient fills and depth.
    static let accentDeep = Color(srgbRed: 0.12, green: 0.44, blue: 0.72, alpha: 1) // #1E6FB8
    /// The light sky-blue highlight from the logo.
    static let accentSoft = Color(srgbRed: 0.47, green: 0.75, blue: 0.94, alpha: 1) // #78C0F0

    /// The signature HighRise gradient (light → azure → deep), used on hero
    /// surfaces, the onboarding, and the app's brand marks.
    static var gradient: LinearGradient {
        LinearGradient(colors: [accentSoft, accent, accentDeep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Corner radius used across cards and tiles.
    static let cornerRadius: CGFloat = 12
}

// MARK: - Liquid Glass surface

extension View {
    /// A translucent "glass" background: Apple's **Liquid Glass** on macOS 26+
    /// (Tahoe), and a vibrant material everywhere else so the same call site
    /// looks glassy on every supported OS. The app's standard way to lean into
    /// the glass aesthetic wherever it reads well.
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}

// MARK: - Card container

private struct CardModifier: ViewModifier {
    var padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(in: RoundedRectangle(cornerRadius: Brand.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Brand.cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4))
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

// MARK: - Avatar

/// A colored circle with a recipient's initials — a scannable stand-in for a
/// photo. The color is derived deterministically from the name so the same
/// person always gets the same hue.
struct Avatar: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }

    private var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" })
        let letters = words.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private var color: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red, .cyan, .mint]
        var hash = 5381
        for scalar in name.unicodeScalars { hash = (hash &* 33) &+ Int(scalar.value) }
        return palette[abs(hash) % palette.count]
    }
}

// MARK: - Status pill

/// A small colored capsule label — "Ready", "Held back", etc.
struct StatusPill: View {
    let text: String
    let color: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).font(.caption2) }
            Text(text).font(.caption2.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Collapsible card

/// A card whose contents can be folded away — used to keep secondary options
/// (attachments, CC/BCC, pacing, tools) tidy until the user wants them. An
/// optional badge on the header hints at hidden content (e.g. "2 files").
struct CollapsibleCard<Content: View>: View {
    let title: String
    var systemImage: String
    var badge: String?
    @State private var expanded: Bool
    @ViewBuilder var content: () -> Content

    init(_ title: String, systemImage: String, badge: String? = nil,
         expanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.badge = badge
        self._expanded = SwiftUI.State(initialValue: expanded)
        self.content = content
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            content().padding(.top, 12)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(Brand.accent).frame(width: 20)
                Text(title).font(.headline)
                if let badge {
                    Text(badge)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Brand.accent.opacity(0.15), in: Capsule())
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .card()
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
