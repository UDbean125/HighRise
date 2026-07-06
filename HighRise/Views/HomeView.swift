import SwiftUI
import AppKit

/// Stage 0: the glanceable home. Opening the app lands here — confirm which
/// account you're sending from, then jump straight to the step you want in one
/// click. No hunting through tabs for the tool or setting you need.
struct HomeView: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                greeting
                sendingFromCard
                Text("Jump in").font(.title3.bold())
                quickStartGrid
                recentActivity
                statusStrip
                credit
            }
            .padding(28)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Recent activity

    /// A glance back at your work: the last send's result and your most
    /// recently saved templates, each one click from picking up where you were.
    @ViewBuilder
    private var recentActivity: some View {
        let recentTemplates = coordinator.savedTemplates
            .sorted { $0.savedAt > $1.savedAt }
            .prefix(4)
        if !recentTemplates.isEmpty || !coordinator.outcomes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent activity").font(.title3.bold())
                if !coordinator.outcomes.isEmpty {
                    lastRunCard
                }
                if !recentTemplates.isEmpty {
                    Text("Saved templates").font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: 12)],
                              spacing: 12) {
                        ForEach(Array(recentTemplates)) { saved in
                            recentTemplateCard(saved)
                        }
                    }
                }
            }
        }
    }

    private var lastRunCard: some View {
        let ok = coordinator.outcomes.filter(\.isSuccess).count
        return Button {
            coordinator.stage = .send
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3).foregroundStyle(Brand.accent).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Last run").font(.subheadline.weight(.medium))
                    Text("\(ok) of \(coordinator.outcomes.count) delivered — view results")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .card(padding: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func recentTemplateCard(_ saved: SavedTemplate) -> some View {
        Button {
            coordinator.loadTemplate(saved)
            coordinator.stage = .compose
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(saved.name, systemImage: "doc.text")
                    .font(.subheadline.weight(.medium)).lineLimit(1)
                Text(saved.savedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Load “\(saved.name)” and open Compose")
    }

    // MARK: - Credit

    /// A "made by HenSolutions LLC" mark. Shows the company logo once its image
    /// is added to the asset catalog (`HenSolutionsLogo`); until then a tidy
    /// text credit stands in, so the build is never blocked on the artwork.
    private var credit: some View {
        HStack {
            Spacer()
            if let logo = NSImage(named: "HenSolutionsLogo"), logo.size.width > 0 {
                Image(nsImage: logo)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 38)
                    .accessibilityLabel("HenSolutions LLC")
            } else {
                Label("A HenSolutions LLC app", systemImage: "building.2.crop.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    // MARK: - Greeting

    private var greeting: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to HighRise")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Brand.gradient)
                Text("Personalize one email for your whole list — sent right from your Mac.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Sending-from (account confirmation, front and center)

    /// The first thing to confirm on open: which mail app and account this run
    /// goes out through. Prominent by design — sending from the wrong account is
    /// the costliest easy mistake.
    private var sendingFromCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "at.circle.fill")
                    .font(.title2).foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("You're sending from").font(.headline)
                    Text(accountSummary).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    .opacity(coordinator.selectedClient == .outlook || !coordinator.senderIdentity.isEmpty ? 1 : 0.25)
            }

            Picker("Email app", selection: $coordinator.selectedClient) {
                ForEach(MailClient.allCases) { client in
                    Label(client.rawValue, systemImage: client.symbolName).tag(client)
                }
            }
            .pickerStyle(.segmented).labelsHidden()

            HStack(alignment: .top, spacing: 16) {
                if coordinator.selectedClient == .appleMail {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("From account").font(.subheadline)
                        TextField("Jordan <jordan@work.com>", text: $coordinator.senderIdentity)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                        Text("Blank = your default Mail account.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Label("Outlook sends from its own default account.",
                          systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider").font(.subheadline)
                    Picker("Provider", selection: $coordinator.sendingProvider) {
                        ForEach(SendingProvider.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().frame(maxWidth: 220)
                    Text("Used for daily-limit warnings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .card(padding: 20)
        .overlay(
            RoundedRectangle(cornerRadius: Brand.cornerRadius, style: .continuous)
                .strokeBorder(Brand.accent.opacity(0.35), lineWidth: 1)
        )
    }

    private var accountSummary: String {
        switch coordinator.selectedClient {
        case .appleMail:
            return coordinator.senderIdentity.isEmpty
                ? "Apple Mail · your default account"
                : "Apple Mail · \(coordinator.senderIdentity)"
        case .outlook:
            return "Microsoft Outlook · its default account"
        }
    }

    // MARK: - Quick start

    private var quickStartGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 14)],
                  spacing: 14) {
            ActionCard(title: "Write your email", subtitle: "Compose a template with merge fields.",
                       systemImage: "square.and.pencil", tint: Brand.accent) {
                coordinator.stage = .compose
            }
            ActionCard(title: "Start from a template", subtitle: "Pick a ready-made starting point.",
                       systemImage: "wand.and.stars", tint: .purple) {
                coordinator.beginWithStarterTemplate()
                coordinator.stage = .compose
            }
            ActionCard(title: "Import contacts", subtitle: "CSV, Excel, or your address book.",
                       systemImage: "person.2.fill", tint: .teal) {
                coordinator.stage = .contacts
            }
            ActionCard(title: "Review messages", subtitle: reviewSubtitle,
                       systemImage: "checklist", tint: .orange,
                       enabled: coordinator.canProceedToReview) {
                coordinator.stage = .review
            }
            ActionCard(title: "Send or draft", subtitle: sendSubtitle,
                       systemImage: "paperplane.fill", tint: .green,
                       enabled: !coordinator.sendablePreviews.isEmpty) {
                coordinator.stage = .send
            }
            ActionCard(title: "Take the tour", subtitle: "A guided walkthrough of the app.",
                       systemImage: "sparkles", tint: .pink) {
                coordinator.startTour()
            }
        }
    }

    private var reviewSubtitle: String {
        coordinator.canProceedToReview
            ? "\(coordinator.sendablePreviews.count) ready to preview."
            : "Add a template and contacts first."
    }

    private var sendSubtitle: String {
        coordinator.sendablePreviews.isEmpty
            ? "Get recipients ready first."
            : "\(coordinator.sendablePreviews.count) ready to go out."
    }

    // MARK: - Status

    private var statusStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let fireDate = coordinator.scheduledFireDate {
                HStack(spacing: 10) {
                    Image(systemName: "clock.badge.checkmark").font(.title3).foregroundStyle(Brand.accent)
                    Text("Scheduled send for \(fireDate.formatted(date: .abbreviated, time: .shortened)) — keep this Mac awake and HighRise open.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .card()
            }
            HStack(spacing: 10) {
                StatTile(value: coordinator.canProceedToContacts ? "Ready" : "—",
                         label: "Template", systemImage: "doc.text",
                         tint: coordinator.canProceedToContacts ? .green : Brand.accent)
                StatTile(value: "\(coordinator.contacts.count)",
                         label: "Contacts", systemImage: "person.2.fill")
                StatTile(value: "\(coordinator.sendablePreviews.count)",
                         label: "Ready to send", systemImage: "checkmark.circle.fill",
                         tint: coordinator.sendablePreviews.isEmpty ? Brand.accent : .green)
                StatTile(value: "\(coordinator.suppressionEntries.count)",
                         label: "Do-not-contact", systemImage: "nosign", tint: .secondary)
            }
        }
    }
}

/// A large, single-click tile for the Home quick-start grid.
private struct ActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = Brand.accent
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
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
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(enabled ? title : "\(title) — \(subtitle)")
    }
}
