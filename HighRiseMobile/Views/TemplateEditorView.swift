import SwiftUI

/// Step 2: write the subject/body once, using the same `{{Field}}` merge
/// syntax as the Mac app. Live preview counts (via `refreshPreviews`) reuse
/// `TemplateMergeEngine`, so a placeholder that doesn't match a CSV column
/// shows up as a held-back recipient before the user ever tries to send.
struct TemplateEditorView: View {
    @EnvironmentObject var coordinator: MobileCoordinator

    var body: some View {
        Form {
            Section("Subject") {
                TextField("Subject", text: $coordinator.template.subject)
            }
            Section("Body") {
                TextEditor(text: $coordinator.template.body)
                    .frame(minHeight: 220)
            }
            Section("Format") {
                Picker("Format", selection: $coordinator.template.format) {
                    ForEach(EmailTemplate.BodyFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
            }
            Section {
                Text("Use {{Field}} for any column from your CSV, e.g. {{First Name}} or {{Company}}.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Template")
        .onChange(of: coordinator.template) { _, _ in coordinator.refreshPreviews() }
        .onAppear { coordinator.refreshPreviews() }
        .safeAreaInset(edge: .bottom) {
            NavigationLink("Next: Review (\(coordinator.sendableCount) ready)") {
                ReviewQueueView()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}
