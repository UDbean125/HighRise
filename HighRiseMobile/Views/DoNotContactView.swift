import SwiftUI

/// The iPhone's do-not-contact list — the same on-device list the Mac keeps,
/// so an address suppressed on either device is honored on both.
///
/// Entries hold back matching recipients on every future merge without
/// editing anyone's CSV, and nothing here ever leaves the device.
struct DoNotContactView: View {
    @EnvironmentObject var coordinator: MobileCoordinator

    @State private var newValue = ""
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("name@example.com or acme.com", text: $newValue)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .focused($fieldFocused)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newValue.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Add someone")
            } footer: {
                Text("Enter one address to block that person, or a bare domain like acme.com to block everyone there. They're held back from every merge from now on — their row stays in your list, it just never sends.")
            }

            if coordinator.suppressionEntries.isEmpty {
                Section {
                    Text("Nobody is blocked yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("\(coordinator.suppressionEntries.count) blocked") {
                    ForEach(coordinator.suppressionEntries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.displayLabel)
                            if let note = entry.note, !note.isEmpty {
                                Text(note).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                coordinator.removeSuppression(entry)
                            } label: {
                                Label("Unblock", systemImage: "arrow.uturn.backward")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Do Not Contact")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add() {
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // An entry with an @ is one person; anything else is read as a domain.
        let added = trimmed.contains("@")
            ? coordinator.suppressAddress(trimmed)
            : coordinator.suppressDomain(trimmed)
        if added {
            newValue = ""
            errorMessage = nil
            fieldFocused = true
        } else {
            errorMessage = "That doesn't look like an address or domain, or it's already on the list."
        }
    }
}
