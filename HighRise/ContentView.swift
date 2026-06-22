import SwiftUI

/// The window shell: a step indicator down the side and the active stage's
/// content on the right, with a persistent footer for moving between stages.
struct ContentView: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator

    var body: some View {
        NavigationSplitView {
            StageSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            VStack(spacing: 0) {
                stageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                StageFooter()
            }
        }
        .navigationTitle("HighRise")
    }

    @ViewBuilder
    private var stageContent: some View {
        switch coordinator.stage {
        case .compose:  TemplateEditorView()
        case .contacts: ContactsImportView()
        case .review:   ReviewView()
        case .send:     SendView()
        }
    }
}

/// The left-hand step list. Steps light up as their prerequisites are met and
/// can be tapped to jump back to a completed stage.
private struct StageSidebar: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator

    var body: some View {
        List {
            Section("Steps") {
                ForEach(HighRiseCoordinator.Stage.allCases, id: \.self) { stage in
                    Button {
                        coordinator.stage = stage
                    } label: {
                        Label {
                            Text(title(for: stage))
                                .foregroundStyle(isEnabled(stage) ? .primary : .secondary)
                        } icon: {
                            Image(systemName: symbol(for: stage))
                                .foregroundStyle(stage == coordinator.stage ? Color.accentColor : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled(stage))
                    .accessibilityAddTraits(stage == coordinator.stage ? [.isSelected] : [])
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func title(for stage: HighRiseCoordinator.Stage) -> String {
        switch stage {
        case .compose:  return "1 · Compose"
        case .contacts: return "2 · Contacts"
        case .review:   return "3 · Review"
        case .send:     return "4 · Send"
        }
    }

    private func symbol(for stage: HighRiseCoordinator.Stage) -> String {
        switch stage {
        case .compose:  return "square.and.pencil"
        case .contacts: return "person.2"
        case .review:   return "checklist"
        case .send:     return "paperplane"
        }
    }

    private func isEnabled(_ stage: HighRiseCoordinator.Stage) -> Bool {
        switch stage {
        case .compose:  return true
        case .contacts: return coordinator.canProceedToContacts
        case .review:   return coordinator.canProceedToContacts && coordinator.canProceedToReview
        case .send:     return coordinator.canProceedToReview && !coordinator.sendablePreviews.isEmpty
        }
    }
}

/// Persistent Back / Continue controls at the bottom of the window.
private struct StageFooter: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator

    var body: some View {
        HStack {
            if coordinator.stage != .compose {
                Button("Back") { goBack() }
                    .keyboardShortcut("[", modifiers: .command)
            }
            Spacer()
            footerHint
            Spacer()
            if let (label, action, enabled) = forwardAction {
                Button(label, action: action)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!enabled)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var footerHint: some View {
        switch coordinator.stage {
        case .compose where !coordinator.canProceedToContacts:
            Text("Add a subject and body to continue").foregroundStyle(.secondary).font(.callout)
        case .contacts where !coordinator.canProceedToReview:
            Text("Import a contact list to continue").foregroundStyle(.secondary).font(.callout)
        default:
            EmptyView()
        }
    }

    private var forwardAction: (String, () -> Void, Bool)? {
        switch coordinator.stage {
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
