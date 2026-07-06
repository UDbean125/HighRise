import SwiftUI
import AppKit

/// The window shell: a branded progress rail down the side and the active
/// stage's content on the right, with a persistent footer for moving between
/// stages.
struct ContentView: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator
    @AppStorage("hasSeenWelcomeTour") private var hasSeenWelcomeTour = false

    var body: some View {
        NavigationSplitView {
            StageSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            VStack(spacing: 0) {
                stageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Home is a hub, not a step in the linear flow — no Back/Continue.
                if coordinator.stage != .home {
                    Divider()
                    StageFooter()
                }
            }
        }
        .navigationTitle("HighRise")
        .tint(Brand.accent)
        // The interactive walkthrough spotlights real controls; it reads their
        // frames from the whole window via anchor preferences.
        .overlayPreferenceValue(CoachAnchorKey.self) { anchors in
            CoachMarkOverlay(anchors: anchors)
        }
        .onAppear {
            if !hasSeenWelcomeTour { coordinator.isShowingWelcome = true }
        }
        .sheet(isPresented: $coordinator.isShowingWelcome) {
            WelcomeView(onStartWithTemplate: { coordinator.beginWithStarterTemplate() },
                        onTakeTour: { coordinator.startTour() })
                .onDisappear { hasSeenWelcomeTour = true }
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch coordinator.stage {
        case .home:     HomeView()
        case .compose:  TemplateEditorView()
        case .contacts: ContactsImportView()
        case .review:   ReviewView()
        case .send:     SendView()
        }
    }
}

// MARK: - Sidebar

/// The left-hand progress rail: a brand header plus the four steps, each showing
/// a done/current/upcoming badge and a short status. Completed steps can be
/// tapped to jump back.
private struct StageSidebar: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
            Divider().padding(.horizontal, 12)
            VStack(spacing: 2) {
                homeRow
                Divider().padding(.vertical, 6).padding(.horizontal, 8)
                ForEach(HighRiseCoordinator.Stage.workflow, id: \.self) { stage in
                    stepRow(stage)
                }
            }
            .padding(12)
            .coachAnchor("sidebar.rail")
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1.5)
            VStack(alignment: .leading, spacing: 0) {
                Text("HighRise")
                    .font(.title2.bold())
                    .foregroundStyle(Brand.gradient)
                Text("Mail merge, made personal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                coordinator.isShowingWelcome = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Show the welcome tour")
        }
        .padding(16)
    }

    /// The Home hub row — a house icon rather than a numbered badge, since it
    /// isn't a step in the linear flow.
    private var homeRow: some View {
        let isCurrent = coordinator.stage == .home
        return Button {
            coordinator.stage = .home
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "house.fill")
                    .foregroundStyle(isCurrent ? Brand.accent : .secondary)
                    .frame(width: 24)
                Text("Home")
                    .font(.callout.weight(isCurrent ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isCurrent ? Brand.accent.opacity(0.14) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    private func stepRow(_ stage: HighRiseCoordinator.Stage) -> some View {
        let isCurrent = stage == coordinator.stage
        return Button {
            if isEnabled(stage) { coordinator.stage = stage }
        } label: {
            HStack(spacing: 10) {
                StepBadge(number: stage.rawValue, state: badgeState(stage))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(for: stage))
                        .font(.callout.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isEnabled(stage) ? .primary : .secondary)
                    Text(status(for: stage))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isCurrent ? Brand.accent.opacity(0.14) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled(stage))
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    // MARK: Step metadata

    private func badgeState(_ stage: HighRiseCoordinator.Stage) -> StepBadge.State {
        if stage == coordinator.stage { return .current }
        return stage.rawValue < coordinator.stage.rawValue ? .done : .upcoming
    }

    private func title(for stage: HighRiseCoordinator.Stage) -> String {
        switch stage {
        case .home:     return "Home"
        case .compose:  return "Compose"
        case .contacts: return "Contacts"
        case .review:   return "Review"
        case .send:     return "Send"
        }
    }

    private func status(for stage: HighRiseCoordinator.Stage) -> String {
        switch stage {
        case .home:
            return "Dashboard"
        case .compose:
            return coordinator.canProceedToContacts ? "Template ready" : "Write your email"
        case .contacts:
            return coordinator.contacts.isEmpty ? "Import a list"
                : "\(coordinator.contacts.count) loaded"
        case .review:
            let ready = coordinator.sendablePreviews.count
            return ready > 0 ? "\(ready) ready to send" : "Nothing ready yet"
        case .send:
            if !coordinator.outcomes.isEmpty {
                let ok = coordinator.outcomes.filter(\.isSuccess).count
                return "\(ok)/\(coordinator.outcomes.count) sent"
            }
            return "Draft or send"
        }
    }

    private func isEnabled(_ stage: HighRiseCoordinator.Stage) -> Bool {
        switch stage {
        case .home:     return true
        case .compose:  return true
        case .contacts: return coordinator.canProceedToContacts
        case .review:   return coordinator.canProceedToContacts && coordinator.canProceedToReview
        case .send:     return coordinator.canProceedToReview && !coordinator.sendablePreviews.isEmpty
        }
    }
}

// MARK: - Footer

/// Persistent Back / Continue controls at the bottom of the window.
private struct StageFooter: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator

    var body: some View {
        HStack {
            if coordinator.stage != .home {
                Button {
                    goBack()
                } label: {
                    Label(coordinator.stage == .compose ? "Home" : "Back",
                          systemImage: "chevron.left")
                }
                .keyboardShortcut("[", modifiers: .command)
            }
            Spacer()
            footerHint
            Spacer()
            if let (label, action, enabled) = forwardAction {
                Button(action: action) {
                    Label(label, systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!enabled)
                .coachAnchor("footer.continue")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var footerHint: some View {
        switch coordinator.stage {
        case .compose where !coordinator.canProceedToContacts:
            Label("Add a subject and body to continue", systemImage: "info.circle")
                .foregroundStyle(.secondary).font(.callout)
        case .contacts where !coordinator.canProceedToReview:
            Label("Import a contact list to continue", systemImage: "info.circle")
                .foregroundStyle(.secondary).font(.callout)
        default:
            EmptyView()
        }
    }

    private var forwardAction: (String, () -> Void, Bool)? {
        switch coordinator.stage {
        case .home:
            return nil
        case .compose:
            return ("Continue to Contacts", { coordinator.stage = .contacts }, coordinator.canProceedToContacts)
        case .contacts:
            return ("Review Messages", { coordinator.stage = .review }, coordinator.canProceedToReview)
        case .review:
            return ("Continue to Send", { coordinator.stage = .send }, !coordinator.sendablePreviews.isEmpty)
        case .send:
            return nil
        }
    }

    private func goBack() {
        if let prev = HighRiseCoordinator.Stage(rawValue: coordinator.stage.rawValue - 1) {
            coordinator.stage = prev
        }
    }
}
