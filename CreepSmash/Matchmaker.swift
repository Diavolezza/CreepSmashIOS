import Foundation
import CreepSmashCore

/// Finds an opponent – regardless of which network they are found on. Currently nearby
/// (Bonjour); Game Center will be added as another source. Whoever connects first is taken.
@MainActor
@Observable
final class Matchmaker {
    enum State: Equatable {
        case idle
        /// Quick game: looks for someone who is also searching.
        case searchingQuick
        /// Game hosted, waiting for someone with this code.
        case hosting(code: String)
        /// Looking for the game with this code.
        case joining(code: String)
        /// Connected, settings are being negotiated.
        case connecting
        case failed(String)
    }

    private(set) var state: State = .idle
    /// Technical detail of the search, shown in small print (helps when nothing is found).
    private(set) var detail = ""
    /// A nearby device runs another version of the app, so the two cannot play together (shown during the search).
    private(set) var versionNotice: String?
    /// Called with the ready game.
    var onMatch: ((NetworkMatch) -> Void)?

    @ObservationIgnored private var nearby: NearbyFinder?
    @ObservationIgnored private var hostMapID = ""
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

    func quick(name: String) {
        start(name: name)
        hostMapID = GameMap.all.randomElement()!.id
        state = .searchingQuick
        nearby?.quick()
    }

    func host(mapID: String, name: String, code: String = Matchmaker.makeCode()) {
        start(name: name)
        hostMapID = mapID
        state = .hosting(code: code)
        nearby?.host(code: code)
    }

    func join(code: String, name: String) {
        let code = Self.normalize(code)
        guard code.count == Self.codeLength else {
            state = .failed(L("The code has \(Self.codeLength) characters."))
            return
        }
        start(name: name)
        state = .joining(code: code)
        nearby?.join(code: code)
    }

    func cancel() {
        nearby?.stop()
        nearby = nil
        state = .idle
        detail = ""
        versionNotice = nil
    }

    private func start(name: String) {
        cancel()
        playerName = name
        let finder = NearbyFinder()
        finder.onConnected = { [weak self] transport, role in
            MainActor.assumeIsolated { self?.connected(transport, role: role) }
        }
        finder.onError = { [weak self] message in
            MainActor.assumeIsolated { self?.state = .failed(message) }
        }
        finder.onStatus = { [weak self] status in
            MainActor.assumeIsolated { self?.detail = status }
        }
        finder.onOtherVersions = { [weak self] versions in
            MainActor.assumeIsolated { self?.otherVersionsFound(versions) }
        }
        nearby = finder
    }

    private func otherVersionsFound(_ versions: Set<Int>) {
        guard let other = versions.max() else { versionNotice = nil; return }
        let newer = other > NetMessage.protocolVersion
        if case .joining = state {
            // The game with this code exists, but cannot be joined: stop with a clear message.
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
        nearby = nil
        state = .connecting
        let completion: (Handshake.Result) -> Void = { [weak self] result in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch result {
                case let .ready(match):
                    self.state = .idle
                    self.onMatch?(match)
                case let .failed(failure):
                    self.state = .failed(failure.message)
                }
            }
        }
        switch role {
        case .host:
            Handshake.host(transport: transport, mapID: hostMapID, name: playerName, completion: completion)
        case .guest:
            Handshake.join(transport: transport, name: playerName, completion: completion)
        }
    }
}
