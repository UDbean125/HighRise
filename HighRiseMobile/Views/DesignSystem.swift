import SwiftUI

/// A small iOS-native counterpart to the macOS app's `DesignSystem.swift`.
/// Not shared with it — that file leans on AppKit (`NSColor`, Liquid Glass
/// availability checks) — but the same idea: one brand accent plus a couple
/// of reusable containers so Home reads as one system.
enum Brand {
    static let accent = Color.blue
    static let accentDeep = Color(red: 0.12, green: 0.44, blue: 0.72)
    static let accentSoft = Color(red: 0.47, green: 0.75, blue: 0.94)

    static var gradient: LinearGradient {
        LinearGradient(colors: [accentSoft, accent, accentDeep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let cornerRadius: CGFloat = 12
}

private struct CardModifier: ViewModifier {
    var padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Brand.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Brand.cornerRadius, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.4))
            )
    }
}

extension View {
    /// Wraps content in a subtle raised card — the standard grouping surface.
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

/// A compact metric chip (value + label + icon), matching the macOS app's
/// `StatTile` used in the Home status strip.
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

/// A large, single-tap tile for the Home quick-start grid — matching the
/// macOS app's `ActionCard`.
struct ActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = Brand.accent
    var enabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(enabled ? tint : Color.secondary)
                .frame(width: 48, height: 48)
                .background(enabled ? tint.opacity(0.14) : Color.secondary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .card()
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(14)
        }
        .contentShape(Rectangle())
        .opacity(enabled ? 1 : 0.55)
    }
}
