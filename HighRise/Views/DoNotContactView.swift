import SwiftUI

/// Manages the on-device do-not-contact list: add an address or a whole domain,
/// review what's suppressed, and remove entries. Everything stays local — this
/// list never leaves the Mac.
struct DoNotContactView: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var newEntry = ""
    @State private var kind: Kind = .address
    @State private var inputError: String?

    private enum Kind: String, CaseIterable, Identifiable {
        case address = "Address"
        case domain = "Whole domain"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            addRow
            Divider()
            list
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Do-Not-Contact List").font(.title2).bold()
            Text("Addresses and domains here are skipped in every merge. Stored only on this Mac.")
                .foregroundStyle(.secondary).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("Type", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
                TextField(kind == .address ? "name@example.com" : "example.com",
                          text: $newEntry)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newEntry.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let inputError {
                Label(inputError, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if coordinator.suppressionEntries.isEmpty {
            ContentUnavailableView("Nothing suppressed yet", systemImage: "nosign",
                                   description: Text("Add an address or domain above to skip it in every merge."))
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            List {
                ForEach(coordinator.suppressionEntries.sorted(by: { $0.dateAdded > $1.dateAdded })) { entry in
                    HStack {
                        Image(systemName: entry.kind == .domain ? "at.badge.minus" : "person.crop.circle.badge.xmark")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.displayLabel)
                            if let note = entry.note, !note.isEmpty {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            coordinator.removeSuppression(entry)
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove from list")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func add() {
        let ok = kind == .address
            ? coordinator.suppressAddress(newEntry)
            : coordinator.suppressDomain(newEntry)
        if ok {
            newEntry = ""
            inputError = nil
        } else {
            inputError = kind == .address
                ? "Enter a valid email address (or it's already on the list)."
                : "Enter a valid domain like example.com (or it's already on the list)."
        }
    }
}
