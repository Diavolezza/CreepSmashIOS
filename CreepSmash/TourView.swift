import SwiftUI
import CreepSmashCore

/// Short introduction on the first start: goal, building towers, sending creeps, income – four pages that can
/// be skipped. Later it opens from "How to play" (the "?" in the menu).
struct TourView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    /// Shown once on the first start; set when it is closed (skipped or finished).
    static let seenKey = "tourSeen"

    /// Not over automated starts (screenshots, tests, measurements in the Simulator or with Instruments).
    static var suppressedByLaunchArguments: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return ["-noTour", "-musicEnabled", "-demo", "-play", "-resume", "-host", "-join", "-quick", "-multiplayer",
                "-records", "-report", "-setup", "-credits"].contains { arguments.contains($0) }
    }

    private struct Page {
        let title: String
        let text: String
        let picture: AnyView
    }

    private var pages: [Page] {
        [
            Page(title: L("Goal"),
                 text: L("Every player has 20 lives. A creep that reaches the end of your path costs you one. The last player with lives left wins."),
                 picture: AnyView(lives)),
            Page(title: L("Build towers"),
                 text: L("Pick a tower on the left and tap a free cell next to the path. Towers shoot the creeps on your board. Tap a tower to upgrade or sell it."),
                 picture: AnyView(icons((1...6).map { "towerButton\($0)" }))),
            Page(title: L("Send creeps"),
                 text: L("Tap a creep on the right to send it to your opponent. Hold it to keep sending until you let go."),
                 picture: AnyView(icons((1...6).map { "creepIcon\($0)" }))),
            Page(title: L("Income"),
                 text: L("Every creep you send raises your income for good. Every 10 seconds the income is added to your credits – so attacking also pays for your towers."),
                 picture: AnyView(income)),
        ]
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: Theme.s(12)) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageView(pages[index]).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                // Both buttons share one width.
                HStack(spacing: Theme.s(16)) {
                    Button(L("Skip")) { close() }
                        .buttonStyle(MenuButtonStyle(color: Theme.text, minWidth: Theme.s(220), shrinks: false))
                        .opacity(page < pages.count - 1 ? 1 : 0)
                        .disabled(page >= pages.count - 1)
                    Button(page < pages.count - 1 ? L("Next page") : L("Let's go")) {
                        if page < pages.count - 1 { withAnimation { page += 1 } } else { close() }
                    }
                    .buttonStyle(MenuButtonStyle(minWidth: Theme.s(220), shrinks: false))
                }
                .padding(.bottom, Theme.s(14))
            }
            .padding(.horizontal, Theme.s(24))
            .padding(.top, Theme.s(10))
        }
        .preferredColorScheme(.dark)
    }

    private func close() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        dismiss()
    }

    /// Picture on the left, text on the right (landscape); one above the other where it is narrow.
    private func pageView(_ page: Page) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.s(36)) {
                page.picture.frame(width: Theme.s(300))
                text(page).frame(maxWidth: Theme.s(460), alignment: .leading)
            }
            VStack(spacing: Theme.s(20)) {
                page.picture
                text(page).frame(maxWidth: Theme.s(460))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, Theme.s(30))   // room for the page dots
    }

    private func text(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: Theme.s(12)) {
            Text(page.title).font(Theme.pixel(18)).foregroundStyle(Theme.green)
            Text(page.text).font(Theme.mono(17)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Pictures

    private var lives: some View {
        VStack(spacing: Theme.s(10)) {
            Image(systemName: "heart.fill").font(.system(size: Theme.s(72))).foregroundStyle(Theme.warning)
                .shadow(color: Theme.warning.opacity(0.6), radius: 14)
            Text(verbatim: "20").font(Theme.pixel(28)).foregroundStyle(Theme.text)
        }
        .accessibilityHidden(true)
    }

    private func icons(_ names: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Theme.s(76)), spacing: Theme.s(10)), count: 3),
                  spacing: Theme.s(10)) {
            ForEach(names, id: \.self) { name in
                Image(name).interpolation(.high).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: Theme.s(64), height: Theme.s(64))
                    .padding(Theme.s(6))
                    .background(RoundedRectangle(cornerRadius: Theme.s(8)).stroke(Theme.dimGreen, lineWidth: Theme.s(1)))
            }
        }
        .accessibilityHidden(true)
    }

    private var income: some View {
        HStack(spacing: Theme.s(14)) {
            Image("creepIcon1").interpolation(.high).resizable().frame(width: Theme.s(56), height: Theme.s(56))
            Image(systemName: "arrow.right").font(.system(size: Theme.s(28))).foregroundStyle(Theme.text)
            VStack(spacing: Theme.s(6)) {
                Image(systemName: "dollarsign.circle.fill").font(.system(size: Theme.s(56))).foregroundStyle(Theme.gold)
                    .shadow(color: Theme.gold.opacity(0.5), radius: 12)
                Text(verbatim: "+").font(Theme.pixel(20)).foregroundStyle(Theme.gold)
            }
        }
        .accessibilityHidden(true)
    }
}
