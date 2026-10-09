import SwiftUI
import QuartzCore
import CreepSmashCore

/// Drives a game: on each display refresh it computes as many ticks as are due,
/// collects the events for the effects and prepares the display values.
@MainActor
@Observable
final class GameController {
    enum Selection: Equatable {
        case none
        case placing(TowerKind)
        case tower(id: Int)
    }

    enum Phase: Equatable {
        case countdown(seconds: Int)
        case running
        case finished(rank: Int?)
    }

    /// Values for the header and the control panel. Changes at most once per tick.
    struct HUD: Equatable {
        var tick = 0
        var phase: Phase = .countdown(seconds: 0)
        var credits = 0
        var available = 0
        var income = 0
        var lives = 0
        var secondsToIncome = 0
        /// Remaining share of the time until the next income payment (1 = just paid).
        var incomeFraction = 1.0
        var myName = ""
        var opponentName = ""
        var opponentLives = 0
        var opponentIncome = 0
        /// More than two players: all opponents in ring order, and where the own creeps go.
        var opponents: [OpponentInfo] = []
        var sendMode: SendMode = .next
    }

    /// One opponent for the overview with more than two players.
    struct OpponentInfo: Equatable, Identifiable {
        let id: Int
        var name: String
        var lives: Int
        var income: Int
        var isDead: Bool
        /// Receives the creeps this player sends (send mode "next" or "all").
        var isTarget: Bool
    }

    let match: any Match
    let effects = EffectStore()
    @ObservationIgnored private var link: DisplayLinkProxy?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    /// Time elapsed since the last tick, for interpolating creep movement.
    @ObservationIgnored private(set) var accumulator: Double = 0
    @ObservationIgnored private(set) var previousPositions: [Int: CGPoint] = [:]

    private(set) var hud = HUD()
    var selection: Selection = .none {
        didSet { if case .placing = selection {} else { aimCell = nil } }
    }
    /// While placing a tower: the cell under the finger or pointer (preview with range circle).
    var aimCell: GridPoint?
    var isPaused = false
    /// The pause came from the opponent (online game).
    private(set) var pausedByOpponent = false
    /// Online game has been waiting for the opponent for more than half a second.
    private(set) var isWaitingForOpponent = false
    /// Online game is broken (the devices compute different results).
    private(set) var connectionProblem: String?
    private(set) var toast: Toast? = nil
    @ObservationIgnored private var waitingSince: CFTimeInterval?

    struct Toast: Equatable {
        let id: Int
        let text: String
    }

    /// Plays for the local player (demo mode).
    @ObservationIgnored var autopilot: Bot?

    var game: Game { match.game }
    var network: NetworkMatch? { match as? NetworkMatch }
    var isOnline: Bool { network != nil }
    var me: Int { match.localPlayer }
    /// The next opponent in the ring – with two players simply the opponent.
    var opponent: Int? { game.opponent(of: me) ?? game.players.indices.first { $0 != me } }
    /// More than two players.
    var isGroup: Bool { game.players.count > 2 }
    /// Opponent whose board is shown large next to the own one (iPhone with more than two players):
    /// the one tapped in the overview, otherwise the next one in the ring.
    var viewedOpponent: Int?
    var shownOpponent: Int? { viewedOpponent ?? opponent }
    /// Send mode chosen but not yet executed (commands take effect after the input delay).
    @ObservationIgnored private var requestedSendMode: SendMode?
    var tickDuration: Double { Double(game.rules.tickMilliseconds) / 1000 }
    /// 0...1 between the previous and the current tick.
    var interpolation: Double { min(1, accumulator / tickDuration) }

    /// Statistics of this game for the record; nil for games that do not count (demo with autopilot).
    @ObservationIgnored private var stats: GameStats?
    /// Kind of game for the record (nil: does not count).
    var mode: GameMode? { stats?.mode }
    @ObservationIgnored private var recorded = false
    @ObservationIgnored private let playerName: String
    /// What the finished game brought (new achievements, leaderboard place); set when it ends.
    private(set) var outcome: PlayerRecord.Outcome?
    /// Course and numbers of the finished game, for the evaluation.
    private(set) var summary: GameSummary?

