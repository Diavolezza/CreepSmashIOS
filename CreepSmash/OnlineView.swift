import SwiftUI
import CreepSmashCore

/// The three ways to play online through Game Center: invite friends (the inviter chooses the map and, in the
/// lobby before the start, computers for free seats), random opponents (Game Center looks for up to three for 30 s), share a code (party
/// code, iOS 26 and later). Shown on the multiplayer page under "Online".
struct OnlinePanels: View {
    let matchmaker: Matchmaker
    @Binding var mapID: String
    let name: String
    /// Opens the code entry of the page (above the keyboard).
    let enterCode: () -> Void
    /// The code typed so far (shared with the code entry of the page).
    let code: String

    private var partyCodes: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    var body: some View {
        GeometryReader { geo in
            if geo.size.height > geo.size.width {
                VStack(spacing: Theme.s(12)) {
                    HStack(alignment: .top, spacing: Theme.s(12)) {
                        randomPanel
                        codePanel
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    invitePanel(mapSize: MultiplayerView.mapSize(for: geo.size))
                }
            } else {
                HStack(alignment: .top, spacing: Theme.s(12)) {
                    invitePanel(mapSize: MultiplayerView.mapSize(for: geo.size))
                    randomPanel
                    codePanel
                }
            }
        }
    }

    // MARK: The three ways

    private func invitePanel(mapSize: CGFloat) -> some View {
        MultiplayerPanel(L("Invite friends"),
                         L("You choose the map; before the start you can give free seats to computers.")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.s(8)) {
                    ForEach(GameMap.all, id: \.id) { map in
                        MapCard(map: map, selected: map.id == mapID, size: mapSize)
                            .onTapGesture { mapID = map.id }
                    }
                }
            }
            Spacer(minLength: 0)
            Button(L("Invite")) { GameCenter.shared.inviteFriends(mapID: mapID) }
                .buttonStyle(MenuButtonStyle(minWidth: 0, fill: true, shrinks: false))
                .layoutPriority(1)
        }
    }

    private var randomPanel: some View {
        MultiplayerPanel(L("Random opponents"),
                         L("Game Center looks for up to three players. After 30 seconds the round starts with everyone found; free seats are taken by computers, the map is drawn at random.")) {
            Spacer(minLength: 0)
            Button(L("Find opponents")) { GameCenter.shared.findRandomOpponents() }
                .buttonStyle(MenuButtonStyle(minWidth: 0, fill: true, shrinks: false))
                .layoutPriority(1)
        }
    }

    private var codePanel: some View {
        MultiplayerPanel(L("Share a code"),
                         partyCodes ? L("Create a code and send it to the others, or enter the code someone sent you.")
                                    : L("Codes for online rounds need iOS 26 or later on every device.")) {
            Spacer(minLength: 0)
            // Looks like an input field; a tap opens the entry above the keyboard.
            Button(action: enterCode) {
                HStack(spacing: Theme.s(8)) {
                    Image(systemName: "keyboard")
                    Text(code.isEmpty ? L("Enter code") : code)
                        .foregroundStyle(code.isEmpty ? .gray : Theme.green)
                    Spacer(minLength: 0)
                }
                .font(Theme.mono(14))
                .foregroundStyle(.gray)
                .padding(.horizontal, Theme.s(10))
                .padding(.vertical, Theme.s(7))
                .background(RoundedRectangle(cornerRadius: Theme.s(6)).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: Theme.s(6)).stroke(Theme.dimGreen, lineWidth: Theme.s(1)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            Button(L("Create code")) { GameCenter.shared.createPartyCode(mapID: mapID) }
                .buttonStyle(MenuButtonStyle(minWidth: 0, fill: true, shrinks: false))
                .layoutPriority(1)
        }
        .disabled(!partyCodes)
        .opacity(partyCodes ? 1 : 0.5)
    }
}

/// Shown under "Online" while the player is not signed in to Game Center.
struct OnlineSignInHint: View {
    var body: some View {
        MultiplayerPanel(L("Game Center"),
                         L("Online rounds run through Game Center. Sign in to Game Center in the Settings app; then the three ways to play online appear here.")) {
            EmptyView()
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: Theme.s(520))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A tile of the multiplayer page: title, explanation, then its controls.
struct MultiplayerPanel<Content: View>: View {
    let title: String
    let text: String
    let content: Content

    init(_ title: String, _ text: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.text = text
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s(10)) {
            Text(title).font(Theme.pixel(12)).foregroundStyle(Theme.green)
            Text(text).font(Theme.mono(14)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .padding(Theme.s(14))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.s(10)).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Theme.s(10)).stroke(Theme.dimGreen.opacity(0.6), lineWidth: Theme.s(1)))
    }
}
