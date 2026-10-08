import SwiftUI

/// Version of the app as shown to the player: 0.1.N, N counts the commits (set by build.sh commit).
enum AppVersion {
    static var text: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }
}

/// Credits: where the game comes from, who made the remake, version, fonts.
struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s(18)) {
                    HStack(alignment: .center, spacing: Theme.s(16)) {
                        Image("logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: Theme.s(260))
                        Spacer(minLength: 0)
                        Text(L("Version \(AppVersion.text)"))
                            .foregroundStyle(.gray)
                    }
                    section(L("Original")) {
                        Text(L("CreepSmash was developed in Java in the summer semester of 2008 by ten computer science students at Hochschule für Technik Stuttgart (HFT Stuttgart), in the course Informatikprojekt 2. It was the first tower defense for several players over the network."))
                        Text(L("Supervision: Prof. Dr.-Ing. Gerhard Wanner"))
                        Link("hft-stuttgart.de", destination: URL(string: "https://www.hft-stuttgart.de")!)
                            .foregroundStyle(Theme.green)
                    }
                    section(L("Team of the original")) {
                        // Alphabetical, as listed in the project report.
                        Text(Self.team.joined(separator: " · "))
                    }
                    section(L("Remake for iPhone and iPad")) {
                        Text("Prof. Dr.-Ing. Gerhard Wanner")
                        Text(L("Towers, creeps, sound effects and music were made for this app."))
                    }
                    section(L("Fonts")) {
                        Text("Press Start 2P · © 2012 The Press Start 2P Project Authors")
                        Text("VT323 · © 2011 The VT323 Project Authors")
                        Text(L("Both under the SIL Open Font License 1.1."))
                    }
                }
                .font(Theme.mono(15))
                .foregroundStyle(Theme.text)
                .tint(Theme.green)
                .padding(.horizontal, Theme.s(24))
                .padding(.vertical, Theme.s(14))
            }
            .background(Theme.background)
            .navigationTitle(L("Credits"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .pageSizedSheet()
    }

    static let team = [
        "Andreas Wittig", "Bernd Hietler", "Christoph Fritz", "Fabian Kessel", "Levin Fritz",
        "Nikolaj Langner", "Philipp Schulte-Hubbert", "Robert Rapczynski", "Ron Trautsch", "Sven Supper",
    ]

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.s(6)) {
            Text(title).font(Theme.pixel(12)).foregroundStyle(Theme.green)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
