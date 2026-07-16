import SwiftUI

/// The iOS counterpart to the macOS app's Home dashboard (`HighRise/Views/HomeView.swift`):
/// a glanceable landing screen with one clear "next step" and quick jumps to
/// every stage, instead of forcing a strict Import → Template → Review → Send
/// order. Reuses the same `Greeting`/`NextStep` logic as the Mac app (both
/// Foundation-only, shared via `project.yml`).
///
/// Deliberately smaller than the Mac dashboard: no sending-from account
/// picker (iOS always sends through `MFMailComposeViewController`, which uses
/// whatever Mail account is already on the device), no scheduled-send status,
/// no saved-template/recent-activity history, and no do-not-contact stat —
/// none of those exist in the iOS app.
struct HomeView: View {
    @EnvironmentObject private var coordinator: MobileCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                greeting
                nextStepCard
                Text("Jump in").font(.title3.bold())
                quickStartGrid
                statusStrip
                credit
            }
            .padding(20)
        }
        .navigationTitle("HighRise")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Greeting

    private var hourGreeting: String {
        Greeting.forHour(Calendar.current.component(.hour, from: Date()))
    }

    private var greeting: some View {
        HStack(spacing: 16) {
            Image(systemName: "building.2.crop.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Brand.gradient)
            VStack(alignment: .leading, spacing: 2) {
                Text(hourGreeting)
                    .font(.title.bold())
                    .foregroundStyle(Brand.gradient)
                Text("Welcome to HighRise — personalize one email for your whole list, sent right from your iPhone or iPad.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // MARK: - Next step (primary wayfinding)

    private var nextStep: NextStep.Suggestion {
        NextStep.suggest(hasTemplate: coordinator.hasTemplateContent,
                          contactCount: coordinator.contacts.count,
                          readyCount: coordinator.sendableCount,
                          hasSent: coordinator.hasCompletedASend)
    }

    private var nextStepLabel: some View {
        HStack(spacing: 14) {
            Image(systemName: icon(for: nextStep.action))
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Next step")
                    .font(.caption.weight(.semibold)).textCase(.uppercase)
                    .foregroundStyle(Brand.accent)
                Text(nextStep.title).font(.title3.bold())
                Text(nextStep.detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if nextStep.action != .done {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title).foregroundStyle(Brand.accent)
            }
        }
        .card(padding: 18)
        .overlay(
            RoundedRectangle(cornerRadius: Brand.cornerRadius, style: .continuous)
                .strokeBorder(Brand.accent.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var nextStepCard: some View {
        switch nextStep.action {
        case .compose:
            NavigationLink(destination: TemplateEditorView()) { nextStepLabel }
        case .contacts:
            NavigationLink(destination: ImportView()) { nextStepLabel }
        case .review, .send:
            NavigationLink(destination: ReviewQueueView()) { nextStepLabel }
        case .done:
            nextStepLabel
        }
    }

    private func icon(for action: NextStep.Action) -> String {
        switch action {
        case .compose:  return "square.and.pencil"
        case .contacts: return "person.2.fill"
        case .review:   return "checklist"
        case .send:     return "paperplane.fill"
        case .done:     return "checkmark.seal.fill"
        }
    }

    // MARK: - Quick start

    private var quickStartGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 320), spacing: 14)],
                  spacing: 14) {
            NavigationLink(destination: TemplateEditorView()) {
                ActionCard(title: "Write your email", subtitle: "Compose a template with merge fields.",
                           systemImage: "square.and.pencil", tint: Brand.accent)
            }
            NavigationLink(destination: ImportView()) {
                ActionCard(title: "Import contacts", subtitle: "Add a CSV of recipients.",
                           systemImage: "person.2.fill", tint: .teal)
            }
            NavigationLink(destination: ReviewQueueView()) {
                ActionCard(title: "Review messages", subtitle: reviewSubtitle,
                           systemImage: "checklist", tint: .orange,
                           enabled: coordinator.canProceedToReview)
            }
            .disabled(!coordinator.canProceedToReview)
            NavigationLink(destination: SendSessionView()) {
                ActionCard(title: "Send", subtitle: sendSubtitle,
                           systemImage: "paperplane.fill", tint: .green,
                           enabled: coordinator.sendableCount > 0)
            }
            .disabled(coordinator.sendableCount == 0)
        }
        .buttonStyle(.plain)
    }

    private var reviewSubtitle: String {
        coordinator.canProceedToReview
            ? "\(coordinator.sendableCount) ready to preview."
            : "Add a template and contacts first."
    }

    private var sendSubtitle: String {
        coordinator.sendableCount == 0
            ? "Get recipients ready first."
            : "\(coordinator.sendableCount) ready to go out."
    }

    // MARK: - Status

    private var statusStrip: some View {
        HStack(spacing: 10) {
            StatTile(value: coordinator.hasTemplateContent ? "Ready" : "—",
                     label: "Template", systemImage: "doc.text",
                     tint: coordinator.hasTemplateContent ? .green : Brand.accent)
            StatTile(value: "\(coordinator.contacts.count)",
                     label: "Contacts", systemImage: "person.2.fill")
            StatTile(value: "\(coordinator.sendableCount)",
                     label: "Ready to send", systemImage: "checkmark.circle.fill",
                     tint: coordinator.sendableCount == 0 ? Brand.accent : .green)
        }
    }

    // MARK: - Credit

    private var credit: some View {
        HStack {
            Spacer()
            Label("A HenSolutions LLC app", systemImage: "building.2.crop.circle")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 6)
    }
}
