import Testing
import Foundation
import AppKit
@testable import HighRise

/// The starter gallery is a new user's first impression *and* their tutorial in
/// the merge syntax, so the catalog is pinned: it must be well-formed, and — the
/// load-bearing guarantee — every fallback placeholder it ships must resolve so
/// a starter previewed against the sample never shows the user a raw `{{token}}`.
struct StarterTemplateCatalogTests {

    private var all: [StarterTemplate] { StarterTemplateCatalog.all }

    @Test("Ships a non-trivial, well-formed catalog")
    func wellFormed() {
        #expect(all.count >= 25)
        #expect(Set(all.map(\.id)).count == all.count, "IDs must be unique")
        #expect(Set(all.map(\.name)).count == all.count, "Names must be unique")
        for starter in all {
            #expect(!starter.id.isEmpty)
            #expect(!starter.name.isEmpty)
            #expect(!starter.category.isEmpty)
            #expect(!starter.systemImage.isEmpty)
            #expect(!starter.blurb.isEmpty)
            #expect(!starter.subject.isEmpty, "\(starter.id) has an empty subject")
            #expect(!starter.body.isEmpty, "\(starter.id) has an empty body")
        }
    }

    @Test("Every card icon is a real SF Symbol")
    func iconsResolve() {
        // A typo'd or too-new symbol name renders as a blank square rather
        // than failing loudly, so the gallery would quietly look broken.
        for starter in all {
            #expect(NSImage(systemSymbolName: starter.systemImage, accessibilityDescription: nil) != nil,
                    "\(starter.id) uses “\(starter.systemImage)”, which doesn't resolve on this OS")
        }
        for industry in TemplateIndustry.allCases {
            #expect(NSImage(systemSymbolName: industry.systemImage, accessibilityDescription: nil) != nil,
                    "\(industry.rawValue) uses “\(industry.systemImage)”, which doesn't resolve on this OS")
        }
    }

    @Test("Search matches name, blurb, industry, and audience wording")
    func searchFindsTemplates() {
        let driver = all.first { $0.id == "transport-driver-seat-open" }
        #expect(driver != nil)
        if let driver {
            #expect(StarterTemplateCatalog.matches(driver, query: "driver"))
            // Industry and audience labels are searchable even when the word
            // appears nowhere in the copy.
            #expect(StarterTemplateCatalog.matches(driver, query: "Transportation"))
            #expect(StarterTemplateCatalog.matches(driver, query: "candidates"))
            // Every word must hit — this is a narrowing search, not an OR.
            #expect(!StarterTemplateCatalog.matches(driver, query: "driver dentist"))
        }
        // An empty query matches everything.
        #expect(all.allSatisfy { StarterTemplateCatalog.matches($0, query: "   ") })
    }

    @Test("emailTemplate round-trips the starter's content")
    func emailTemplateRoundTrips() {
        for starter in all {
            let template = starter.emailTemplate
            #expect(template.subject == starter.subject)
            #expect(template.body == starter.body)
            #expect(template.format == starter.format)
        }
    }

    @Test("Never leaks a raw placeholder, even with no data at all")
    func neverLeaksAPlaceholder() {
        // The load-bearing guarantee: whatever the row, a raw `{{token}}` must
        // never reach the rendered output. Merging against a contact with *no*
        // fields is the worst case — every placeholder must still be stripped
        // (to its fallback, a formatted value, or empty).
        let empty = Contact(fields: [:], email: "nobody@example.com")
        for starter in all {
            let preview = TemplateMergeEngine.merge(template: starter.emailTemplate, with: empty)
            #expect(!preview.resolvedSubject.contains("{{"),
                    "\(starter.id) subject leaked a placeholder")
            #expect(!preview.resolvedBody.contains("{{"),
                    "\(starter.id) body leaked a placeholder")
        }
    }

    @Test("Grouping covers every template, in the declared category order")
    func grouping() {
        let grouped = StarterTemplateCatalog.byCategory
        // Nothing lost or duplicated by grouping.
        #expect(grouped.flatMap(\.templates).count == all.count)
        #expect(Set(grouped.map(\.category)).count == grouped.count, "Categories must be distinct")
        #expect(grouped.allSatisfy { !$0.templates.isEmpty }, "No empty category groups")

        // Known categories appear in `categoryOrder`'s order, ahead of any
        // unlisted ones.
        let ranks = grouped.map { StarterTemplateCatalog.categoryOrder.firstIndex(of: $0.category) ?? Int.max }
        #expect(ranks == ranks.sorted(), "Categories must follow categoryOrder")

        // Every category the templates actually use is a known one — a typo'd
        // category would otherwise silently sort to the end.
        for group in grouped {
            #expect(StarterTemplateCatalog.categoryOrder.contains(group.category),
                    "Unknown category “\(group.category)” — add it to categoryOrder")
        }
    }

    @Test("Every category carries a useful number of templates")
    func categoriesAreSubstantial() {
        for group in StarterTemplateCatalog.byCategory {
            #expect(group.templates.count >= 3,
                    "Category “\(group.category)” has only \(group.templates.count)")
        }
    }

    @Test("Previews cleanly against the built-in sample recipient")
    func mergesAgainstSample() {
        // Each starter is authored to line up with `Contact.sample`, so the very
        // first preview a newcomer sees looks like a genuine send: no "missing
        // for this recipient" warnings, no blank spots.
        for starter in all {
            let preview = TemplateMergeEngine.merge(template: starter.emailTemplate, with: .sample)
            #expect(preview.unresolvedFields.isEmpty,
                    "\(starter.id) references fields the sample can't fill: \(preview.unresolvedFields)")
        }
    }

    // MARK: - Industry / audience filters

    @Test("Every industry has a useful number of tailored starters")
    func everyIndustryHasTailoredStarters() {
        // Each of the twelve North American sectors needs enough depth that
        // picking it in the dropdown is worth doing — one lonely card isn't.
        for industry in TemplateIndustry.allCases {
            let count = StarterTemplateCatalog.tailoredCount(for: industry)
            #expect(count >= 3, "Only \(count) starter(s) written for “\(industry.rawValue)”")
        }
    }

    @Test("Every industry × audience pair has a purpose-written starter")
    func industryAudienceMatrixIsCovered() {
        // The gallery lets someone choose their sector *and* who they're
        // emailing, so every one of the 48 cells needs a starter written in
        // that industry's vocabulary and shaped for that reader — not a
        // neutral one standing in.
        for industry in TemplateIndustry.allCases {
            for audience in TemplateAudience.allCases {
                let written = all.filter {
                    $0.industries.contains(industry) && $0.audiences.contains(audience)
                }
                #expect(!written.isEmpty,
                        "Nothing written for “\(industry.rawValue)” addressed to “\(audience.rawValue)”")
            }
        }
    }

    @Test("Choosing an industry and an audience still leads with tailored work")
    func tailoredBandSurvivesAudienceFilter() {
        // Because the matrix is fully covered, narrowing to a sector *and* an
        // audience must still produce a "Made for …" band — never drop the
        // user into nothing but generic templates.
        for industry in TemplateIndustry.allCases {
            for audience in TemplateAudience.allCases {
                let sections = StarterTemplateCatalog.sections(industry: industry, audience: audience)
                #expect(sections.first?.industry == industry,
                        "\(industry.rawValue) + \(audience.rawValue) lost its tailored band")
            }
        }
    }

    @Test("Industry-tailored starters spread across more than one task group")
    func tailoredStartersSpanCategories() {
        for industry in TemplateIndustry.allCases {
            let categories = Set(all.filter { $0.industries.contains(industry) }.map(\.category))
            #expect(categories.count >= 2,
                    "All “\(industry.rawValue)” starters land in one task group (\(categories))")
        }
    }

    // MARK: - Sectioned gallery

    @Test("With no industry chosen the gallery is one band holding everything")
    func sectionsWithoutIndustry() {
        let sections = StarterTemplateCatalog.sections(industry: nil, audience: nil)
        #expect(sections.count == 1)
        #expect(sections[0].industry == nil)
        #expect(sections[0].count == all.count)
        #expect(sections[0].groups.map(\.category) == StarterTemplateCatalog.byCategory.map(\.category))
    }

    @Test("Choosing an industry splits the gallery into tailored and neutral bands")
    func sectionsWithIndustry() {
        for industry in TemplateIndustry.allCases {
            let sections = StarterTemplateCatalog.sections(industry: industry, audience: nil)
            #expect(sections.count == 2, "\(industry.rawValue) didn't produce both bands")

            let tailored = sections[0]
            #expect(tailored.industry == industry, "The tailored band must come first")
            #expect(tailored.title == "Made for \(industry.rawValue)")
            #expect(tailored.groups.allSatisfy { $0.templates.allSatisfy { $0.industries.contains(industry) } },
                    "A neutral starter leaked into the tailored band")
            #expect(tailored.count == StarterTemplateCatalog.tailoredCount(for: industry))

            let neutral = sections[1]
            #expect(neutral.industry == nil)
            #expect(neutral.groups.allSatisfy { $0.templates.allSatisfy(\.industries.isEmpty) },
                    "A tailored starter leaked into the any-industry band")

            // Another industry's starters appear in neither band.
            let shown = Set(sections.flatMap { $0.groups.flatMap(\.templates) }.map(\.id))
            let otherIndustryOnly = all.filter { !$0.industries.isEmpty && !$0.industries.contains(industry) }
            #expect(otherIndustryOnly.allSatisfy { !shown.contains($0.id) },
                    "\(industry.rawValue) is showing another sector's starters")
        }
    }

    @Test("Sections keep the task groups as their subsections, in catalog order")
    func sectionsPreserveCategoryOrder() {
        let order = StarterTemplateCatalog.byCategory.map(\.category)
        for industry in TemplateIndustry.allCases {
            for section in StarterTemplateCatalog.sections(industry: industry, audience: nil) {
                let categories = section.groups.map(\.category)
                #expect(categories == order.filter(categories.contains),
                        "“\(section.title)” lists task groups out of order")
                #expect(section.groups.allSatisfy { !$0.templates.isEmpty },
                        "“\(section.title)” has an empty task group")
            }
        }
    }

    @Test("No industry/audience combination empties the sectioned gallery")
    func sectionsNeverDeadEnd() {
        for industry in TemplateIndustry.allCases {
            for audience in TemplateAudience.allCases {
                let sections = StarterTemplateCatalog.sections(industry: industry, audience: audience)
                #expect(!sections.flatMap { $0.groups.flatMap(\.templates) }.isEmpty,
                        "\(industry.rawValue) + \(audience.rawValue) shows nothing")
            }
        }
    }

    @Test("Sections never duplicate a template")
    func sectionsAreDisjoint() {
        for industry in TemplateIndustry.allCases {
            let ids = StarterTemplateCatalog.sections(industry: industry, audience: nil)
                .flatMap { $0.groups.flatMap(\.templates) }.map(\.id)
            #expect(Set(ids).count == ids.count, "\(industry.rawValue) shows a template twice")
        }
    }

    @Test("Every audience has at least one tagged starter")
    func everyAudienceHasAStarter() {
        for audience in TemplateAudience.allCases {
            #expect(all.contains { $0.audiences.contains(audience) },
                    "No starter is addressed to “\(audience.rawValue)”")
        }
    }

    @Test("No industry/audience combination empties the gallery")
    func filtersNeverDeadEnd() {
        // Neutral starters (empty tag sets) fit every filter, so whatever the
        // user picks in the two dropdowns, something useful must remain.
        for industry in TemplateIndustry.allCases {
            for audience in TemplateAudience.allCases {
                let groups = StarterTemplateCatalog.byCategory(industry: industry, audience: audience)
                #expect(!groups.flatMap(\.templates).isEmpty,
                        "\(industry.rawValue) + \(audience.rawValue) shows nothing")
            }
        }
    }

    @Test("Nil filters reproduce the full grouped catalog")
    func nilFiltersAreIdentity() {
        let unfiltered = StarterTemplateCatalog.byCategory(industry: nil, audience: nil)
        #expect(unfiltered.flatMap(\.templates).count == all.count)
        #expect(unfiltered.map(\.category) == StarterTemplateCatalog.byCategory.map(\.category))
    }

    @Test("Industry-tailored starters lead their category when that industry is chosen")
    func tailoredStartersFloatToTheTop() {
        for industry in TemplateIndustry.allCases {
            for group in StarterTemplateCatalog.byCategory(industry: industry, audience: nil) {
                // Once a neutral starter appears, no tailored one may follow it.
                var seenNeutral = false
                for template in group.templates {
                    let tailored = template.industries.contains(industry)
                    if !tailored { seenNeutral = true }
                    #expect(!(tailored && seenNeutral),
                            "\(template.id) is tailored for \(industry.rawValue) but sorted after neutral starters in “\(group.category)”")
                }
            }
        }
    }

    @Test("A tagged starter fits its own tags and the no-filter state")
    func fitsSemantics() {
        let tagged = StarterTemplate(id: "x", name: "x", category: "Grow", systemImage: "x",
                                     blurb: "x", subject: "s", body: "b",
                                     audiences: [.prospects], industries: [.retail])
        #expect(tagged.fits(industry: nil) && tagged.fits(audience: nil))
        #expect(tagged.fits(industry: .retail) && tagged.fits(audience: .prospects))
        #expect(!tagged.fits(industry: .healthcare))
        #expect(!tagged.fits(audience: .candidates))

        let neutral = StarterTemplate(id: "y", name: "y", category: "Grow", systemImage: "y",
                                      blurb: "y", subject: "s", body: "b")
        for industry in TemplateIndustry.allCases { #expect(neutral.fits(industry: industry)) }
        for audience in TemplateAudience.allCases { #expect(neutral.fits(audience: audience)) }
    }
}
