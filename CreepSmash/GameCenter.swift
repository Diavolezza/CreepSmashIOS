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
    /// A game against the computer asked for from outside (an activity in the Games app or a challenge):
    /// the menu opens the setup page with it and then sets it back to nil.
    var requestedSetup: RequestedSetup?
    struct RequestedSetup: Equatable {
        var level: Bot.Level?
        var opponents: Int?
    }
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
                    if #available(iOS 26.0, *) { GKLocalPlayer.local.register(GameActivityListener.shared) }
                    let record = ProgressStore.shared.record
                    self.submitBestTimes(record)
                    // Catching up with what was reached before signing in: no banner for each of them.
                    self.reportAchievements(record, banners: false)
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
                // Sent now: not again from submitBestTimes at the next sign-in.
                var sent = UserDefaults.standard.dictionary(forKey: "gameCenterSubmittedBest") as? [String: Int] ?? [:]
                sent[board] = min(sent[board] ?? .max, summary.seconds)
                UserDefaults.standard.set(sent, forKey: "gameCenterSubmittedBest")
            }
        }
        reportAchievements(record)
    }

    /// The device's best times to Game Center (once signed in: also those from before Game Center).
    /// Each one only once: a score sent again at sign-in would count in a running challenge as a new try.
    func submitBestTimes(_ record: PlayerRecord) {
        guard isAuthenticated else { return }
        let key = "gameCenterSubmittedBest"
        var sent = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        for level in Bot.Level.allCases {
            for opponents in 1...3 {
                let board = Self.leaderboardID(level, opponents: opponents)
                guard let best = record.leaderboard[PlayerRecord.leaderboardKey(level, opponents: opponents)]?.first,
                      best.seconds < sent[board] ?? .max else { continue }
                GKLeaderboard.submitScore(best.seconds, context: Self.context(mapID: best.mapID, lives: best.livesLeft),
                                          player: GKLocalPlayer.local, leaderboardIDs: [board]) { _ in }
                sent[board] = best.seconds
            }
        }
        UserDefaults.standard.set(sent, forKey: key)
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
    /// Why the last `loadBoard` brought nothing (shown instead of the leaderboard).
    enum BoardProblem { case unreachable, missing }
    private(set) var boardProblem: BoardProblem?

    func loadBoard(level: Bot.Level, opponents: Int, scope: BoardScope) async -> BoardPage? {
        guard isAuthenticated else { return nil }
        let boards: [GKLeaderboard]
        do {
            boards = try await GKLeaderboard.loadLeaderboards(IDs: [Self.leaderboardID(level, opponents: opponents)])
        } catch {
            boardProblem = .unreachable
            return nil
        }
        // No error, but no leaderboard: Game Center does not know it (not live yet).
        guard let board = boards.first else {
            boardProblem = .missing
            return nil
        }
        guard let (mine, entries, total) = try? await board.loadEntries(for: scope == .friends ? .friendsOnly : .global,
                                                                       timeScope: .allTime, range: NSRange(location: 1, length: 10))
        else {
            boardProblem = .unreachable
            return nil
        }
        boardProblem = nil
        let me = GKLocalPlayer.local.gamePlayerID
        func row(_ e: GKLeaderboard.Entry) -> BoardPage.Row {
            let extra = Self.mapAndLives(context: e.context)
            let player = Self.object(e, "player") as? GKPlayer
            return .init(rank: e.rank,
                         entry: LeaderboardEntry(name: player.flatMap { Self.object($0, "displayName") as? String } ?? "?",
                                                 mapID: extra?.mapID ?? "",
                                                 durationTicks: min(max(e.score, 0), 1_000_000) * 1000 / Rules.standard.tickMilliseconds,
                                                 livesLeft: extra?.lives ?? -1,
                                                 date: Self.object(e, "date") as? Date ?? .distantPast),
                         isMe: player.flatMap { Self.object($0, "gamePlayerID") as? String } == me)
        }
        return BoardPage(rows: entries.map(row), mine: mine.map(row), total: total)
    }

    /// An object property of a Game Center object, read through the Objective-C getter. Game Center leaves
    /// some of them out (a score's date with leaderboards that are not live yet); the Swift properties are
    /// not optional and crash on a missing value, and key-value coding is not supported for them either.
    /// nil if the getter does not exist or returns nothing.
    nonisolated static func object(_ object: NSObject, _ getter: String) -> Any? {
        let selector = NSSelectorFromString(getter)
        // GKLeaderboardEntry hands most of its properties on to an internal object (forwardingTarget):
        // the getter is answered there, not by the entry itself.
        let target = object.responds(to: selector) ? object : object.forwardingTarget(for: selector) as? NSObject
        guard let target, target.responds(to: selector) else { return nil }
        return target.perform(selector)?.takeUnretainedValue()
    }

    /// Reads the player's achievement progress from Game Center and turns it back into the app's values.
    func loadAchievementValues() {
        guard isAuthenticated else { return }
        GKAchievement.loadAchievements { [weak self] loaded, _ in
            // Values from Game Center: only finite percentages, kept within 0…100.
            let percent = Dictionary((loaded ?? []).compactMap { a -> (String, Double)? in
                guard let id = GameCenter.object(a, "identifier") as? String, a.percentComplete.isFinite else { return nil }
                return (id, min(max(a.percentComplete, 0), 100))
            }, uniquingKeysWith: max)
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
    /// `banners`: Game Center announces a tier completed by this report at the top of the screen – after a game,
    /// not when catching up at sign-in (that showed one banner after the other over the menu).
    func reportAchievements(_ record: PlayerRecord, banners: Bool = true) {
        guard isAuthenticated else { return }
        let achievements = Achievement.all.flatMap { achievement in
            achievement.tiers.enumerated().compactMap { index, threshold -> GKAchievement? in
                let progress = achievement.progress(in: record)
                guard progress > 0 else { return nil }
                let gk = GKAchievement(identifier: Self.achievementID(achievement.id, tier: index + 1))
                gk.percentComplete = min(100, Double(progress) * 100 / Double(threshold))
                gk.showsCompletionBanner = banners
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
        guard let peer = GameCenter.object(player, "gamePlayerID") as? String else { return }
        Task { @MainActor in
            if let link = self.link { link.received(data, from: peer) } else { self.early.append((data, peer)) }
        }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        guard let peer = GameCenter.object(player, "gamePlayerID") as? String else { return }
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

/// An activity from the Games app or from a challenge: a game against the computer. Its leaderboard brings the
/// difficulty and the number of opponents as properties ("level", "opponents"); the setup page opens with them,
/// so one tap starts the game. A listener of its own: activities exist from iOS 26 on, the app from iOS 17.
@available(iOS 26.0, *)
final class GameActivityListener: NSObject, GKLocalPlayerListener {
    static let shared = GameActivityListener()

    func player(_ player: GKPlayer, wantsToPlay activity: GKGameActivity) async -> Bool {
        let properties = activity.properties
        let level = properties["level"].flatMap(Bot.Level.init(rawValue:))
        let opponents = properties["opponents"].flatMap(Int.init).map { min(3, max(1, $0)) }
        await MainActor.run { GameCenter.shared.requestedSetup = .init(level: level, opponents: opponents) }
        return true
    }
}
