import Testing
@testable import HighRise

/// The results report is the accountability record of a run, so its row mapping
/// and CSV escaping (reused from the tested RFC-4180 writer) are pinned.
struct RunReportExporterTests {

    private func contact(_ name: String, _ email: String) -> Contact {
        Contact(fields: ["Name": name], email: email)
    }

    @Test("Outcomes and held rows map to the right status and detail")
    func rowMapping() {
        let outcomes = [
            SendOutcome(id: UUID(), contact: contact("Ada", "ada@x.com"), status: .sent),
            SendOutcome(id: UUID(), contact: contact("Bo", "bo@x.com"), status: .drafted),
            SendOutcome(id: UUID(), contact: contact("Cy", "cy@x.com"), status: .failed(reason: "declined")),
        ]
        let blocked = [
            TemplateMergeEngine.merge(template: EmailTemplate(subject: "Hi {{X}}", body: "y"),
                                      with: contact("Di", "di@x.com")) // missing {{X}} → held
        ]
        let rows = RunReportExporter.rows(outcomes: outcomes, blocked: blocked)
        #expect(rows.count == 4)
        #expect(rows[0] == .init(name: "Ada", email: "ada@x.com", status: "Sent", detail: ""))
        #expect(rows[1].status == "Draft created")
        #expect(rows[2] == .init(name: "Cy", email: "cy@x.com", status: "Failed", detail: "declined"))
        #expect(rows[3].status == "Held back")
        #expect(rows[3].detail.contains("Missing data"))
    }

    @Test("CSV has a header and one line per row, RFC-4180 escaped")
    func csvOutput() {
        let rows = [
            RunReportExporter.Row(name: "O'Hara, Sam", email: "s@x.com",
                                  status: "Failed", detail: "said \"no\""),
        ]
        let csv = RunReportExporter.csv(rows)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.first == "Name,Email,Status,Detail")
        // Comma and quotes force quoting + doubled quotes.
        #expect(csv.contains("\"O'Hara, Sam\""))
        #expect(csv.contains("\"said \"\"no\"\"\""))
    }

    @Test("An empty run still produces a header row")
    func emptyReport() {
        let csv = RunReportExporter.csv(RunReportExporter.rows(outcomes: [], blocked: []))
        #expect(csv == "Name,Email,Status,Detail\n")
    }
}
