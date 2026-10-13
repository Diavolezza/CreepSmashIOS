import Foundation
import CreepSmashCore

/// Finds other players and runs the lobby – regardless of which network they are found on. Currently
/// nearby (Bonjour); Game Center will be added as another source.
@MainActor
@Observable
final class Matchmaker {
    enum State: Equatable {
        case idle
        /// Quick game: looks for someone who is also searching.
        case searchingQuick
        /// Looking for the round with this code.
        case joining(code: String)
        /// Connected, settings are being negotiated.
        case connecting
        /// In a lobby (own round or as a guest), see `lobby`.
        case lobby
        case failed(String)
    }

    /// The lobby as shown.
    struct Lobby: Equatable {
        var code: String
        var mapID: String
        var seats: [Seat]
        /// Own seat.
        var you: Int
        var isHost: Bool
        var canStart: Bool
    }

    private(set) var state: State = .idle
    private(set) var lobby: Lobby?
    /// Open rounds nearby, while `listGames()` runs.
    private(set) var openGames: [OpenGame] = []
    /// Technical detail of the search, shown in small print (helps when nothing is found).
    private(set) var detail = ""
    /// A nearby device runs another version of the app, so the two cannot play together (shown during the search).
    private(set) var versionNotice: String?
    /// Called with the ready game.
    var onMatch: ((NetworkMatch) -> Void)?
    /// Tests: the host starts by itself as soon as this many people are in the round.
    @ObservationIgnored var autoStartPeople: Int?
    /// Tests: at that start, the free seats get computers of this level.
    @ObservationIgnored var autoStartComputers: Bot.Level?

    @ObservationIgnored private var nearby: NearbyFinder?
    @ObservationIgnored private var lister: NearbyFinder?
    @ObservationIgnored private var hostLobby: HostLobby?
    @ObservationIgnored private var guestLobby: GuestLobby?
    @ObservationIgnored private var code = ""
    @ObservationIgnored private var playerName = ""

    /// Characters that cannot be confused (no 0/O, 1/I).
    nonisolated static let codeAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    nonisolated static let codeLength = 5

    nonisolated static func makeCode() -> String {
        String((0..<codeLength).map { _ in codeAlphabet.randomElement()! })
    }

    nonisolated static func normalize(_ input: String) -> String {
        String(input.uppercased().filter { codeAlphabet.contains($0) }.prefix(codeLength))
    }

    // MARK: Finding

    /// Quick game for two: whoever is also searching; the map is drawn at random.
    func quick(name: String) {
        start(name: name)
        state = .searchingQuick
        nearby?.quick()
    }

