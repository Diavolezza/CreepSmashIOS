/// Simple computer opponent for single-player games against the computer.
///
/// The bot sees the same game state as the UI and issues commands the same way as a
/// human. It decides at regular intervals: defense first (build or upgrade), then it attacks with the rest.
public struct Bot: Sendable {
    public enum Level: String, CaseIterable, Codable, Sendable {
        case easy, normal, hard

        /// Ticks between two decisions.
        var thinkInterval: Int {
            switch self {
            case .easy: 120
            case .normal: 20
            case .hard: 10
            }
        }

        /// Share of all spending that goes into sending creeps (percent). Sent creeps raise the income
        /// permanently, so this is the bot's investment in its economy; a bot that only defends falls behind.
        var economyShare: Int {
            switch self {
            case .easy: 30
            case .normal: 65
            case .hard: 70
            }
        }

        /// Maximum number of towers; after that the bot only upgrades.
        var maxTowers: Int {
            switch self {
            case .easy: 8
            case .normal: 12
            case .hard: 16
            }
        }

        /// Minimum wave size; the bot saves up for it instead of wasting single creeps.
        var minimumWave: Int {
            switch self {
            case .easy: 3
            case .normal: 5
            case .hard: 6
            }
        }

        /// Highest tower level the bot upgrades to.
        var maxTowerLevel: Int {
            switch self {
            case .easy: 2
            case .normal, .hard: 4
            }
        }

        /// How far ahead the bot looks when it checks its defense: the opponent's income over this many
        /// half rounds is assumed to arrive as one wave.
        var threatRounds: Int {
            switch self {
            case .easy: 0
            case .normal: 3
            case .hard: 4
            }
        }

        /// How strongly the bot rates the opponent's attack power (percent).
        var caution: Int {
            switch self {
            case .easy: 110
            case .normal: 80
            case .hard: 65
            }
        }
    }

    public let player: Int
    public let level: Level
    private var nextThinkTick = 0
    private var wavesSent = 0
    private var lastLives = Int.max
    /// Tick at which the bot last lost a life.
    private var lastLifeLostTick = Int.min / 2
    private var spentOnDefense = 0
    private var spentOnAttack = 0
    /// Results of `simulatedLeaks` (key: type and count) for the opponent's towers in `leakCacheTowers`.
    private var leakCache: [Int: Int] = [:]
    private var leakCacheTowers = 0
    /// Scratch games the bot may still play in this decision (they cost time on the device).
    private var simulationBudget = 0
    /// Results of `threatLeaks` for our own towers in `threatCacheTowers`, and its budget per decision.
    private var threatCache: [Int: Int] = [:]
    private var threatCacheTowers = 0
    private var threatBudget = 0
    /// Score of each cell: how many path points lie within range (for a range of 50 px).
    private let cellScores: [(cell: GridPoint, score: Int)]

    public init(player: Int, level: Level, map: GameMap) {
        self.player = player
        self.level = level
        var scores: [(GridPoint, Int)] = []
        let range = 50 * Board.milli
        for y in 0..<Board.cells {
            for x in 0..<Board.cells {
                let cell = GridPoint(x: x, y: y)
                guard map.isBuildable(cell) else { continue }
                let c = Board.center(of: cell)
                let score = map.path.filter { point in
                    let q = Board.center(of: point)
                    return distanceSquared(c.x, c.y, q.x, q.y) < range * range
                }.count
                if score > 0 { scores.append((cell, score)) }
            }
        }
        // Best cells first; on a tie, closer to the end of the path (that is the last chance).
        cellScores = scores.sorted { a, b in
            a.1 != b.1 ? a.1 > b.1 : (a.0.y, a.0.x) < (b.0.y, b.0.x)
        }
    }

