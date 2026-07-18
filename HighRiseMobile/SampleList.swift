import Foundation

#if DEBUG
/// Demo data for development and App Store screenshots — a realistic AEC
/// prospect list with deliberate gaps (blank names, companies, websites, one
/// missing email) so the import screen's cleanup and fill-proposal features
/// have something to show. DEBUG-only: never compiled into release builds.
enum SampleList {
    static let csv = """
    First Name,Last Name,Company,Job Title,Email,Website
    Jordan,Avery,Northwind Traders,Director of Procurement,jordan.avery@northwind-traders.com,
    ,,Kimley-Horn,Design Director,riley.chen@kimley-horn.com,
    Sam,Patel,,Project Executive,sam.patel@acme-construction.com,
    Maria,Garcia,Stark Engineering,Principal Engineer,maria.garcia@stark-engineering.com,https://stark-engineering.com
    ,,Turner Construction,VP Preconstruction,alex.morgan@turnerconstruction.com,
    Casey,Lee,Gensler,Studio Director,,
    Taylor,Brooks,HOK,Managing Principal,taylor.brooks@hok.com,
    ,,Skanska USA,Senior Estimator,jamie.fox@skanska.com,
    Priya,Shah,AECOM,Transportation Lead,priya.shah@aecom.com,
    Omar,Haddad,Parsons,Program Manager,omar.haddad@parsons.com,
    """

    /// A ready-made template so Compose/Review screens are populated too.
    static let templateSubject = "Quick intro — {{Company}} + Hen Solutions"
    static let templateBody = """
    Hi {{First Name}},

    I work with AEC firms like {{Company}} on design-technology adoption, and \
    I'd love 20 minutes to share what nearby teams are doing to cut rework on \
    active projects.

    Would next Tuesday or Wednesday afternoon work for a quick call?

    Best,
    Bryan Hennigan
    Hen Solutions LLC
    """
}
#endif
