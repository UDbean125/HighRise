import SwiftUI

/// A friendly, paged first-run tour. Shown once (tracked by `@AppStorage`), and
/// replayable any time from the sidebar's help button. Each page maps to one of
/// the four stages so a newcomer knows the shape of the whole trip before they
/// start — and the final page invites them to start from a ready-made template.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    /// Called when the user chooses to start from a template on the last page.
    var onStartWithTemplate: () -> Void = {}
    /// Called when the user chooses the interactive walkthrough of the dashboard.
    var onTakeTour: () -> Void = {}

    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let systemImage: String
        let title: String
        let blurb: String
    }

    private let pages: [Page] = [
        Page(systemImage: "building.2.fill",
             title: "Welcome to HighRise",
             blurb: "Send one email to your whole list — personalized for every single person. No servers, no sign-ups, no monthly fee. HighRise drafts and sends right through Apple Mail or Outlook on your Mac."),
        Page(systemImage: "square.and.pencil",
             title: "1 · Compose",
             blurb: "Write your email once. Wrap any field in double braces — like “Hi {{First Name}},” — and HighRise fills it in for each recipient. Not sure where to start? Kick off from a ready-made template."),
        Page(systemImage: "person.2.fill",
             title: "2 · Contacts",
             blurb: "Drag in a CSV or Excel file. Every column becomes a merge field you can drop into your email — {{Company}}, {{Amount}}, anything. HighRise lines them up for you."),
        Page(systemImage: "checklist",
             title: "3 · Review",
             blurb: "Preview every message exactly as it’ll arrive, one per person. HighRise quietly flags rows with missing details or duplicate addresses so nothing awkward slips out."),
        Page(systemImage: "paperplane.fill",
             title: "4 · Send",
             blurb: "Create drafts to eyeball first, or send them all at once. Pick Apple Mail or Outlook, add CC/BCC, pace the sending — you stay in control the whole way.")
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            hero
            controls
        }
        .frame(width: 480, height: 460)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(Brand.gradient)
                    .frame(width: 108, height: 108)
                    .shadow(color: Brand.accent.opacity(0.4), radius: 14, y: 5)
                Image(systemName: pages[page].systemImage)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .transition(.scale.combined(with: .opacity))
            .id(pages[page].id)

            VStack(spacing: 10) {
                Text(pages[page].title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(pages[page].blurb)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 36)
            .id(pages[page].id)
            .transition(.opacity)

            Spacer(minLength: 0)

            pageDots
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 12)
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == page ? Brand.accent : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
                    .onTapGesture { withAnimation(.easeInOut) { page = index } }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            Divider()
            HStack(spacing: 10) {
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                if isLastPage {
                    Button("Start with a template") {
                        onStartWithTemplate()
                    }
                    .buttonStyle(.bordered)

                    Button("Take the tour") { onTakeTour() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Next") { withAnimation(.easeInOut) { page += 1 } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
    }

    private func finish() {
        dismiss()
    }
}