    /// Opens a round for two to four players.
    func host(mapID: String, name: String, code: String = Matchmaker.makeCode()) {
        start(name: name)
        self.code = code
        let lobby = HostLobby(mapID: mapID, name: name, code: code)
        lobby.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.hostLobbyChanged() }
        }
        lobby.onStart = { [weak self] match in
            MainActor.assumeIsolated { self?.started(match) }
        }
        hostLobby = lobby
        state = .lobby
        hostLobbyChanged()
        nearby?.host(code: code, info: info(of: lobby))
    }

    /// Joins the round with this code; the lobby is shown until the host starts.
    func join(code: String, name: String) {
        let code = Self.normalize(code)
        guard code.count == Self.codeLength else {
            state = .failed(L("The code has \(Self.codeLength) characters."))
            return
        }
        start(name: name)
        self.code = code
        state = .joining(code: code)
        nearby?.join(code: code)
    }

    func cancel() {
        nearby?.stop()
        nearby = nil
        hostLobby?.close()
        hostLobby = nil
        guestLobby?.leave()
        guestLobby = nil
        lobby = nil
        state = .idle
        detail = ""
        versionNotice = nil
    }

    // MARK: List of open rounds

    /// Lists the open rounds nearby while the multiplayer page is visible.
    func listGames() {
        guard lister == nil else { return }
        let finder = NearbyFinder()
        finder.onGames = { [weak self] games in
            MainActor.assumeIsolated { self?.openGames = games }
        }
        finder.listGames()
        lister = finder
    }

    func stopListing() {
        lister?.stop()
        lister = nil
        openGames = []
    }

    // MARK: Lobby (host)

    /// Gives a free seat to a computer or frees it (nil).
    func setComputer(seat: Int, level: Bot.Level?) {
        hostLobby?.setComputer(seat: seat, level: level)
    }

    func startRound() {
        hostLobby?.start()
    }

    // MARK: - Internal

    private func start(name: String) {
        cancel()
        playerName = name
        let finder = NearbyFinder()
        finder.onConnected = { [weak self] transport, role in
            MainActor.assumeIsolated { self?.connected(transport, role: role) }
        }
        finder.onError = { [weak self] message in
            MainActor.assumeIsolated { self?.failed(message) }
        }
        finder.onStatus = { [weak self] status in
            MainActor.assumeIsolated { self?.detail = status }
        }
        finder.onOtherVersions = { [weak self] versions in
            MainActor.assumeIsolated { self?.otherVersionsFound(versions) }
        }
        nearby = finder
    }

    private func failed(_ message: String) {
        nearby?.stop()
        nearby = nil
        hostLobby?.close()
        hostLobby = nil
        guestLobby?.leave()
        guestLobby = nil
        lobby = nil
        state = .failed(message)
    }

    private func otherVersionsFound(_ versions: Set<Int>) {
        guard let other = versions.max() else { versionNotice = nil; return }
        let newer = other > NetMessage.protocolVersion
        if case .joining = state {
            // The round with this code exists, but cannot be joined: stop with a clear message.
            let message = newer
                ? L("The game with this code was opened with a newer version of CreepSmash. Please update this device.")
                : L("The game with this code was opened with an older version of CreepSmash. Please update the other device.")
            cancel()
            state = .failed(message)
        } else {
            // Quick game: keep looking (another device may fit), but say why this one is not taken.
            versionNotice = newer
                ? L("A device nearby has a newer version of CreepSmash. Please update this device.")
                : L("A device nearby has an older version of CreepSmash. Please update the other device.")
        }
    }

    private func connected(_ transport: Transport, role: NearbyFinder.Role) {
        switch (role, hostLobby) {
        case let (.host, lobby?):
            // Own round: another guest.
            lobby.add(transport)
        case (.host, nil):
            // Quick game: this device became the host; the game starts as soon as the guest has introduced itself.
            nearby = nil
            state = .connecting
            let lobby = HostLobby(mapID: GameMap.all.randomElement()!.id, name: playerName, seats: 2)
            lobby.startsWhenFull = true
            lobby.onStart = { [weak self] match in
                MainActor.assumeIsolated { self?.started(match) }
            }
            hostLobby = lobby
            lobby.add(transport)
        case (.guest, _):
            // Joining a round shows its lobby; a quick game starts at once.
            let showsLobby = { if case .joining = self.state { true } else { false } }()
            nearby = nil
            state = .connecting
            let lobby = GuestLobby(transport: transport, name: playerName)
            lobby.onChange = { [weak self] in
                MainActor.assumeIsolated { if showsLobby { self?.guestLobbyChanged() } }
            }
            lobby.onResult = { [weak self] result in
                MainActor.assumeIsolated {
                    switch result {
                    case let .ready(match): self?.started(match)
                    case let .failed(failure): self?.failed(failure.message)
                    }
                }
            }
            guestLobby = lobby
        }
    }

    private func hostLobbyChanged() {
        guard let hostLobby else { return }
        lobby = Lobby(code: code, mapID: hostLobby.mapID, seats: hostLobby.seats, you: 0, isHost: true,
                      canStart: hostLobby.canStart)
        nearby?.update(info: info(of: hostLobby))
        let people = hostLobby.seats.filter { if case .human = $0 { true } else { false } }.count
        if let wanted = autoStartPeople, people >= wanted {
            autoStartPeople = nil
            if let level = autoStartComputers {
                for seat in hostLobby.seats.indices where hostLobby.seats[seat] == .open {
                    hostLobby.setComputer(seat: seat, level: level)
                }
            }
            hostLobby.start()
        }
    }

    private func guestLobbyChanged() {
        guard let info = guestLobby?.info else { return }
        lobby = Lobby(code: code, mapID: info.mapID, seats: info.seats, you: info.you, isHost: false, canStart: false)
        state = .lobby
    }

    /// Details of the own round for the list on other devices: host name, map, seats taken/total.
    private func info(of lobby: HostLobby) -> [String: String] {
        ["n": playerName, "m": lobby.mapID, "s": "\(lobby.takenSeats)/\(lobby.seats.count)"]
    }

    private func started(_ match: NetworkMatch) {
        nearby?.stop()
        nearby = nil
        hostLobby = nil
        guestLobby = nil
        lobby = nil
        state = .idle
        detail = ""
        versionNotice = nil
        onMatch?(match)
    }
}