    /// Returns the commands the bot wants to issue now.
    public mutating func think(game: Game) -> [Command] {
        guard game.isStarted, !game.isFinished, game.tick >= nextThinkTick else { return [] }
        nextThinkTick = game.tick + level.thinkInterval
        let board = game.players[player]
        guard !board.isDead else { return [] }

        let budget = board.credits - game.reservedCredits(player: player)
        var commands: [Command] = []
        simulationBudget = 3
        threatBudget = 2

        // 1. Defense – only as much as needed. Requirement: the damage our own towers deal to a creep
        //    of medium speed during one pass must cover what is already on the board plus one wave
        //    from one income round of the opponent (roughly 7 health per credit).
        let opponentIncome = game.opponent(of: player).map { game.players[$0].income } ?? 0
        let threat = board.creeps.reduce(0) { $0 + $1.health }
        let damage = Self.damagePerPass(towers: board.towers, map: game.map, speed: 70)
        let wanted = 300 + (opponentIncome * 7 * level.caution / 100 + threat) * 6 / 5
        if board.lives < lastLives { lastLifeLostTick = game.tick }
        lastLives = board.lives
        // Normal and hard also play through the strongest wave the opponent could afford soon against
        // their own towers: if it would get through, the defense is too weak.
        var defenseNeeded = damage < wanted
        if level != .easy, !defenseNeeded, let opponent = game.opponent(of: player),
           threatLeaks(game: game, opponent: opponent, fund: opponentIncome * level.threatRounds / 2) > 0 {
            defenseNeeded = true
        }
        // Under fire (a life lost in the last 20 seconds and creeps on the board): defend first.
        let underFire = game.tick - lastLifeLostTick < 400 && damage < threat * 2
        // Otherwise defense may only take its share of the spending, the rest goes into creeps.
        let share = level.economyShare
        let defenseInBudget = spentOnDefense * share <= spentOnAttack * (100 - share) + 400 * share
        var money = budget
        if defenseNeeded && (underFire || defenseInBudget),
           let command = defenseCommand(board: board, budget: money, game: game) {
            commands.append(command)
            let price = cost(of: command, board: board)
            money -= price
            spentOnDefense += price
        }

        // 2. Attack with the rest. Sent creeps raise the income permanently, so even a wave that is shot
        //    down is an investment. The type is chosen by which one gets the most creeps through the
        //    opponent's defense. While under fire only part of the rest is used.
        // "Easy" holds back half of its money, so it attacks less and leaves the player room to grow.
        let attackMoney = underFire ? money / 3 : (level == .easy ? money / 2 : money)
        if let plan = attackPlan(game: game, fund: attackMoney, saveForBreakthrough: !defenseInBudget || !defenseNeeded) {
            commands.append(.sendCreeps(type: plan.type, count: plan.count))
            spentOnAttack += plan.type.stats.price * plan.count
            wavesSent += 1
        }
        return commands
    }

    /// Damage the towers deal to a single creep with `speed` during one pass:
    /// for each tower, damage per tick times the time the creep spends in range.
    static func damagePerPass(towers: [Tower], map: GameMap, speed: Int, slowed: Bool = false) -> Int {
        let ticksPerCell = Board.segmentSteps / max(1, speed * Board.milli)
        var total = 0
        for tower in towers {
            let s = tower.stats
            let center = Board.center(of: tower.cell)
            let r = s.range * Board.milli
            let cellsInRange = map.path.reduce(0) { n, p in
                let q = Board.center(of: p)
                return n + (distanceSquared(center.x, center.y, q.x, q.y) < r * r ? 1 : 0)
            }
            var damage = s.damage * cellsInRange * ticksPerCell / s.reloadTicks
            if s.splashRadius > 0 { damage = damage * 3 / 2 }   // hits several creeps of a wave
            if slowed, s.slowPermille > 0 { damage = damage * 3 / 2 }
            total += damage
        }
        return total
    }

    /// Damage the opponent's towers deal to a whole wave during one pass, in health points.
    /// Single-target towers split their damage among the creeps of the wave. Splash towers (and rockets)
    /// hit every creep within their radius with each shot – against a dense wave of many weak creeps
    /// that multiplies their damage, which is why swarms of cheap creeps rarely get through a splash tower.
    static func waveDamage(towers: [Tower], map: GameMap, type: CreepType, count: Int, slowed: Bool, rules: Rules) -> Int {
        let speed = type.stats.speed
        let ticksPerCell = Board.segmentSteps / max(1, speed * Board.milli)
        // Distance between two creeps of the wave in milli-pixels.
        let spacing = max(1, rules.waveSpacingTicks * speed * Board.cellSize)
        var total = 0
        for tower in towers {
            let s = tower.stats
            let center = Board.center(of: tower.cell)
            let r = s.range * Board.milli
            let cellsInRange = map.path.reduce(0) { n, p in
                let q = Board.center(of: p)
                return n + (distanceSquared(center.x, center.y, q.x, q.y) < r * r ? 1 : 0)
            }
            var damage = s.damage * cellsInRange * ticksPerCell / s.reloadTicks
            if s.splashRadius > 0 {
                // Creeps hit per shot; on average they take about 60 % (damage falls off towards the edge).
                let hits = min(count, 1 + 2 * s.splashRadius * Board.milli / spacing)
                damage = damage * hits * 6 / 10
            }
            if slowed, s.slowPermille > 0 { damage = damage * 3 / 2 }
            total += damage
        }
        return total
    }

