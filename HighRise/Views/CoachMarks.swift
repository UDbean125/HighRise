import SwiftUI

// MARK: - Tour model

/// One stop on the interactive walkthrough. `id` matches a `.coachAnchor(id)`
/// placed on the real control, so the overlay can spotlight the actual UI
/// rather than a mock-up of it.
struct TourStep: Identifiable {
    let id: String
    let title: String
    let message: String
    var systemImage: String = "sparkles"
}

/// The scripted HighRise tour. Every step points at a live element on the
/// Compose screen (or the always-visible sidebar / footer), so the user learns
/// the real dashboard by having it pointed out to them.
enum HighRiseTour {
    static let steps: [TourStep] = [
        TourStep(id: "sidebar.rail",
                 title: "Four simple steps",
                 message: "Everything happens in order down the left: Compose your email, import Contacts, Review each message, then Send. The rail always shows where you are.",
                 systemImage: "list.number"),
        TourStep(id: "compose.gallery",
                 title: "Start from a template",
                 message: "New here? Pick a ready-made template to see how personalization works — then make it your own. Or just start typing.",
                 systemImage: "wand.and.stars"),
        TourStep(id: "compose.subject",
                 title: "Personalize anything",
                 message: "Wrap any field from your list in double braces — {{First Name}}, {{Company}} — and HighRise fills it in for every recipient.",
                 systemImage: "curlybraces"),
        TourStep(id: "compose.templates",
                 title: "Save your work",
                 message: "Found a template you like? Save it here and reload it anytime.",
                 systemImage: "tray.full"),
        TourStep(id: "footer.continue",
                 title: "You're ready!",
                 message: "Once your email has a subject and body, continue to Contacts here. That's the whole flow — go make something great.",
                 systemImage: "arrow.right.circle.fill")
    ]
}

// MARK: - Anchor plumbing

/// Collects the on-screen frame of every element tagged with `.coachAnchor(id)`
/// so the overlay can find the real control to highlight.
struct CoachAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Tags this view so the coach-mark overlay can spotlight it by `id`.
    func coachAnchor(_ id: String) -> some View {
        anchorPreference(key: CoachAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// Punches a hole in this view in the shape of `mask` (used to keep the
    /// spotlighted control bright while the rest of the screen dims).
    func reverseMask<Mask: View>(alignment: Alignment = .center,
                                 @ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: alignment) {
                    mask().blendMode(.destinationOut)
                }
                .compositingGroup()
        }
    }
}

// MARK: - Overlay

/// The full-screen coach-mark layer: dims the window, cuts a bright hole around
/// the current step's target, and floats a glass callout beside it with
/// Back / Next / Skip. Attach at the window root via `.overlayPreferenceValue`.
struct CoachMarkOverlay: View {
    let anchors: [String: Anchor<CGRect>]
    @EnvironmentObject private var coordinator: HighRiseCoordinator

    var body: some View {
        GeometryReader { proxy in
            if let step = coordinator.currentTourStep {
                let rect: CGRect? = anchors[step.id].map { proxy[$0] }
                ZStack {
                    dimming(around: rect)
                    if let rect {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Brand.accent, lineWidth: 2)
                            .frame(width: rect.width + 16, height: rect.height + 16)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                    }
                    callout(step)
                        .frame(maxWidth: 340)
                        .position(calloutPosition(for: rect, in: proxy.size))
                }
                .animation(.easeInOut(duration: 0.28), value: coordinator.tourIndex)
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        // When the tour is off, the overlay must never intercept clicks meant
        // for the app beneath it.
        .allowsHitTesting(coordinator.isTouring)
    }

    private func dimming(around rect: CGRect?) -> some View {
        Color.black.opacity(0.55)
            .reverseMask {
                if let rect {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .frame(width: rect.width + 16, height: rect.height + 16)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .ignoresSafeArea()
    }

    private func callout(_ step: TourStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: step.systemImage)
                    .font(.headline)
                    .foregroundStyle(Brand.accent)
                Text(step.title).font(.headline)
                Spacer()
                Text("\(coordinator.tourIndex + 1) of \(HighRiseTour.steps.count)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(step.message)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Skip") { coordinator.endTour() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                if coordinator.tourIndex > 0 {
                    Button("Back") { coordinator.retreatTour() }
                        .buttonStyle(.plain)
                }
                Button(coordinator.isLastTourStep ? "Finish" : "Next") {
                    coordinator.advanceTour()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(maxWidth: 340, alignment: .leading)
        .glassSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Brand.accent.opacity(0.25))
        )
        .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
    }

    /// Places the callout just below the target when it sits in the top half of
    /// the window, otherwise above it — always clamped inside the edges.
    private func calloutPosition(for rect: CGRect?, in size: CGSize) -> CGPoint {
        guard let rect else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let margin: CGFloat = 120
        let y = rect.midY < size.height / 2
            ? min(rect.maxY + margin, size.height - margin)
            : max(rect.minY - margin, margin)
        let x = min(max(rect.midX, 190), size.width - 190)
        return CGPoint(x: x, y: y)
    }
}
