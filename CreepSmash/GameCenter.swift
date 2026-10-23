import GameKit
import SwiftUI
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
    /// The player's Game Center name while signed in; it is then the player's name everywhere in the app.
    var playerName: String? {
        isAuthenticated ? GKLocalPlayer.local.displayName : nil
    }
    /// Progress of every app achievement as Game Center knows it (all devices of the player), by app
    /// achievement id; the records show the larger of this and the device's own value.
    private(set) var achievementValues: [String: Int] = [:]
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
                    let record = ProgressStore.shared.record
                    self.submitBestTimes(record)
                    self.reportAchievements(record)
                    self.loadAchievementValues()
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
                GKLeaderboard.submitScore(summary.seconds, context: Self.context(mapID: summary.mapID, lives: summary.livesLeft),
                                          player: GKLocalPlayer.local, leaderboardIDs: [board]) { _ in }
            }
        }
        reportAchievements(record)
    }

    /// The device's best times to Game Center (once signed in: also those from before Game Center).
    /// Game Center keeps the best score per player, so sending them again does no harm.
    func submitBestTimes(_ record: PlayerRecord) {
        guard isAuthenticated else { return }
        for level in Bot.Level.allCases {
            for opponents in 1...3 {
                guard let best = record.leaderboard[PlayerRecord.leaderboardKey(level, opponents: opponents)]?.first else { continue }
                GKLeaderboard.submitScore(best.seconds, context: Self.context(mapID: best.mapID, lives: best.livesLeft),
                                          player: GKLocalPlayer.local,
                                          leaderboardIDs: [Self.leaderboardID(level, opponents: opponents)]) { _ in }
            }
        }
    }

    /// Map and lives left travel with a score as its context: 1 + map index × 100 + lives (0 = unknown).
    static func context(mapID: String, lives: Int) -> Int {
        guard let index = GameMap.all.firstIndex(where: { $0.id == mapID }) else { return 0 }
        return 1 + index * 100 + max(0, min(99, lives))
    }

    static func mapAndLives(context: Int) -> (mapID: String, lives: Int)? {
        guard context > 0 else { return nil }
        let index = (context - 1) / 100
        guard GameMap.all.indices.contains(index) else { return nil }
        return (GameMap.all[index].id, (context - 1) % 100)
    }

    /// One page of a leaderboard as the records show it.
    struct BoardPage {
        struct Row: Identifiable {
            let rank: Int
            let entry: LeaderboardEntry
            let isMe: Bool
            var id: Int { rank }
        }
        var rows: [Row]
        var mine: Row?
        var total: Int
    }

    enum BoardScope: Hashable { case worldwide, friends }

    /// The best ten of a leaderboard (worldwide or among friends) and the player's own place.
    func loadBoard(level: Bot.Level, opponents: Int, scope: BoardScope) async -> BoardPage? {
        guard isAuthenticated,
              let board = try? await GKLeaderboard.loadLeaderboards(IDs: [Self.leaderboardID(level, opponents: opponents)]).first,
              let (mine, entries, total) = try? await board.loadEntries(for: scope == .friends ? .friendsOnly : .global,
                                                                       timeScope: .allTime, range: NSRange(location: 1, length: 10))
        else { return nil }
        let me = GKLocalPlayer.local.gamePlayerID
        func row(_ e: GKLeaderboard.Entry) -> BoardPage.Row {
            let extra = Self.mapAndLives(context: e.context)
            return .init(rank: e.rank,
                         entry: LeaderboardEntry(name: e.player.displayName, mapID: extra?.mapID ?? "",
                                                 durationTicks: e.score * 1000 / Rules.standard.tickMilliseconds,
                                                 livesLeft: extra?.lives ?? -1, date: e.date),
                         isMe: e.player.gamePlayerID == me)
        }
        return BoardPage(rows: entries.map(row), mine: mine.map(row), total: total)
    }

    /// Reads the player's achievement progress from Game Center and turns it back into the app's values.
    func loadAchievementValues() {
        guard isAuthenticated else { return }
        GKAchievement.loadAchievements { [weak self] loaded, _ in
            let percent = Dictionary((loaded ?? []).map { ($0.identifier, $0.percentComplete) }, uniquingKeysWith: max)
            Task { @MainActor in
                var values: [String: Int] = [:]
                for achievement in Achievement.all {
                    for (index, threshold) in achievement.tiers.enumerated() {
                        guard let p = percent[Self.achievementID(achievement.id, tier: index + 1)] else { continue }
                        values[achievement.id] = max(values[achievement.id] ?? 0, Int((Double(threshold) * p / 100).rounded(.down)))
                    }
                }
                self?.achievementValues = values
            }
        }
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
        GKAchievement.report(achievements) { [weak self] _ in
            Task { @MainActor in self?.loadAchievementValues() }
        }
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

/// The player's name: the Game Center name while signed in, otherwise the one typed into the app.
enum PlayerName {
    @MainActor static func current(typed: String) -> String {
        GameCenter.shared.playerName ?? typed.trimmingCharacters(in: .whitespaces)
    }
}

/// Where the player's name is set: a text field, or – signed in to Game Center – that name, not editable.
struct PlayerNameField: View {
    @Binding var text: String
    var width: CGFloat? = nil

    var body: some View {
        if let name = GameCenter.shared.playerName {
            HStack(spacing: Theme.s(6)) {
                Image(systemName: "gamecontroller.fill").foregroundStyle(Theme.green)
                Text(verbatim: name).foregroundStyle(Theme.text).lineLimit(1)
            }
            .font(Theme.mono(14))
            .frame(width: width, alignment: .leading)
            .accessibilityLabel(L("Name from Game Center: \(name)"))
        } else {
            TextField(L("Your name"), text: $text)
                .textFieldStyle(.roundedBorder)
                .font(Theme.mono(14))
                .frame(width: width)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
        }
    }
}