    init(match: any Match, mode: GameMode? = nil) {
        self.match = match
        let name = match.game.players[match.localPlayer].name
        self.playerName = name.isEmpty ? L("You") : name
        if let mode { stats = GameStats(me: match.localPlayer, mode: mode) }
        updateHUD()
        network?.onPeerPause = { [weak self] paused in
            MainActor.assumeIsolated {
                self?.isPaused = paused
                self?.pausedByOpponent = paused
            }
        }
        network?.onStatusChange = { [weak self] status in
            MainActor.assumeIsolated { self?.networkStatusChanged(status) }
        }
    }

    /// Out of a game against the computer: the remaining computers are not played on in the background
    /// (online the game has to go on for the others).
    private var isOutOfLocalGame: Bool {
        network == nil && game.players[me].isDead
    }

    /// Pause on/off; in an online game for both players.
    func setPaused(_ paused: Bool) {
        guard paused != isPaused || pausedByOpponent else { return }
        isPaused = paused
        pausedByOpponent = false
        network?.sendPause(paused)
    }

    /// The game is over for the local player: add it to the record once.
    private func recordIfFinished() {
        guard !recorded, stats != nil else { return }
        let board = game.players[me]
        guard game.isFinished || board.isDead else { return }
        record(won: game.winner == me && !board.isDead)
    }

    private func record(won: Bool) {
        guard !recorded, let stats else { return }
        recorded = true
        let opponentName = isGroup ? game.players.indices.filter { $0 != me }.map(displayName).joined(separator: ", ")
                                   : hud.opponentName
        let summary = stats.summary(game: game, won: won, opponentName: opponentName,
                                    playerNames: game.players.indices.map(displayName))
        self.summary = summary
        outcome = ProgressStore.shared.add(summary, playerName: playerName)
    }

    /// Leave the game. Online this means giving up; the opponent wins.
    func quit() {
        // Giving up a running game counts as a loss.
        if game.isStarted { record(won: false) }
        stop()
        network?.leave()
    }

    private func networkStatusChanged(_ status: NetworkMatch.Status) {
        switch status {
        case .running:
            break
        case .opponentGone:
            isPaused = false
            pausedByOpponent = false
            isWaitingForOpponent = false
            if !game.isFinished || game.winner == me { show(L("Your opponent has left the game")) }
        case let .desynced(tick):
            connectionProblem = L("The two devices compute differently (tick \(tick)). The game cannot continue.")
        }
    }

    // MARK: - Runtime

