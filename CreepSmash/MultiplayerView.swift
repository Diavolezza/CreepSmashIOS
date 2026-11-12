import SwiftUI
import CreepSmashCore

/// Multiplayer, in two parts. Online (Game Center): invite friends, random opponents, share a code. Nearby
/// (local network): quick game for two, open a round for two to four (with a code), join a round from the
/// list or with its code.
struct MultiplayerView: View {
    enum Tab { case online, nearby }

    let matchmaker: Matchmaker
    @Binding var mapID: String
    @Binding var playerName: String
    let onCancel: () -> Void
    @State private var code = ""
    /// The code is being typed: a small panel at the top with the field, above the keyboard.
    @State private var enteringCode = false
    /// Online or nearby; online first while signed in to Game Center.
    @State private var tab: Tab = GameCenter.shared.isAuthenticated || Self.onlinePreview ? .online : .nearby
    /// Screenshots in the Simulator (not signed in to Game Center there): "-onlinePreview" shows the online part.
    static var onlinePreview: Bool { ProcessInfo.processInfo.arguments.contains("-onlinePreview") }
    @FocusState private var codeFocused: Bool

    /// Without a name an empty one is sent; the other devices then show "Opponent" or "Player n".
    private var name: String { PlayerName.current(typed: playerName) }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: Theme.s(12)) {
                PageHeader(L("Multiplayer"), onBack: onCancel) {
                    HStack(spacing: Theme.s(8)) {
                        Text(L("Name")).font(Theme.mono(13)).foregroundStyle(.gray)
                        PlayerNameField(text: $playerName, width: Theme.s(150))
                    }
                }
                tabs
                if tab == .online {
                    if GameCenter.shared.isAuthenticated || Self.onlinePreview {
                        OnlinePanels(matchmaker: matchmaker, mapID: $mapID, name: name,
                                     enterCode: startCodeEntry, code: code)
                    } else {
                        OnlineSignInHint()
                    }
                } else {
                    nearbyPanels
                }
            }
            .padding(.horizontal, Theme.s(24))
            .padding(.vertical, Theme.s(10))
            // The keyboard does not squeeze the tiles; the code is typed in its own panel above it.
            .ignoresSafeArea(.keyboard)

            if enteringCode {
                codeEntry
            }
            if matchmaker.state != .idle {
                statusOverlay
            }
        }
        .onAppear {
            if GameMap.named(mapID) == nil { mapID = GameMap.all[0].id }
            matchmaker.listGames()
            // Screenshots: "-enterCode" opens the code entry, "-sampleRounds" fills the list with made-up rounds,
            // "-nearby" / "-online" show that part.
            if ProcessInfo.processInfo.arguments.contains("-nearby") { tab = .nearby }
            if ProcessInfo.processInfo.arguments.contains("-online") { tab = .online }
            if ProcessInfo.processInfo.arguments.contains("-enterCode") { enteringCode = true }
            if ProcessInfo.processInfo.arguments.contains("-sampleRounds") { matchmaker.showSampleRounds() }
        }
        .onDisappear { matchmaker.stopListing() }
    }

    /// Online or nearby: two choices under the title.
    private var tabs: some View {
        HStack(spacing: Theme.s(10)) {
            tabButton(L("Online"), icon: "globe", .online)
            tabButton(L("Nearby"), icon: "wifi", .nearby)
        }
    }

    private func tabButton(_ title: String, icon: String, _ value: Tab) -> some View {
        let selected = tab == value
        return Button {
            if tab != value { code = ""; tab = value }
        } label: {
            HStack(spacing: Theme.s(8)) {
                Image(systemName: icon)
                Text(title).textCase(.uppercase)
            }
            .font(Theme.pixel(12))
            .foregroundStyle(selected ? Theme.green : Theme.text)
            .padding(.horizontal, Theme.s(16)).padding(.vertical, Theme.s(7))
            .background(Capsule().fill(selected ? Theme.green.opacity(0.2) : Color.clear))
            .overlay(Capsule().stroke(selected ? Theme.green : Theme.dimGreen.opacity(0.6), lineWidth: Theme.s(1.5)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var nearbyPanels: some View {
        // Landscape: the three ways side by side. Portrait (iPad): quick game and opening side by side,
        // joining below them with the rest of the height for the list of open rounds.
        GeometryReader { geo in
            if geo.size.height > geo.size.width {
                VStack(spacing: Theme.s(12)) {
                    HStack(alignment: .top, spacing: Theme.s(12)) {
                        quickPanel
                        openPanel(mapSize: Self.mapSize(for: geo.size))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    joinPanel
                }
            } else {
                HStack(alignment: .top, spacing: Theme.s(12)) {
                    quickPanel
                    openPanel(mapSize: Self.mapSize(for: geo.size))
                    joinPanel
                }
            }
        }
    }

    // Buttons in the tiles keep their full height and font size (one size on the whole page): when a tile
    // is short of room, the other contents give way.
    private var quickPanel: some View {
        panel(L("Quick game for two"), L("Against someone who is searching right now. The map is drawn at random.")) {
            Spacer(minLength: 0)
            Button(L("Find opponent")) { matchmaker.quick(name: name) }
                .buttonStyle(MenuButtonStyle(minWidth: 0, fill: true, shrinks: false))
                .layoutPriority(1)
        }
    }

    /// Map cards a little smaller where the tiles are short (iPhone in landscape), so everything fits.
    static func mapSize(for size: CGSize) -> CGFloat {
        size.height < Theme.s(420) ? Theme.s(52) : Theme.s(64)
    }

    private func openPanel(mapSize: CGFloat) -> some View {
        panel(L("Open a round"), L("2 to 4 players, you choose the map. Free seats can be taken by computers.")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.s(8)) {
                    ForEach(GameMap.all, id: \.id) { map in
                        MapCard(map: map, selected: map.id == mapID, size: mapSize)
                            .onTapGesture { mapID = map.id }
                    }
                }
            }
            Spacer(minLength: 0)
            Button(L("Open")) { matchmaker.host(mapID: mapID, name: name) }
                .buttonStyle(MenuButtonStyle(minWidth: 0, fill: true, shrinks: false))
                .layoutPriority(1)
        }
    }

    private var joinPanel: some View {
        panel(L("Join"), L("Choose a round nearby or enter the code.")) {
            openGames
            // Looks like an input field; a tap opens the entry above the keyboard.
            Button { startCodeEntry() } label: {
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
            Button(L("Join"), action: join)
                .buttonStyle(MenuButtonStyle(minWidth: 0, fill: true, shrinks: false))
                .disabled(code.count != Matchmaker.codeLength)
                .opacity(code.count == Matchmaker.codeLength ? 1 : 0.4)
                .layoutPriority(1)
        }
    }

    /// Entering the code: field and buttons at the top, the keyboard below. "Cancel", a tap beside the
    /// panel or the return key without a complete code close it again.
    private var codeEntry: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.75).ignoresSafeArea()
                .onTapGesture { endCodeEntry() }
            VStack(spacing: Theme.s(10)) {
                Text(tab == .online ? L("Join with a Game Center code") : L("Join with a code"))
                    .font(Theme.pixel(12)).foregroundStyle(Theme.green)
                HStack(spacing: Theme.s(12)) {
                    TextField(text: $code, prompt: Text(verbatim: "CODE").foregroundStyle(.gray)) { EmptyView() }
                        .font(Theme.pixel(18))
                        .foregroundStyle(Theme.green)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($codeFocused)
                        .submitLabel(.join)
                        .onSubmit { codeComplete ? join() : endCodeEntry() }
                        .frame(width: Theme.s(170))
                        .padding(.vertical, Theme.s(9))
                        .background(RoundedRectangle(cornerRadius: Theme.s(6)).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: Theme.s(6)).stroke(Theme.green, lineWidth: Theme.s(1)))
                        .onChange(of: code) { _, new in
                            let normalized = tab == .online ? GameCenter.normalizePartyCode(new) : Matchmaker.normalize(new)
                            if normalized != new { code = normalized }
                        }
                    Button(L("Join"), action: join)
                        .buttonStyle(MenuButtonStyle(minWidth: 0, shrinks: false))
                        .disabled(!codeComplete)
                        .opacity(codeComplete ? 1 : 0.4)
                    Button(L("Cancel")) { endCodeEntry() }
                        .buttonStyle(MenuButtonStyle(color: Theme.text, minWidth: 0, shrinks: false))
                }
            }
            .padding(Theme.s(14))
            .background(RoundedRectangle(cornerRadius: Theme.s(10)).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: Theme.s(10)).stroke(Theme.dimGreen, lineWidth: Theme.s(1)))
            .padding(.top, Theme.s(10))
        }
        .onAppear { codeFocused = true }
    }

    private func startCodeEntry() {
        enteringCode = true
    }

    private func endCodeEntry() {
        codeFocused = false
        enteringCode = false
    }

    /// The open rounds nearby; a tap joins. The list takes the free room of the tile and scrolls when it
    /// is longer; rounds that can be joined come first.
    private var openGames: some View {
        Group {
            if matchmaker.openGames.isEmpty {
                Text(L("No open round nearby yet.")).font(Theme.mono(14)).foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(spacing: Theme.s(6)) {
                        ForEach(Self.ordered(matchmaker.openGames)) { game in
                            Button { joinListed(game) } label: { openGameRow(game) }
                                .buttonStyle(.plain)
                                .disabled(!game.fits || game.taken >= game.seats)
                        }
                    }
                    .padding(.trailing, Theme.s(8))     // room for the scroll bar
                }
                .scrollIndicators(.visible)
                .scrollIndicatorsFlash(onAppear: true)
                .scrollIndicatorsFlash(trigger: matchmaker.openGames.count)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Free rounds first, then full ones, then those of another version; each by host name.
    static func ordered(_ games: [OpenGame]) -> [OpenGame] {
        func rank(_ game: OpenGame) -> Int { !game.fits ? 2 : (game.taken >= game.seats ? 1 : 0) }
        return games.sorted { (rank($0), $0.hostName, $0.code) < (rank($1), $1.hostName, $1.code) }
    }

    private func openGameRow(_ game: OpenGame) -> some View {
        let full = game.taken >= game.seats
        let host = game.hostName.isEmpty ? game.code : game.hostName
        return HStack(spacing: Theme.s(8)) {
            Text(verbatim: host).foregroundStyle(game.fits && !full ? Theme.green : .gray).lineLimit(1)
            Spacer(minLength: Theme.s(4))
            if !game.fits {
                Text(L("other version")).foregroundStyle(Theme.warning)
            } else {
                Text(GameMap.named(game.mapID).map { L(key: $0.name) } ?? "").foregroundStyle(Theme.text).lineLimit(1)
                Text(verbatim: "\(game.taken)/\(game.seats)").foregroundStyle(full ? .gray : Theme.text)
            }
        }
        .font(Theme.mono(14))
        .padding(.horizontal, Theme.s(10))
        .padding(.vertical, Theme.s(6))
        .background(RoundedRectangle(cornerRadius: Theme.s(6)).stroke(Theme.dimGreen.opacity(0.6), lineWidth: Theme.s(1)))
        .contentShape(Rectangle())
    }

    private var codeComplete: Bool {
        tab == .online ? GameCenter.isValidPartyCode(code) : code.count == Matchmaker.codeLength
    }

    private func join() {
        guard codeComplete else { return }
        endCodeEntry()
        if tab == .online {
            GameCenter.shared.joinPartyCode(code)
        } else {
            matchmaker.join(code: code, name: name)
        }
    }

    private func joinListed(_ game: OpenGame) {
        endCodeEntry()
        matchmaker.join(code: game.code, name: name)
    }

    private func panel<Content: View>(_ title: String, _ text: String, @ViewBuilder content: () -> Content) -> some View {
        MultiplayerPanel(title, text, content: content)
    }

    // MARK: Search and lobby

    @ViewBuilder private var statusOverlay: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.s(14)) {
                    switch matchmaker.state {
                    case .idle:
                        EmptyView()
                    case .searchingQuick:
                        ProgressView().tint(Theme.green)
                        Text(L("Looking for an opponent …")).font(Theme.pixel(15)).foregroundStyle(Theme.green)
                    case let .joining(code):
                        ProgressView().tint(Theme.green)
                        Text(L("Looking for game \(code) …")).font(Theme.pixel(15)).foregroundStyle(Theme.green)
                    case let .searchingOnline(kind):
                        onlineSearch(kind)
                    case .connecting:
                        ProgressView().tint(Theme.green)
                        Text(L("Connecting …")).font(Theme.pixel(15)).foregroundStyle(Theme.green)
                    case .lobby:
                        if let lobby = matchmaker.lobby { lobbyView(lobby) }
                    case let .failed(message):
                        Text(L("That didn't work")).font(Theme.pixel(15)).foregroundStyle(Theme.warning)
                        Text(message).font(Theme.mono(14)).foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center).frame(maxWidth: Theme.s(440))
                    }
                    if let notice = matchmaker.versionNotice, !isFailed {
                        Text(notice).font(Theme.mono(14)).foregroundStyle(Theme.warning)
                            .multilineTextAlignment(.center).frame(maxWidth: Theme.s(440))
                    }
                    if !matchmaker.detail.isEmpty, matchmaker.state != .lobby {
                        Text(matchmaker.detail).font(Theme.mono(11)).foregroundStyle(.gray)
                            .multilineTextAlignment(.center).frame(maxWidth: Theme.s(440))
                    }
                    buttons
                        .padding(.top, Theme.s(6))
                }
                .padding(Theme.s(28))
                .background(RoundedRectangle(cornerRadius: Theme.s(12)).fill(Color.black.opacity(0.9)))
                .overlay(RoundedRectangle(cornerRadius: Theme.s(12)).stroke(Theme.dimGreen, lineWidth: Theme.s(1)))
                .padding(Theme.s(12))
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center)
        }
    }

    /// Game Center looks for players. The creator of a code sees the code to pass on.
    @ViewBuilder private func onlineSearch(_ kind: OnlineKind) -> some View {
        if let code = kind.partyCode, kind.opensRound {
            Text(L("Your code")).font(Theme.mono(14)).foregroundStyle(Theme.text)
            partyCodeText(code)
            Text(L("Send it to the others; they enter it under „Online“ › „Share a code“."))
                .font(Theme.mono(14)).foregroundStyle(Theme.text)
                .multilineTextAlignment(.center).frame(maxWidth: Theme.s(440))
            HStack(spacing: Theme.s(8)) {
                ProgressView().tint(Theme.green)
                Text(L("Waiting for players …")).font(Theme.mono(14)).foregroundStyle(Theme.text)
            }
        } else if let code = kind.partyCode {
            ProgressView().tint(Theme.green)
            Text(L("Looking for round \(code) …")).font(Theme.pixel(15)).foregroundStyle(Theme.green)
        } else {
            ProgressView().tint(Theme.green)
            Text(L("Game Center is looking for players …")).font(Theme.pixel(15)).foregroundStyle(Theme.green)
                .multilineTextAlignment(.center)
        }
    }

    private func partyCodeText(_ code: String) -> some View {
        HStack(spacing: Theme.s(10)) {
            Text(verbatim: code).font(Theme.pixel(28)).foregroundStyle(Theme.green).kerning(3)
                .textSelection(.enabled)
            ShareLink(item: code) { Image(systemName: "square.and.arrow.up").font(Theme.mono(18)) }
                .tint(Theme.green)
                .accessibilityLabel(L("Share code"))
        }
    }

    @ViewBuilder private var buttons: some View {
        if let lobby = matchmaker.lobby, matchmaker.state == .lobby, lobby.isHost {
            HStack(spacing: Theme.s(14)) {
                Button(lobby.online == .random ? L("Start now") : L("Start")) { matchmaker.startRound() }
                    .buttonStyle(MenuButtonStyle(minWidth: 160))
                    .disabled(!lobby.canStart)
                    .opacity(lobby.canStart ? 1 : 0.4)
                Button(L("Cancel")) { matchmaker.cancel() }
                    .buttonStyle(MenuButtonStyle(color: Theme.text, minWidth: 160))
            }
        } else if matchmaker.state == .lobby {
            Button(L("Leave")) { matchmaker.cancel() }
                .buttonStyle(MenuButtonStyle(color: Theme.text, minWidth: 160))
        } else {
            Button(isFailed ? "OK" : L("Cancel")) { matchmaker.cancel() }
                .buttonStyle(MenuButtonStyle(color: Theme.text, minWidth: 160))
        }
    }

    /// The round before the start: code (host) and map on the left, the four seats on the right (so it
    /// also fits an iPhone in landscape). The host gives free seats to computers.
    @ViewBuilder private func lobbyView(_ lobby: Matchmaker.Lobby) -> some View {
        HStack(alignment: .center, spacing: Theme.s(24)) {
            VStack(spacing: Theme.s(10)) {
                lobbyHeading(lobby)
                if lobby.isHost && lobby.online != .random {
                    // The host can still change the map.
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.s(6)) {
                                ForEach(GameMap.all, id: \.id) { map in
                                    MapCard(map: map, selected: map.id == lobby.mapID, size: Theme.s(52))
                                        .id(map.id)
                                        .onTapGesture { matchmaker.setMap(map.id) }
                                }
                            }
                        }
                        .onAppear { proxy.scrollTo(lobby.mapID, anchor: .center) }
                    }
                } else if let map = GameMap.named(lobby.mapID) {
                    MapCard(map: map, selected: false, size: Theme.s(64))
                }
            }
            .frame(width: Theme.s(220))
            VStack(spacing: Theme.s(8)) {
                ForEach(lobby.seats.indices, id: \.self) { seat in
                    seatRow(lobby, seat: seat)
                }
                if !lobby.isHost {
                    HStack(spacing: Theme.s(8)) {
                        ProgressView().tint(Theme.green)
                        Text(L("Waiting for \(seatName(lobby.seats[0], seat: 0)) to start …"))
                            .font(Theme.mono(14)).foregroundStyle(Theme.text)
                    }
                    .padding(.top, Theme.s(4))
                }
            }
            .frame(width: Theme.s(480))
        }
    }

    /// Above the map: what the others need (code) or what happens next.
    @ViewBuilder private func lobbyHeading(_ lobby: Matchmaker.Lobby) -> some View {
        if !lobby.isHost {
            Text(L("Round of \(seatName(lobby.seats[0], seat: 0))")).font(Theme.pixel(14)).foregroundStyle(Theme.green)
                .multilineTextAlignment(.center)
        } else if let online = lobby.online {
            if let code = online.partyCode {
                Text(L("Your code")).font(Theme.mono(14)).foregroundStyle(Theme.text)
                partyCodeText(code)
                Text(L("More players can still join with it."))
                    .font(Theme.mono(14)).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            } else if online == .random, let at = lobby.startsAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(at.timeIntervalSince(context.date).rounded(.up)))
                    Text(L("Game Center is looking for more players. The round starts in \(left) s; free seats are taken by computers."))
                        .font(Theme.mono(14)).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(L("Your friends are here. Give free seats to computers if you like, then start."))
                    .font(Theme.mono(14)).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(L("Your code")).font(Theme.mono(14)).foregroundStyle(Theme.text)
            Text(lobby.code).font(Theme.pixel(32)).foregroundStyle(Theme.green).kerning(4)
                .textSelection(.enabled)
            Text(L("The others join with this code or choose your round from the list."))
                .font(Theme.mono(14)).foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func seatRow(_ lobby: Matchmaker.Lobby, seat: Int) -> some View {
        HStack(spacing: Theme.s(10)) {
            Text(verbatim: "\(seat + 1)").foregroundStyle(.gray).frame(width: Theme.s(16))
            switch lobby.seats[seat] {
            case .human:
                Text(seatName(lobby.seats[seat], seat: seat) + (seat == lobby.you ? " (" + L("you") + ")" : ""))
                    .foregroundStyle(Theme.green)
                    .lineLimit(1)
                Spacer(minLength: Theme.s(4))
            case let .computer(level):
                if lobby.isHost {
                    Text(L("Computer")).foregroundStyle(Theme.gold)
                } else {
                    Text(L("Computer · \(level.label)")).foregroundStyle(Theme.gold)
                }
                Spacer(minLength: Theme.s(4))
            case .open:
                Text(L("free")).foregroundStyle(.gray)
                Spacer(minLength: Theme.s(4))
            }
            if lobby.isHost, seat > 0, !isHuman(lobby.seats[seat]), lobby.online != .random {
                seatChoices(lobby, seat: seat)
            }
        }
        .font(Theme.mono(14))
        .padding(.horizontal, Theme.s(10))
        .frame(minHeight: Theme.s(34))
        .background(RoundedRectangle(cornerRadius: Theme.s(6)).fill(Theme.panel))
    }

    /// Free seat or computer of a level: one tap chooses.
    private func seatChoices(_ lobby: Matchmaker.Lobby, seat: Int) -> some View {
        let current: Bot.Level? = if case let .computer(level) = lobby.seats[seat] { level } else { nil }
        let choices: [Bot.Level?] = [nil] + Bot.Level.allCases.map(Optional.some)
        return HStack(spacing: Theme.s(6)) {
            ForEach(choices.indices, id: \.self) { i in
                let level = choices[i]
                let selected = level == current
                Button { matchmaker.setComputer(seat: seat, level: level) } label: {
                    Text(level?.label ?? L("free"))
                        .foregroundStyle(selected ? Theme.green : Theme.text)
                        .padding(.horizontal, Theme.s(8)).padding(.vertical, Theme.s(3))
                        .background(Capsule().fill(selected ? Theme.green.opacity(0.2) : Color.clear))
                        .overlay(Capsule().stroke(selected ? Theme.green : Theme.dimGreen.opacity(0.6), lineWidth: Theme.s(1)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func isHuman(_ seat: Seat) -> Bool {
        if case .human = seat { true } else { false }
    }

    private func seatName(_ seat: Seat, seat index: Int) -> String {
        guard case let .human(name) = seat else { return "" }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? L("Player \(index + 1)") : trimmed
    }

    private var isFailed: Bool {
        if case .failed = matchmaker.state { return true }
        return false
    }
}
