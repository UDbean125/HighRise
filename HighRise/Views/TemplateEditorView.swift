import SwiftUI

/// Stage 1: write the email draft with `{{Field}}` merge placeholders.
///
/// Fields are open-ended: any column from the imported list is usable, plus a
/// curated catalog of common professional fields. Clicking any field in the
/// palette drops its `{{token}}` into whichever box (subject or body) you were
/// last typing in.
struct TemplateEditorView: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator

    private enum Field: Hashable { case subject, body }
    @FocusState private var focus: Field?

    @State private var showSaveDialog = false
    @State private var newTemplateName = ""
    @State private var showTemplateGallery = false
    /// A starter the user picked while the composer already had content — held
    /// until they confirm the overwrite.
    @State private var pendingStarter: StarterTemplate?
    @State private var showInstructions = false

    var body: some View {
        ScrollView {
            // Wide windows get a two-column workspace — editor on the left, a
            // live companion rail (preview + field palette) filling the right —
            // so no screen real estate sits idle. Narrow windows stack.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    editorColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                    sideRail
                        .frame(width: 360)
                }
                .frame(minWidth: 900)

                VStack(alignment: .leading, spacing: 20) {
                    editorColumn
                    sideRail
                }
            }
            .padding(24)
            .frame(maxWidth: 1320, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .sheet(isPresented: $showTemplateGallery) { starterGallerySheet }
        .onAppear(perform: consumeGalleryRequestIfNeeded)
        .onChange(of: coordinator.pendingStarterGalleryRequest) { _, _ in
            consumeGalleryRequestIfNeeded()
        }
        .confirmationDialog("Replace what you've written?",
                            isPresented: Binding(get: { pendingStarter != nil },
                                                 set: { if !$0 { pendingStarter = nil } }),
                            titleVisibility: .visible) {
            Button("Replace with “\(pendingStarter?.name ?? "")”", role: .destructive) {
                if let starter = pendingStarter { load(starter) }
                pendingStarter = nil
            }
            Button("Keep what I have", role: .cancel) { pendingStarter = nil }
        } message: {
            Text("This will overwrite the subject and body you've already written.")
        }
    }

    // MARK: - Columns

    /// The main writing surface: title row, starter gallery (when empty),
    /// subject, format, body, variants, and the fields summary.
    private var editorColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                header
                Spacer()
                instructionsButton
                templateLibraryMenu
                    .coachAnchor("compose.templates")
            }

            if coordinator.isTemplateEmpty {
                starterHero
                    .coachAnchor("compose.gallery")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Subject").font(.headline)
                TextField("e.g. Quick question about {{Company}}",
                          text: $coordinator.template.subject)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($focus, equals: .subject)
                    .accessibilityLabel("Email subject")
                subjectCounter
            }
            .coachAnchor("compose.subject")

            bodyFormatPicker

            VStack(alignment: .leading, spacing: 6) {
                Text("Body").font(.headline)
                formattingToolbar
                TextEditor(text: $coordinator.template.body)
                    .font(.body)
                    .frame(minHeight: 260)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    .focused($focus, equals: .body)
                    .accessibilityLabel("Email body")
                if coordinator.template.body.isEmpty {
                    Text("Use {{FieldName}} anywhere to drop in a contact's details, e.g.\n\nHi {{First Name}},\n\nI've been following {{Company}} and wanted to reach out about {{Product Name}}…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    let stats = WordCount.of(coordinator.template.body)
                    Text(WordCount.caption(stats))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            variantsEditor
            fieldsSummary
        }
    }

    /// The always-visible companion rail: the live merged preview on top, the
    /// local content check, then the merge-field palette — no more scrolling
    /// past the editor to reach any of them.
    private var sideRail: some View {
        VStack(alignment: .leading, spacing: 16) {
            livePreview
            contentCheck
            fieldPalette
        }
    }

    // MARK: - Content check

    /// Live, on-device quality feedback: a 0–100 score plus specific findings
    /// (spam triggers, clipped subjects, missed personalization).
    @ViewBuilder
    private var contentCheck: some View {
        if !coordinator.isTemplateEmpty {
            let findings = ContentLinter.lint(template: coordinator.template)
            let score = ContentLinter.score(for: findings)
            SectionCard("Content check", systemImage: "checkmark.shield",
                        subtitle: "Checked on your Mac — nothing is sent anywhere.") {
                HStack(alignment: .top, spacing: 14) {
                    ScoreRing(score: score)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ContentLinter.grade(for: score))
                            .font(.subheadline.weight(.semibold))
                        if findings.isEmpty {
                            Label("No spam triggers, personalized, inbox-friendly.",
                                  systemImage: "checkmark.circle.fill")
                                .font(.callout).foregroundStyle(.green)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(findings) { finding in
                                Label(finding.message, systemImage: finding.systemImage)
                                    .font(.callout)
                                    .foregroundStyle(finding.severity == .warning ? .orange : .secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Instructions

    /// The merge-syntax guide, collapsed behind one button so the dashboard
    /// itself stays clean.
    private var instructionsButton: some View {
        Button {
            showInstructions.toggle()
        } label: {
            Label("How it works", systemImage: "questionmark.circle")
        }
        .popover(isPresented: $showInstructions, arrowEdge: .bottom) {
            MergeSyntaxGuide()
        }
        .help("A quick guide to merge fields, fallbacks, and formatters")
    }

    // MARK: - Starter templates

    /// A welcoming hero shown while the composer is empty: pick a ready-made
    /// template to learn the merge syntax by example, or just start typing.
    private var starterHero: some View {
        SectionCard("Start with a ready-made template",
                    systemImage: "wand.and.stars",
                    subtitle: "New here? Pick one to see how merge fields work — then make it your own. Or just start typing below.") {
            StarterTemplateGallery { starter in choose(starter) }
        }
    }

    private var starterGallerySheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start from a template").font(.title2.bold())
                    Text("Every one is a working example of merge fields, fallbacks, and formatters you can tweak.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Close") { showTemplateGallery = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                StarterTemplateGallery { starter in
                    showTemplateGallery = false
                    // Defer so the sheet finishes dismissing before we load or
                    // raise the overwrite confirmation on the window beneath.
                    DispatchQueue.main.async { choose(starter) }
                }
                .padding(20)
            }
        }
        .frame(width: 720, height: 560)
    }

    /// Opens the starter gallery if the welcome tour asked for it (deferred
    /// until Compose is on screen), then clears the request.
    private func consumeGalleryRequestIfNeeded() {
        guard coordinator.pendingStarterGalleryRequest else { return }
        coordinator.pendingStarterGalleryRequest = false
        // Defer one tick so the welcome sheet (if any) finishes dismissing
        // before we present the gallery on the same window.
        DispatchQueue.main.async { showTemplateGallery = true }
    }

    /// Loads a starter, but asks first if it would clobber existing writing.
    private func choose(_ starter: StarterTemplate) {
        if coordinator.isTemplateEmpty {
            load(starter)
        } else {
            pendingStarter = starter
        }
    }

    private func load(_ starter: StarterTemplate) {
        withAnimation { coordinator.loadStarterTemplate(starter) }
        focus = .body
    }

    // MARK: - Live preview

    private var livePreview: some View {
        let preview = coordinator.composePreview
        let isSample = coordinator.composePreviewIsSample
        let body = coordinator.template.format.isHTMLDelivery
            ? HTMLTextExtractor.plainText(fromHTML: preview.resolvedBody)
            : preview.resolvedBody
        return SectionCard("Live preview", systemImage: "eye",
                           subtitle: isSample ? "Sample recipient — import your list to preview real data"
                                              : "First recipient in your list") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Avatar(name: preview.contact.displayName)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preview.contact.displayName).font(.subheadline.weight(.semibold))
                        Text(preview.contact.email).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text("Subject").font(.caption).foregroundStyle(.secondary)
                Text(preview.resolvedSubject.isEmpty ? "—" : preview.resolvedSubject)
                    .font(.headline).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Body").font(.caption).foregroundStyle(.secondary)
                if coordinator.template.format == .rich {
                    // Render the Markdown natively so bold/italic/links/bullets
                    // show as formatted text, not raw markup.
                    Text(RichPreview.attributed(from: coordinator.composeMergedBodySource))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(body.isEmpty ? "—" : body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !preview.unresolvedFields.isEmpty {
                    Label("Missing for this recipient: \(preview.unresolvedFields.joined(separator: ", "))",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var templateLibraryMenu: some View {
        Menu {
            Button {
                showTemplateGallery = true
            } label: {
                Label("Start from a template…", systemImage: "wand.and.stars")
            }
            Divider()
            Button {
                newTemplateName = ""
                showSaveDialog = true
            } label: {
                Label("Save current template…", systemImage: "square.and.arrow.down")
            }
            if !coordinator.savedTemplates.isEmpty {
                Divider()
                Section("Load") {
                    ForEach(coordinator.savedTemplates.sorted(by: { $0.savedAt > $1.savedAt })) { saved in
                        Button(saved.name) { coordinator.loadTemplate(saved) }
                    }
                }
                Divider()
                Menu("Delete") {
                    ForEach(coordinator.savedTemplates.sorted(by: { $0.savedAt > $1.savedAt })) { saved in
                        Button(saved.name, role: .destructive) { coordinator.deleteTemplate(saved) }
                    }
                }
            }
        } label: {
            Label("Templates", systemImage: "tray.full")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .alert("Save template", isPresented: $showSaveDialog) {
            TextField("Template name", text: $newTemplateName)
            Button("Save") { coordinator.saveCurrentTemplate(as: newTemplateName) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Saves the subject, body, format, and any variants under a name you can reload later.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Compose your template").font(.title.bold())
            Text("Write it once — HighRise personalizes it for every recipient.")
                .foregroundStyle(.secondary)
        }
    }

    /// Live character count under the subject, warning when it's long enough to
    /// risk being clipped in a recipient's inbox.
    private var subjectCounter: some View {
        let stats = SubjectStats.of(coordinator.template.subject)
        return Text(stats.isLong
                    ? "\(stats.characters) characters — may be clipped in inboxes"
                    : "\(stats.characters) character\(stats.characters == 1 ? "" : "s")")
            .font(.caption)
            .foregroundStyle(stats.isLong ? .orange : .secondary)
    }

    private var bodyFormatPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Body format").font(.headline)
            Picker("Body format", selection: $coordinator.template.format) {
                ForEach(EmailTemplate.BodyFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)
            switch coordinator.template.format {
            case .rich:
                Text("Write with Markdown — **bold**, *italic*, [links](https://…), and “- ” bullet lists. It's converted to HTML on send; field values are escaped automatically. Full fidelity in Outlook; Apple Mail renders HTML as plain text.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .html:
                Text("Paste HTML markup as the body. Field values are HTML-escaped automatically. Full fidelity in Outlook; Apple Mail renders it as plain text.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .plainText:
                EmptyView()
            }
        }
    }

    // MARK: - Field palette

    private var fieldPalette: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Insert a merge field").font(.headline)
            Text("Click a field to add it where you're typing.")
                .font(.callout).foregroundStyle(.secondary)

            if !coordinator.importedHeaders.isEmpty {
                Text("From your list").font(.subheadline).foregroundStyle(.secondary)
                FieldChipsRow(fields: coordinator.importedHeaders.map { MergeField(name: $0, detail: "Column from your imported list") },
                              onInsert: insert)
            }

            DisclosureGroup("Recommended professional fields") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(MergeFieldCatalog.groups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.title).font(.subheadline).foregroundStyle(.secondary)
                            FieldChipsRow(fields: group.fields, onInsert: insert)
                        }
                    }
                }
                .padding(.top, 6)
            }
            .font(.subheadline)
        }
        .card(padding: 14)
    }

    /// Appends `field.token` to whichever box is focused (body by default),
    /// inserting a separating space when the existing text needs one.
    private func insert(_ field: MergeField) {
        let target: Field = (focus == .subject) ? .subject : .body
        switch target {
        case .subject:
            coordinator.template.subject = appended(field.token, to: coordinator.template.subject)
            focus = .subject
        case .body:
            coordinator.template.body = appended(field.token, to: coordinator.template.body)
            focus = .body
        }
    }

    private func appended(_ token: String, to existing: String) -> String {
        guard let last = existing.last else { return token }
        let needsSpace = !last.isWhitespace && last != "\n"
        return existing + (needsSpace ? " " : "") + token
    }

    // MARK: - Rich formatting toolbar

    /// Bold / italic / link / bullet buttons, shown only for the Rich (Markdown)
    /// body. Each inserts its Markdown snippet into the body via a pure helper.
    @ViewBuilder
    private var formattingToolbar: some View {
        if coordinator.template.format == .rich {
            HStack(spacing: 6) {
                ForEach(MarkdownFormatting.Style.allCases) { style in
                    Button {
                        coordinator.template.body =
                            MarkdownFormatting.inserting(style, into: coordinator.template.body)
                        focus = .body
                    } label: {
                        Image(systemName: style.systemImage)
                    }
                    .buttonStyle(.bordered)
                    .help("Insert \(style.label.lowercased())")
                    .accessibilityLabel(style.label)
                }
                Spacer()
            }
        }
    }

    // MARK: - Conditional variants

    private var variantsEditor: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Send a different subject/body to recipients matching a rule. The first matching variant wins; everyone else gets the template above.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach($coordinator.template.variants) { $variant in
                    variantCard($variant)
                }

                Button {
                    coordinator.template.variants.append(TemplateVariant())
                } label: {
                    Label("Add a variant", systemImage: "plus.circle")
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Conditional variants (\(coordinator.template.variants.count))", systemImage: "arrow.triangle.branch")
                .font(.headline)
        }
    }

    private func variantCard(_ variant: Binding<TemplateVariant>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("If").foregroundStyle(.secondary)
                fieldMenu(variant.rule.field)
                Picker("", selection: variant.rule.predicate) {
                    ForEach(RoutingRule.Predicate.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(maxWidth: 150)
                if variant.wrappedValue.rule.predicate.needsValue {
                    TextField("value", text: variant.rule.value)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 160)
                }
                Spacer()
                Button(role: .destructive) {
                    coordinator.template.variants.removeAll { $0.id == variant.wrappedValue.id }
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
            }
            TextField("Variant subject", text: variant.subject)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: variant.body)
                .font(.body).frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private func fieldMenu(_ selection: Binding<String>) -> some View {
        Menu {
            ForEach(coordinator.importedHeaders, id: \.self) { header in
                Button(header) { selection.wrappedValue = header }
            }
        } label: {
            Text(selection.wrappedValue.isEmpty ? "field" : selection.wrappedValue)
                .frame(maxWidth: 140)
        }
    }

    @ViewBuilder
    private var fieldsSummary: some View {
        let referenced = coordinator.template.referencedFields
        if !referenced.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Merge fields in this template").font(.headline)
                if coordinator.importedHeaders.isEmpty {
                    // No list imported yet — nothing to check the fields against.
                    FieldChipsRow(fields: referenced.map { MergeField(name: $0, detail: "") }, onInsert: nil)
                    Text("Import your contact list to see which fields are backed by a column.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    let report = FieldCoverage.assess(template: coordinator.template,
                                                      headers: coordinator.importedHeaders)
                    coverageSummaryLabel(report)
                    CoverageChipsRow(report: report)
                    if !report.missing.isEmpty {
                        Label("No column for \(report.missing.map(\.name).joined(separator: ", ")) — add a matching column or a fallback like {{Field|there}}, or those rows are held back.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    /// A one-line coverage verdict: green when every field is backed, neutral
    /// otherwise with the backed/needed counts.
    @ViewBuilder
    private func coverageSummaryLabel(_ report: FieldCoverage.Report) -> some View {
        if report.allBacked {
            Label(FieldCoverage.line(report), systemImage: "checkmark.seal.fill")
                .font(.callout).foregroundStyle(.green)
        } else {
            Label(FieldCoverage.line(report), systemImage: "list.bullet.clipboard")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// A wrapping row of merge-field chips. When `onInsert` is provided each chip is
/// a button; otherwise the chips are static labels (used to display detected
/// fields).
struct FieldChipsRow: View {
    let fields: [MergeField]
    let onInsert: ((MergeField) -> Void)?

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 90, maximum: 240), spacing: 8, alignment: .leading)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(fields) { field in
                if let onInsert {
                    Button { onInsert(field) } label: { chip(field) }
                        .buttonStyle(.plain)
                        .help(field.detail)
                } else {
                    chip(field)
                }
            }
        }
    }

    private func chip(_ field: MergeField) -> some View {
        Text(field.name)
            .font(.callout.monospaced())
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .contentShape(Capsule())
    }
}

/// Merge-field chips colored by how the imported list covers each field: green
/// when a column backs it, orange when a required field has no column (rows are
/// held back), and gray when it's only ever used with a fallback (safe). A quick
/// read of "will my merge actually resolve?" without leaving Compose.
struct CoverageChipsRow: View {
    let report: FieldCoverage.Report

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 90, maximum: 240), spacing: 8, alignment: .leading)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(report.fields) { field in
                HStack(spacing: 4) {
                    Image(systemName: icon(field.status)).font(.caption2)
                    Text(field.name).font(.callout.monospaced()).lineLimit(1)
                }
                .foregroundStyle(color(field.status))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(color(field.status).opacity(0.15), in: Capsule())
                .contentShape(Capsule())
                .help(helpText(field.status))
            }
        }
    }

    private func color(_ status: FieldCoverage.Status) -> Color {
        switch status {
        case .matched:  return .green
        case .missing:  return .orange
        case .fallback: return .gray
        }
    }

    private func icon(_ status: FieldCoverage.Status) -> String {
        switch status {
        case .matched:  return "checkmark.circle.fill"
        case .missing:  return "exclamationmark.triangle.fill"
        case .fallback: return "arrow.uturn.down.circle"
        }
    }

    private func helpText(_ status: FieldCoverage.Status) -> String {
        switch status {
        case .matched:  return "Backed by a column in your imported list."
        case .missing:  return "No matching column — add one or a fallback, or these rows are held back."
        case .fallback: return "No column, but every use has a fallback, so it won't hold rows back."
        }
    }
}

/// The merge-syntax cheat sheet behind Compose's "How it works" button — the
/// full instructions live here so the dashboard itself stays clean.
struct MergeSyntaxGuide: View {
    private struct Rule: Identifiable {
        var id: String { token }
        let token: String
        let explanation: String
    }

    private let rules: [Rule] = [
        Rule(token: "{{First Name}}",
             explanation: "Inserts that column's value from your list — any column works."),
        Rule(token: "{{First Name|there}}",
             explanation: "Fallback: rows with no value say “there” instead of being held back."),
        Rule(token: "{{Amount|currency:USD}}",
             explanation: "Formats numbers as money — 24500 becomes $24,500.00."),
        Rule(token: "{{Due Date|date:MMMM d, yyyy}}",
             explanation: "Reformats dates — 2026-07-22 becomes July 22, 2026."),
        Rule(token: "{{Name|fixcaps}}",
             explanation: "Fixes ALL-CAPS values — JANE DOE becomes Jane Doe.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("How merge fields work", systemImage: "curlybraces")
                .font(.headline)
            Text("Write your email once. Anything wrapped in double braces is filled in per recipient from your contact list.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            ForEach(rules) { rule in
                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.token)
                        .font(.callout.monospaced())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Brand.accent.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(rule.explanation)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            Label("Tip: click any field in the palette to drop it in where you're typing.",
                  systemImage: "lightbulb")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 400)
    }
}