    func start() {
        guard link == nil else { return }
        lastTimestamp = nil
        link = DisplayLinkProxy { [weak self] timestamp in
            self?.frame(timestamp: timestamp)
        }
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    private func frame(timestamp: CFTimeInterval) {
        defer { lastTimestamp = timestamp }
        guard let last = lastTimestamp, !isPaused, !game.isFinished, !isOutOfLocalGame else { return }
        accumulator += min(timestamp - last, 0.25)
        var steps = 0
        while accumulator >= tickDuration && steps < 5 {
            rememberPositions()
            runAutopilot()
            guard match.advance() else {
                accumulator = 0
                noteWaiting(network?.isWaitingForOpponent == true, now: timestamp)
                break
            }
            noteWaiting(false, now: timestamp)
            handleEvents(game.events, now: timestamp)
            stats?.observe(game)
            accumulator -= tickDuration
            steps += 1
        }
        if steps == 5 { accumulator = 0 }
        if steps > 0 {
            updateHUD()
            recordIfFinished()
        }
        effects.prune(now: timestamp)
    }

    private func noteWaiting(_ waiting: Bool, now: CFTimeInterval) {
        if !waiting {
            waitingSince = nil
            if isWaitingForOpponent { isWaitingForOpponent = false }
            return
        }
        if waitingSince == nil { waitingSince = now }
        let long = now - (waitingSince ?? now) > 0.5
        if long != isWaitingForOpponent { isWaitingForOpponent = long }
    }

    private func runAutopilot() {
        guard var bot = autopilot else { return }
        for command in bot.think(game: game) { match.issue(command) }
        autopilot = bot
    }

    /// Immediately computes a number of ticks (demo mode).
    func fastForward(ticks: Int) {
        for _ in 0..<ticks where !game.isFinished {
            runAutopilot()
            match.advance()
        }
        updateHUD()
    }

    private func rememberPositions() {
        previousPositions.removeAll(keepingCapacity: true)
        for board in game.players {
            for c in board.creeps {
                previousPositions[c.id] = CGPoint(x: c.x, y: c.y)
            }
        }
    }

    private func handleEvents(_ events: [GameEvent], now: CFTimeInterval) {
        for event in events {
            switch event {
            case let .commandRejected(player, _, reason) where player == me:
                show(reason.message)
            case let .towerSold(player, towerId, _):
                if player == me, selection == .tower(id: towerId) { selection = .none }
            default:
                break
            }
        }
        effects.add(events: events, game: game, now: now)
        effects.track(game: game, now: now)
        SoundManager.shared.handle(events, game: game, me: me)
    }

    private func updateHUD() {
        var h = HUD()
        let board = game.players[me]
        h.tick = game.tick
        if game.isFinished || board.isDead {
            h.phase = .finished(rank: board.rank)
        } else if !game.isStarted {
            h.phase = .countdown(seconds: Int((Double(game.ticksUntilStart) * tickDuration).rounded(.up)))
        } else {
            h.phase = .running
        }
        // A player without a name (two-player game) is shown as "You" or "Opponent".
        h.myName = board.name.isEmpty ? L("You") : board.name
        h.credits = board.credits
        h.available = board.credits - game.reservedCredits(player: me)
        h.income = board.income
        h.lives = board.lives
        h.secondsToIncome = Int((Double(game.ticksUntilIncome) * tickDuration).rounded(.up))
        let interval = game.isStarted ? game.rules.incomeIntervalTicks : max(1, game.rules.startTick)
        h.incomeFraction = Double(game.ticksUntilIncome) / Double(interval)
        if let o = shownOpponent {
            h.opponentName = displayName(o)
            h.opponentLives = game.players[o].lives
            h.opponentIncome = game.players[o].income
        }
        if board.sendMode == requestedSendMode { requestedSendMode = nil }
        h.sendMode = requestedSendMode ?? board.sendMode
        if isGroup {
            let next = game.opponent(of: me)
            h.opponents = game.players.indices.filter { $0 != me }
                .sorted { ($0 - me + game.players.count) % game.players.count < ($1 - me + game.players.count) % game.players.count }
                .map { i in
                    let p = game.players[i]
                    return OpponentInfo(id: i, name: displayName(i), lives: max(0, p.lives), income: p.income,
                                        isDead: p.isDead,
                                        isTarget: !p.isDead && (h.sendMode == .all || (h.sendMode == .next && i == next)))
                }
        }
        if h != hud { hud = h }
    }

    /// Name as shown: players without a name are "Opponent".
    func displayName(_ player: Int) -> String {
        let name = game.players[player].name
        return name.isEmpty ? (player == me ? L("You") : L("Opponent")) : name
    }

    // MARK: - Controls

    /// Boards a sent creep lands on (send mode "all": every living opponent).
    var recipients: Int { hud.sendMode == .all ? max(1, game.opponents(of: me).count) : 1 }

    func setSendMode(_ mode: SendMode) {
        guard mode != hud.sendMode else { return }
        requestedSendMode = mode
        match.issue(.setSendMode(mode))
        updateHUD()
    }

    /// Shows this opponent's board large (iPhone); tapping it again returns to the next one in the ring.
    func view(opponent: Int) {
        viewedOpponent = viewedOpponent == opponent || opponent == self.opponent ? nil : opponent
        updateHUD()
    }

    func tapCell(_ cell: GridPoint) {
        let board = game.players[me]
        if let tower = board.tower(at: cell) {
            selection = selection == .tower(id: tower.id) ? .none : .tower(id: tower.id)
            return
        }
        guard case let .placing(kind) = selection else {
            selection = .none
            return
        }
        guard game.map.isBuildable(cell) else { return show(RejectReason.cellNotBuildable.message) }
        guard !pendingBuilds.contains(where: { $0.cell == cell }) else { return }
        guard hud.available >= kind.stats(level: 1).price else { return show(RejectReason.notEnoughCredits.message) }
        match.issue(.buildTower(kind: kind, cell: cell))
        updateHUD()
    }

    func togglePlacing(_ kind: TowerKind) {
        selection = selection == .placing(kind) ? .none : .placing(kind)
    }

    /// Sends one creep, or with `wave` a wave (at most 20, as many as the credits allow).
    func send(_ type: CreepType, wave: Bool = false) {
        guard canAfford(type) else { return show(RejectReason.notEnoughCredits.message) }
        match.issue(.sendCreeps(type: type, count: wave ? game.rules.waveSize : 1))
        // Sending creeps means the player has moved on: the tower panel closes.
        if case .tower = selection { selection = .none }
        updateHUD()
    }

    func canAfford(_ type: CreepType) -> Bool {
        hud.available >= type.stats.price * recipients
    }

    func upgradeSelected() {
        guard let tower = selectedTower, let price = tower.nextLevelPrice else { return }
        guard hud.available >= price else { return show(RejectReason.notEnoughCredits.message) }
        match.issue(.upgradeTower(id: tower.id))
        selection = .none   // done with this tower: the panel closes
        updateHUD()
    }

    func sellSelected() {
        guard let tower = selectedTower else { return }
        match.issue(.sellTower(id: tower.id))
        selection = .none
    }

    /// Target strategy as the player last chose it: an order still waiting, a change in progress or
    /// the current one. So the choice shows at once, although it takes effect only after 2 seconds.
    func chosenStrategy(of tower: Tower) -> (strategy: TargetStrategy, locked: Bool) {
        for scheduled in game.scheduledCommands(player: me).reversed() {
            if case let .setStrategy(id, strategy, locked) = scheduled.command, id == tower.id { return (strategy, locked) }
        }
        if case let .retargeting(_, strategy, locked) = tower.activity { return (strategy, locked) }
        return (tower.strategy, tower.locked)
    }

    func setStrategy(_ strategy: TargetStrategy, locked: Bool) {
        guard let tower = selectedTower else { return }
        match.issue(.setStrategy(towerId: tower.id, strategy: strategy, locked: locked))
    }

    var selectedTower: Tower? {
        guard case let .tower(id) = selection else { return nil }
        return game.players[me].tower(id: id)
    }

    /// Build orders still waiting to be executed (for the preview on the board).
    var pendingBuilds: [(kind: TowerKind, cell: GridPoint)] {
        game.scheduledCommands(player: me).compactMap {
            if case let .buildTower(kind, cell) = $0.command { return (kind: kind, cell: cell) }
            return nil
        }
    }

    func hasPendingAction(towerId: Int) -> Bool {
        game.scheduledCommands(player: me).contains {
            switch $0.command {
            case let .upgradeTower(id), let .sellTower(id): id == towerId
            case let .setStrategy(id, _, _): id == towerId
            default: false
            }
        }
    }

    private var toastCounter = 0
    private func show(_ text: String) {
        toastCounter += 1
        let toast = Toast(id: toastCounter, text: text)
        self.toast = toast
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            if self?.toast == toast { self?.toast = nil }
        }
    }
}

/// CADisplayLink needs an NSObject as its target.
@MainActor
private final class DisplayLinkProxy: NSObject {
    private var link: CADisplayLink?
    private let callback: @MainActor (CFTimeInterval) -> Void

    init(callback: @escaping @MainActor (CFTimeInterval) -> Void) {
        self.callback = callback
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        callback(link.timestamp)
    }

    func invalidate() {
        link?.invalidate()
        link = nil
    }
}