    /// Chooses creep type and count: the wave that gets the most creeps through the opponent's defense.
    ///
    /// Instead of estimating, the bot plays the wave through in a scratch copy of the opponent's board
    /// (`simulatedLeaks`) – slowing, splash damage and target strategies are then exactly as in the game.
    /// Against splash towers that rules out swarms of cheap creeps, which die all at once.
    private mutating func attackPlan(game: Game, fund: Int, saveForBreakthrough: Bool) -> (type: CreepType, count: Int)? {
        guard let opponent = game.opponent(of: player) else { return nil }
        let income = game.players[player].income
        let minimumWave = income < 500 ? 3 : level.minimumWave
        // "Easy" does not look at the opponent's defense: it simply sends the most expensive wave it can afford.
        if level == .easy {
            return CreepType.allCases.reversed()
                .map { (type: $0, count: min(game.rules.waveSize, fund / $0.stats.price)) }
                .first { $0.count >= minimumWave }
        }
        // Candidates: the five most expensive affordable types, as many of each as the money allows –
        // a single strong creep is often worth more than a swarm of weak ones.
        func candidates(_ fund: Int) -> [(type: CreepType, count: Int)] {
            Array(CreepType.allCases.reversed()
                .map { (type: $0, count: min(game.rules.waveSize, fund / $0.stats.price)) }
                .filter { $0.count >= 1 }
                .prefix(5))
        }
        func bestPlan(_ fund: Int) -> (type: CreepType, count: Int, leaks: Int)? {
            var best: (type: CreepType, count: Int, leaks: Int)?
            for c in candidates(fund) {
                // Not everything evaluated yet: decide at the next opportunity (results are cached).
                guard let l = simulatedLeaks(game: game, opponent: opponent, type: c.type, count: c.count) else { return nil }
                // More creeps through is better; on a tie the more expensive wave (more health per credit).
                if best == nil || l > best!.leaks || (l == best!.leaks && c.type.stats.price > best!.type.stats.price) {
                    best = (c.type, c.count, l)
                }
            }
            return best
        }
        guard let plan = bestPlan(fund) else { return nil }
        // Nothing gets through: no point in feeding the opponent single creeps. Save at least one income
        // round and then send something strong – it still raises the income.
        if plan.leaks == 0 && fund < income { return nil }
        // Saving up can be worth it: wait if one more income round gets clearly more creeps through
        // per credit – but do not let the money sit idle for long.
        if saveForBreakthrough, fund < income * 3, let later = bestPlan(fund + income), later.leaks > 0 {
            let costNow = max(1, plan.type.stats.price * plan.count)
            let costLater = max(1, later.type.stats.price * later.count)
            let nowPerCredit = plan.leaks * 1_000_000 / costNow
            let laterPerCredit = later.leaks * 1_000_000 / costLater
            if laterPerCredit > nowPerCredit * 3 / 2 { return nil }
        }
        return (plan.type, plan.count)
    }

    /// How many creeps of the strongest wave the opponent could send with `fund` would get through our own
    /// towers (tries the three most expensive affordable types). Cached until our towers change.
    private mutating func threatLeaks(game: Game, opponent: Int, fund: Int) -> Int {
        let towers = game.players[player].towers
        var signature = Hasher()
        for t in towers { signature.combine(t.id); signature.combine(t.level); signature.combine(t.activity.isReady) }
        let key = signature.finalize()
        if key != threatCacheTowers {
            threatCache.removeAll()
            threatCacheTowers = key
        }
        var worst = 0
        let candidates = CreepType.allCases.reversed()
            .map { (type: $0, count: min(game.rules.waveSize, fund / $0.stats.price)) }
            .filter { $0.count >= 1 }
            .prefix(3)
        for c in candidates {
            let cacheKey = c.type.rawValue * 100 + c.count
            if let cached = threatCache[cacheKey] {
                worst = max(worst, cached)
                continue
            }
            guard threatBudget > 0 else { break }
            threatBudget -= 1
            let leaks = Self.playWave(map: game.map, towers: towers, type: c.type, count: c.count, rules: game.rules)
            threatCache[cacheKey] = leaks
            worst = max(worst, leaks)
        }
        return worst
    }

