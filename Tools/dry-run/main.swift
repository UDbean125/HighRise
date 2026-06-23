import Foundation

// A reproducible, no-Mail dry run of HighRise's CSV → merge → AppleScript
// pipeline. Compiled against the *real* shipping source (see Tools/dry-run.sh),
// so it exercises the exact CSVParser / TemplateMergeEngine / AppleScriptBuilder
// code the app uses — there is no second implementation to drift out of sync.
//
// For every recipient it either prints the AppleScript that *would* be handed
// to Mail (had MailSender run it), or explains why the row was blocked before a
// script was ever built. Nothing is sent and Mail is never launched.

let args = CommandLine.arguments
let csvPath = args.count > 1 ? args[1] : "Examples/sample-recipients.csv"

guard let csvText = try? String(contentsOfFile: csvPath, encoding: .utf8) else {
    FileHandle.standardError.write(Data("Could not read CSV at \(csvPath)\n".utf8))
    exit(1)
}

// Mirrors the README's worked example. Swap to `.html` to watch the second
// escaping layer (TemplateMergeEngine.htmlEscape) kick in before AppleScript.
let template = EmailTemplate(
    subject: "Quick question about {{Company}}",
    body: """
    Hi {{Name}},

    I wanted to reach out about {{Company}}.

    Best,
    Bryan
    """,
    format: .plainText
)

let client: MailClient = .appleMail
let mode: SendMode = .draft
let rule = String(repeating: "─", count: 60)

do {
    let table = try CSVParser.parse(csvText)
    let (contacts, emailHeader) = CSVParser.contacts(from: table)
    print("Parsed \(contacts.count) contact(s) from \(csvPath)")
    print("Email column: \(emailHeader ?? "—")  ·  client: \(client.rawValue)  ·  mode: \(mode.rawValue)\n")

    let previews = TemplateMergeEngine.mergeAll(template: template, contacts: contacts)
    var sendable = 0
    var blocked = 0

    for preview in previews {
        let name = preview.contact.displayName
        guard preview.isSendable else {
            blocked += 1
            print("🚫 \(name) — blocked: \(preview.blockingReason ?? "unknown")\n")
            continue
        }
        sendable += 1
        let message = ComposedMessage(
            recipientEmail: preview.contact.email,
            recipientName: name,
            subject: preview.resolvedSubject,
            body: preview.resolvedBody,
            isHTML: template.format == .html
        )
        let script = AppleScriptBuilder.script(for: message, client: client, mode: mode)
        print("✅ \(name) <\(preview.contact.email)> — would create a draft:")
        print(rule)
        print(script)
        print(rule + "\n")
    }

    print("Summary: \(sendable) draft(s) would be created, \(blocked) blocked. No mail was touched.")
} catch {
    FileHandle.standardError.write(Data("Parse failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
