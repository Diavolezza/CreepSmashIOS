import GameKit
import UIKit
import CreepSmashCore

/// Game Center: sign-in, leaderboards, achievements and online games with players anywhere.
///
/// Switched off until the app has the Game Center capability (it needs a paid developer account): then the
/// Info.plist key `CSGameCenter` is set to YES. The launch argument "-gameCenter" switches it on for tests.
/// Identifiers: `docs/appstore/game-center.md`.
@MainActor
@Observable
final class GameCenter: NSObject {
    static let shared = GameCenter()

    static let isEnabled = (Bundle.main.object(forInfoDictionaryKey: "CSGameCenter") as? Bool ?? false)
        || ProcessInfo.processInfo.arguments.contains("-gameCenter")

    /// Signed in to Game Center: online games, leaderboards and achievements are available.
    private(set) var isAuthenticated = false
    /// Called with a found match (from the matchmaker screen or an accepted invitation).
    @ObservationIgnored var onMatch: ((GKMatch) -> Void)?

    // MARK: Sign-in

    /// Signs in at the start of the app; Game Center shows its own screen if needed.
    func authenticate() {
        guard Self.isEnabled else { return }
        GKLocalPlayer.local.authenticateHandler = { [weak self] controller, _ in
            Task { @MainActor in
                guard let self else { return }
                if let controller {
                    Self.present(controller)
                    return
                }
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                if self.isAuthenticated {
                    GKLocalPlayer.local.register(self)
                    self.reportAchievements(ProgressStore.shared.record)
                }
            }
        }
    }

    // MARK: Leaderboards and achievements

    /// Leaderboard of the fastest wins against the computer, as on the device (time in seconds, lower is better).
    static func leaderboardID(_ level: Bot.Level, opponents: Int) -> String {
        "cs.fastest.\(level.rawValue).\(opponents)"
    }

    /// One Game Center achievement per tier of an achievement of the app.
    static func achievementID(_ id: String, tier: Int) -> String {
        "cs.\(id).\(tier)"
    }

    /// After every recorded game: the win time to its leaderboard, the progress of all achievements.
    func report(_ summary: GameSummary, record: PlayerRecord) {
        guard isAuthenticated else { return }
        if summary.won {
            let board: String? = switch summary.mode {
            case let .computer(level): Self.leaderboardID(level, opponents: 1)
            case let .computerGroup(level, opponents): Self.leaderboardID(level, opponents: opponents)
            case .online: nil
            }
            if let board {
                GKLeaderboard.submitScore(summary.seconds, context: 0, player: GKLocalPlayer.local,
                                          leaderboardIDs: [board]) { _ in }
            }
        }
        reportAchievements(record)
    }

    /// Reports the progress of every tier (Game Center keeps the highest value reported, so this can be repeated).
    func reportAchievements(_ record: PlayerRecord) {
        guard isAuthenticated else { return }
        let achievements = Achievement.all.flatMap { achievement in
            achievement.tiers.enumerated().compactMap { index, threshold -> GKAchievement? in
                let progress = achievement.progress(in: record)
                guard progress > 0 else { return nil }
                let gk = GKAchievement(identifier: Self.achievementID(achievement.id, tier: index + 1))
                gk.percentComplete = min(100, Double(progress) * 100 / Double(threshold))
                gk.showsCompletionBanner = true
                return gk
            }
        }
        guard !achievements.isEmpty else { return }
        GKAchievement.report(achievements) { _ in }
    }

    /// Game Center's own screen with the leaderboards and achievements.
    func showDashboard() {
        guard isAuthenticated else { return }
        let controller = GKGameCenterViewController(state: .dashboard)
        controller.gameCenterDelegate = self
        Self.present(controller)
    }

    // MARK: Online games

    /// Game Center's matchmaker screen: invite friends or play with anyone looking for 2 to 4 players.
    func findMatch() {
        guard isAuthenticated else { return }
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 4
        request.defaultNumberOfPlayers = 2
        // Only devices with the same protocol version are matched (as nearby).
        request.playerGroup = NetMessage.protocolVersion
        guard let controller = GKMatchmakerViewController(matchRequest: request) else { return }
        controller.matchmakerDelegate = self
        Self.present(controller)
    }

    // MARK: Presenting

    private static func present(_ controller: UIViewController) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        guard var top = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        top.present(controller, animated: true)
    }
}

extension GameCenter: GKMatchmakerViewControllerDelegate, GKLocalPlayerListener, GKGameCenterControllerDelegate {
    nonisolated func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        Task { @MainActor in viewController.dismiss(animated: true) }
    }

    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        Task { @MainActor in viewController.dismiss(animated: true) }
    }

    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        Task { @MainActor in
            viewController.dismiss(animated: true)
            self.onMatch?(match)
        }
    }

    /// An invitation was accepted (in Game Center or a message): the matchmaker screen of that round.
    nonisolated func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        Task { @MainActor in
            guard let controller = GKMatchmakerViewController(invite: invite) else { return }
            controller.matchmakerDelegate = self
            Self.present(controller)
        }
    }

    nonisolated func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        Task { @MainActor in gameCenterViewController.dismiss(animated: true) }
    }
}

/// One online round through Game Center: waits until all players are connected, then turns the match into a
/// `MeshLink` (the lobby, the game and a handover run over it as nearby).
@MainActor
final class GameCenterSession: NSObject, GKMatchDelegate {
    let match: GKMatch
    private(set) var link: MeshLink?
    /// All players are connected: set up the lobby on this link (before further messages are delivered).
    var onReady: ((MeshLink) -> Void)?
    /// A player dropped out before the round started, or Game Center failed.
    var onFailure: ((String) -> Void)?
    /// Messages that arrived before the link was ready.
    private var early: [(Data, MeshLink.Peer)] = []

    init(match: GKMatch) {
        self.match = match
        super.init()
        match.delegate = self
    }

    /// Call once the callbacks are set.
    func begin() { checkReady() }

    private func checkReady() {
        guard link == nil, match.expectedPlayerCount == 0 else { return }
        let match = self.match
        let link = MeshLink(me: GKLocalPlayer.local.gamePlayerID, peers: match.players.map(\.gamePlayerID)) { data, peers in
            let players = match.players.filter { peers.contains($0.gamePlayerID) }
            try? match.send(data, to: players, dataMode: .reliable)
        }
        self.link = link
        onReady?(link)
        for (data, peer) in early { link.received(data, from: peer) }
        early = []
    }

    func disconnect() {
        match.delegate = nil
        match.disconnect()
    }

    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        let peer = player.gamePlayerID
        Task { @MainActor in
            if let link = self.link { link.received(data, from: peer) } else { self.early.append((data, peer)) }
        }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        let peer = player.gamePlayerID
        Task { @MainActor in
            switch state {
            case .connected:
                self.checkReady()
            case .disconnected:
                if let link = self.link { link.disconnected(peer) } else { self.onFailure?(L("Connection lost")) }
            default:
                break
            }
        }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: Error?) {
        Task { @MainActor in self.onFailure?(L("Connection lost")) }
    }
}