    /// How many creeps of a wave get through the opponent's current towers, found by playing the wave
    /// through a scratch game. Results are cached until the opponent's towers change.
    private mutating func simulatedLeaks(game: Game, opponent: Int, type: CreepType, count: Int) -> Int? {
        let towers = game.players[opponent].towers
        var signature = Hasher()
        for t in towers {
            signature.combine(t.id); signature.combine(t.level); signature.combine(t.kind.rawValue)
            signature.combine(t.strategy.index); signature.combine(t.locked)
        }
        let towersKey = signature.finalize()
        if towersKey != leakCacheTowers {
            leakCache.removeAll()
            leakCacheTowers = towersKey
        }
        let key = type.rawValue * 100 + count
        if let cached = leakCache[key] { return cached }
        guard simulationBudget > 0 else { return nil }
        simulationBudget -= 1
        let leaks = Self.playWave(map: game.map, towers: towers, type: type, count: count, rules: game.rules)
        leakCache[key] = leaks
        return leaks
    }

    /// Plays one wave over a board with the given towers and returns how many creeps reach the end.
    static func playWave(map: GameMap, towers: [Tower], type: CreepType, count: Int, rules: Rules) -> Int {
        var r = rules
        r.startTick = 0
        r.startLives = 1_000
        r.startCredits = 1_000_000_000
        let scratch = Game(map: map, playerNames: ["attacker", "defender"], rules: r)
        scratch.players[1].towers = towers.map { tower in
            var t = tower
            t.projectiles = []
            t.lastTargetId = nil
            return t
        }
        scratch.schedule(ScheduledCommand(tick: 0, player: 0, sequence: 1, command: .sendCreeps(type: type, count: count)))
        var finished = 0
        var leaked = 0
        // A pass takes well under 3000 ticks; stop when every creep has died or arrived once.
        while finished < count && scratch.tick < 3_000 {
            scratch.step()
            for event in scratch.events {
                switch event {
                case .creepKilled(1, _, _, _, _, _): finished += 1
                case .creepEscaped(1, _, _, _): finished += 1; leaked += 1
                default: break
                }
            }
        }
        return leaked
    }

    private func defenseCommand(board: PlayerBoard, budget: Int, game: Game) -> Command? {
        // An upgrade pays off when the next level is affordable and enough towers are already in place.
        let upgradable = board.towers
            .filter { $0.activity.isReady && $0.level < level.maxTowerLevel && ($0.nextLevelPrice ?? .max) <= budget }
            .sorted { ($0.nextLevelPrice ?? 0) < ($1.nextLevelPrice ?? 0) }
        let freeCells = cellScores.filter { board.tower(at: $0.cell) == nil && !isPlanned($0.cell, game: game) }

        if board.towers.count >= level.maxTowers || freeCells.isEmpty {
            return upgradable.first.map { .upgradeTower(id: $0.id) }
        }
        // Once there are several towers, an affordable upgrade is often better than another small tower.
        if board.towers.count >= level.maxTowers / 2, let tower = upgradable.first,
           (tower.nextLevelPrice ?? 0) * 2 <= budget {
            return .upgradeTower(id: tower.id)
        }
        guard let cell = freeCells.first?.cell else { return nil }
        let kind: TowerKind
        switch budget {
        case 20_000...: kind = .ultimate
        case 1_000...: kind = board.towers.contains { $0.kind == .speed } ? .rocket : .speed
        case 250...: kind = board.towers.filter { $0.kind == .splash }.count < 2 ? .splash : .basic
        case 100...: kind = board.towers.contains { $0.kind == .slow } ? .basic : .slow
        case 50...: kind = .basic
        default: return upgradable.first.map { .upgradeTower(id: $0.id) }
        }
        return .buildTower(kind: kind, cell: cell)
    }

    private func isPlanned(_ cell: GridPoint, game: Game) -> Bool {
        game.scheduledCommands(player: player).contains {
            if case let .buildTower(_, c) = $0.command { return c == cell }
            return false
        }
    }

    private func cost(of command: Command, board: PlayerBoard) -> Int {
        switch command {
        case let .buildTower(kind, _): kind.stats(level: 1).price
        case let .upgradeTower(id): board.tower(id: id)?.nextLevelPrice ?? 0
        case let .sendCreeps(type, count): type.stats.price * count
        case .sellTower, .setStrategy, .surrender, .setSendMode: 0
        }
    }
}
