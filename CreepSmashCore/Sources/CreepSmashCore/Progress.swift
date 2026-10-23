import Foundation

// Statistics, leaderboard and achievements of the local player.
//
// While a game runs, `GameStats` watches the events of each tick. At the end it turns into a
// `GameSummary`, which `PlayerRecord.add(_:)` adds to the totals. The record is what the app stores;
// the achievements are computed from it, so they never get out of step with the statistics.

/// What kind of game was played.
public enum GameMode: Codable, Equatable, Hashable, Sendable {
    case computer(Bot.Level)
    case online
    /// Against two or three computer opponents. Counts for its level like a game against one, and has its
    /// own leaderboard per number of opponents (times against three are not comparable with times against one).
    case computerGroup(Bot.Level, opponents: Int)
}

/// Values of one player at one moment of the game.
public struct PlayerSample: Codable, Equatable, Sendable {
    public var income: Int
    public var lives: Int
    public var damage: Int
    public var healthSent: Int
    /// Health of all creeps that have arrived on the board so far (older records: nil).
    public var arrived: Int?
    /// Damage the towers could deal in one income round if creeps passed them all the time – the installed
    /// capacity of the defense (older records: nil).
    public var capacity: Int?

    public init(income: Int, lives: Int, damage: Int, healthSent: Int, arrived: Int? = nil, capacity: Int? = nil) {
        self.income = income
        self.lives = lives
        self.damage = damage
        self.healthSent = healthSent
        self.arrived = arrived
        self.capacity = capacity
    }
}

/// How well and how economically one player defended, over the whole game – in Green IT terms: was the
/// service delivered (effectiveness), how much of the installed capacity was used (utilization), and how much
/// of the income went into it (share).
public struct DefenseRecord: Codable, Equatable, Sendable {
    /// Health of all creeps that arrived on the board, and the part of it the towers shot away.
    public var healthArrived: Int
    public var healthStopped: Int
    /// Credits put into towers: building and upgrades, minus refunds for sold towers.
    public var towerSpent: Int
    /// Credits earned: start credits, income and bounties.
    public var earned: Int
    /// "Zombie towers": standing at the end, ready for at least `GameStats.zombieReadyTicks` while the player
    /// was in the game, and busy (shooting or reloading) less than 5 % of that time – and what they cost.
    /// Rare, because the path leads past all towers; shown only when there are some.
    public var zombieTowers: Int
    public var zombieValue: Int
    /// Installed capacity over the game: the health all towers could have shot away while the player was in
    /// the game, had creeps passed them all the time (older records: nil).
    public var capacity: Int?

    public init(healthArrived: Int, healthStopped: Int, towerSpent: Int, earned: Int, zombieTowers: Int, zombieValue: Int,
                capacity: Int? = nil) {
        self.healthArrived = healthArrived
        self.healthStopped = healthStopped
        self.towerSpent = towerSpent
        self.earned = earned
        self.zombieTowers = zombieTowers
        self.zombieValue = zombieValue
        self.capacity = capacity
    }

    /// Effectiveness: share of the arriving health that was shot away, in per mille.
    public var stoppedPermille: Int? { healthArrived > 0 ? min(1000, healthStopped * 1000 / healthArrived) : nil }
    /// Utilization: arriving health in relation to the installed capacity, in per mille. Low = capacity standing
    /// idle (overprovisioning); above about 600 lives are usually lost, because creeps are not always in range.
    public var utilizationPermille: Int? {
        guard let capacity, capacity > 0 else { return nil }
        return healthArrived * 1000 / capacity
    }
    /// Share of the earned credits put into towers, in per mille – independent of how much was earned.
    public var towerSharePermille: Int? { earned > 0 ? max(0, towerSpent) * 1000 / earned : nil }
}

/// One sample of the course of a game (taken at every income payment), for the evaluation afterwards.
public struct GameSample: Codable, Equatable, Sendable {
    public var tick: Int
    public var myIncome: Int
    public var opponentIncome: Int
    public var myLives: Int
    public var opponentLives: Int
    /// Running totals: damage done by the towers, health of the creeps sent (older records: nil).
    public var myDamage: Int?
    public var opponentDamage: Int?
    public var myHealthSent: Int?
    public var opponentHealthSent: Int?
    /// All players by index (newer records); the my/opponent values above stay for older ones.
    public var players: [PlayerSample]?

    public init(tick: Int, myIncome: Int, opponentIncome: Int, myLives: Int, opponentLives: Int,
                myDamage: Int? = nil, opponentDamage: Int? = nil, myHealthSent: Int? = nil, opponentHealthSent: Int? = nil,
                players: [PlayerSample]? = nil) {
        self.tick = tick
        self.myIncome = myIncome
        self.opponentIncome = opponentIncome
        self.myLives = myLives
        self.opponentLives = opponentLives
        self.myDamage = myDamage
        self.opponentDamage = opponentDamage
        self.myHealthSent = myHealthSent
        self.opponentHealthSent = opponentHealthSent
        self.players = players
    }
}

/// The result of a finished game from the local player's point of view.
public struct GameSummary: Codable, Equatable, Sendable {
    public var mode: GameMode
    public var mapID: String
    public var won: Bool
    public var durationTicks: Int
    public var livesLeft: Int
    public var livesLost: Int
    public var maxIncome: Int
    public var creepsSent: Int
    public var creepsKilled: Int
    public var towersBuilt: Int
    public var builtUltimate: Bool
    public var sentColossus: Bool
    public var samples: [GameSample]
    public var date: Date
    /// Name of the opponent as shown in the game (older records: nil).
    public var opponentName: String?
    /// Names of all players by index and the local player's index (older records: nil).
    public var playerNames: [String]?
    public var me: Int?
    /// Damage done by the own towers and health of all creeps sent (older records: nil).
    public var damageDealt: Int?
    public var healthSent: Int?
    /// What the own towers standing at the end cost, upgrades included (older records: nil).
    public var towerValue: Int?
    /// Efficiency of the defense of every player, by player index (older records: nil).
    public var defense: [DefenseRecord]?

    /// The own defense record.
    public var myDefense: DefenseRecord? {
        guard let defense, let me, defense.indices.contains(me) else { return nil }
        return defense[me]
    }

    /// The opponents' records (all others).
    public var opponentDefense: [DefenseRecord] {
        guard let defense, let me else { return [] }
        return defense.indices.filter { $0 != me }.map { defense[$0] }
    }

    /// Mean of a value over the opponents that have it.
    public func opponentMean(_ value: (DefenseRecord) -> Int?) -> Int? {
        let values = opponentDefense.compactMap(value)
        return values.isEmpty ? nil : values.reduce(0, +) / values.count
    }

    public var seconds: Int { durationTicks * Rules.standard.tickMilliseconds / 1000 }

    public init(mode: GameMode, mapID: String, won: Bool, durationTicks: Int, livesLeft: Int, livesLost: Int,
                maxIncome: Int, creepsSent: Int, creepsKilled: Int, towersBuilt: Int, builtUltimate: Bool,
                sentColossus: Bool, samples: [GameSample], date: Date, opponentName: String? = nil,
                damageDealt: Int? = nil, healthSent: Int? = nil, playerNames: [String]? = nil, me: Int? = nil,
                towerValue: Int? = nil, defense: [DefenseRecord]? = nil) {
        self.mode = mode
        self.mapID = mapID
        self.won = won
        self.durationTicks = durationTicks
        self.livesLeft = livesLeft
        self.livesLost = livesLost
        self.maxIncome = maxIncome
        self.creepsSent = creepsSent
        self.creepsKilled = creepsKilled
        self.towersBuilt = towersBuilt
        self.builtUltimate = builtUltimate
        self.sentColossus = sentColossus
        self.samples = samples
        self.date = date
        self.opponentName = opponentName
        self.damageDealt = damageDealt
        self.healthSent = healthSent
        self.playerNames = playerNames
        self.me = me
        self.towerValue = towerValue
        self.defense = defense
    }
}

/// Collects the statistics of one game while it runs.
public struct GameStats: Sendable {
    public let me: Int
    public let mode: GameMode
    private(set) var livesLost = 0
    private(set) var maxIncome = 0
    private(set) var creepsSent = 0
    private(set) var creepsKilled = 0
    private(set) var towersBuilt = 0
    private(set) var builtUltimate = false
    private(set) var sentColossus = false
    private(set) var samples: [GameSample] = []
    /// Per player: health arrived, credits put into towers (building and upgrades minus refunds), credits earned.
    private(set) var arrived: [Int] = []
    private(set) var towerSpent: [Int] = []
    private(set) var earned: [Int] = []
    /// Per player: installed capacity summed up per tick while in the game, in thousandths of health.
    private(set) var capacityMilli: [Int] = []
    /// Per tower: ticks ready while its player was in the game, and ticks busy (each shot counts its reload time).
    private struct TowerKey: Hashable { let player: Int, id: Int }
    private var towerTicks: [TowerKey: (ready: Int, busy: Int)] = [:]

    /// A tower ready for at least this long (2 minutes) and busy less than 5 % of it counts as a zombie.
    public static let zombieReadyTicks = 2 * 60 * 20

    public init(me: Int, mode: GameMode) {
        self.me = me
        self.mode = mode
    }

    /// Call after every tick with the events of that tick.
    public mutating func observe(_ game: Game) {
        let board = game.players[me]
        maxIncome = max(maxIncome, board.income)
        if arrived.isEmpty {
            arrived = Array(repeating: 0, count: game.players.count)
            towerSpent = arrived
            earned = Array(repeating: game.rules.startCredits, count: game.players.count)
            capacityMilli = arrived
        }
        // After a player is out, its towers no longer count: they are idle, but not wasted.
        for (p, player) in game.players.enumerated() where !player.isDead {
            for tower in player.towers {
                capacityMilli[p] += tower.stats.damage * 1000 / max(1, tower.stats.reloadTicks)
                if tower.activity.isReady { towerTicks[TowerKey(player: p, id: tower.id), default: (0, 0)].ready += 1 }
            }
        }
        for event in game.events {
            switch event {
            case let .creepsSent(_, to, type, count):
                arrived[to] += type.stats.health * count
            case let .incomePaid(player, amount):
                earned[player] += amount
            case let .creepKilled(player, _, _, _, _, bounty):
                earned[player] += bounty
            case let .towerBuilt(player, towerId):
                towerSpent[player] += game.players[player].tower(id: towerId)?.totalPrice ?? 0
            case let .towerUpgraded(player, towerId, level):
                towerSpent[player] += game.players[player].tower(id: towerId)?.kind.stats(level: level).price ?? 0
            case let .towerSold(player, _, refund):
                towerSpent[player] -= refund
            case let .laserShot(player, towerId, _, _), let .rocketLaunched(player, towerId):
                let reload = game.players[player].tower(id: towerId)?.stats.reloadTicks ?? 0
                towerTicks[TowerKey(player: player, id: towerId), default: (0, 0)].busy += reload
            default:
                break
            }
        }
        for event in game.events {
            switch event {
            case let .creepKilled(player, _, _, _, _, _) where player == me:
                creepsKilled += 1
            case let .creepsSent(from, _, type, count) where from == me:
                creepsSent += count
                if type == .fatColossus { sentColossus = true }
            case let .towerBuilt(player, towerId) where player == me:
                towersBuilt += 1
                if board.tower(id: towerId)?.kind == .ultimate { builtUltimate = true }
            case let .towerUpgraded(player, towerId, _) where player == me:
                if board.tower(id: towerId)?.kind == .ultimate { builtUltimate = true }
            case let .creepEscaped(player, _, _, _) where player == me:
                livesLost += 1
            case let .incomePaid(player, _) where player == me:
                if let sample = sample(game) { samples.append(sample) }
            default:
                break
            }
        }
    }

    /// The summary at the end of the game. `won` is passed in because a game can also end by the
    /// opponent leaving or by giving up.
    public func summary(game: Game, won: Bool, date: Date = Date(), opponentName: String? = nil,
                        playerNames: [String]? = nil) -> GameSummary {
        // The course ends with the state at the end of the game, not at the last income payment.
        var course = samples
        if course.last?.tick != game.tick, let sample = sample(game) { course.append(sample) }
        return GameSummary(mode: mode, mapID: game.map.id, won: won, durationTicks: max(0, game.tick - game.rules.startTick),
                           livesLeft: max(0, game.players[me].lives), livesLost: livesLost, maxIncome: maxIncome,
                           creepsSent: creepsSent, creepsKilled: creepsKilled, towersBuilt: towersBuilt,
                           builtUltimate: builtUltimate, sentColossus: sentColossus, samples: course, date: date,
                           opponentName: opponentName, damageDealt: game.players[me].damageDealt,
                           healthSent: game.players[me].healthSent,
                           playerNames: playerNames ?? game.players.map(\.name), me: me,
                           towerValue: game.players[me].towerValue,
                           defense: arrived.isEmpty ? nil : game.players.indices.map { defenseRecord(game, player: $0) })
    }

    /// Installed capacity of a defense: the damage all towers could deal in one income round if there were
    /// always a creep in range (splash and slowing not counted).
    static func capacity(of board: PlayerBoard, rules: Rules) -> Int {
        board.towers.reduce(0) { $0 + $1.stats.damage * rules.incomeIntervalTicks / max(1, $1.stats.reloadTicks) }
    }

    private func defenseRecord(_ game: Game, player p: Int) -> DefenseRecord {
        let zombies = game.players[p].towers.filter { tower in
            guard let ticks = towerTicks[TowerKey(player: p, id: tower.id)] else { return false }
            return ticks.ready >= Self.zombieReadyTicks && ticks.busy * 20 < ticks.ready
        }
        return DefenseRecord(healthArrived: arrived[p], healthStopped: game.players[p].damageDealt,
                             towerSpent: towerSpent[p], earned: earned[p], zombieTowers: zombies.count,
                             zombieValue: zombies.reduce(0) { $0 + $1.totalPrice }, capacity: capacityMilli[p] / 1000)
    }

    private func sample(_ game: Game) -> GameSample? {
        guard let opponent = game.opponent(of: me) ?? game.players.indices.first(where: { $0 != me }) else { return nil }
        let board = game.players[me], other = game.players[opponent]
        return GameSample(tick: game.tick, myIncome: board.income, opponentIncome: other.income,
                          myLives: max(0, board.lives), opponentLives: max(0, other.lives),
                          myDamage: board.damageDealt, opponentDamage: other.damageDealt,
                          myHealthSent: board.healthSent, opponentHealthSent: other.healthSent,
                          players: game.players.enumerated().map { p, board in
                              PlayerSample(income: board.income, lives: max(0, board.lives), damage: board.damageDealt,
                                           healthSent: board.healthSent,
                                           arrived: arrived.indices.contains(p) ? arrived[p] : 0,
                                           capacity: Self.capacity(of: board, rules: game.rules))
                          })
    }
}

/// An entry of the leaderboard: a win against the computer.
public struct LeaderboardEntry: Codable, Equatable, Sendable {
    public var name: String
    public var mapID: String
    public var durationTicks: Int
    public var livesLeft: Int
    public var date: Date

    public var seconds: Int { durationTicks * Rules.standard.tickMilliseconds / 1000 }

    public init(name: String, mapID: String, durationTicks: Int, livesLeft: Int, date: Date) {
        self.name = name
        self.mapID = mapID
        self.durationTicks = durationTicks
        self.livesLeft = livesLeft
        self.date = date
    }

    /// Faster wins first; with the same time, more lives left first.
    static func ranked(_ a: LeaderboardEntry, _ b: LeaderboardEntry) -> Bool {
        a.durationTicks != b.durationTicks ? a.durationTicks < b.durationTicks : a.livesLeft > b.livesLeft
    }
}

/// Everything the app stores about the local player.
public struct PlayerRecord: Codable, Equatable, Sendable {
    public var games = 0
    public var wins = 0
    public var winsByLevel: [String: Int] = [:]
    public var gamesByLevel: [String: Int] = [:]
    public var onlineGames = 0
    public var onlineWins = 0
    public var currentStreak = 0
    public var bestStreak = 0
    public var flawlessWins = 0
    public var closeWins = 0
    public var fastWins = 0
    public var creepsSent = 0
    public var creepsKilled = 0
    public var towersBuilt = 0
    public var bestIncome = 0
    /// Wins with an efficient defense and with a lean defense (optional: older records do not have them).
    public var efficientWins: Int?
    public var leanWins: Int?
    public var builtUltimate = false
    public var sentColossus = false
    public var mapsWon: Set<String> = []
    public var totalTicks = 0
    /// Fastest wins against the computer per level and number of opponents (`leaderboardKey`), at most
    /// `leaderboardSize` each.
    public var leaderboard: [String: [LeaderboardEntry]] = [:]
    /// The last game, for the evaluation after the game.
    public var lastGame: GameSummary?

    public static let leaderboardSize = 10
    /// A win in at most this many seconds of play counts as a fast win.
    public static let fastWinSeconds = 8 * 60
    /// A win counts as efficient when the defense stopped at least this much (per mille) of what arrived and
    /// was used at least this much (per mille of its capacity): the service delivered without idle capacity.
    public static let efficientStoppedPermille = 900
    public static let efficientUtilizationPermille = 400

    /// Key of the leaderboard for a level and number of computer opponents (one opponent: just the level, as
    /// in older records).
    public static func leaderboardKey(_ level: Bot.Level, opponents: Int) -> String {
        opponents <= 1 ? level.rawValue : "\(level.rawValue)-\(opponents)"
    }


    public init() {}

    public func achievementLevels() -> [String: Int] {
        Dictionary(uniqueKeysWithValues: Achievement.all.map { ($0.id, $0.tier(in: self)) })
    }

    public struct Outcome: Equatable, Sendable {
        /// Achievements that reached a new tier: id and the tier now reached (1 = first).
        public var unlocked: [(id: String, tier: Int)]
        /// Place on the leaderboard (1 = best), if the game made it there.
        public var leaderboardPlace: Int?

        public static func == (a: Outcome, b: Outcome) -> Bool {
            a.leaderboardPlace == b.leaderboardPlace && a.unlocked.map(\.id) == b.unlocked.map(\.id)
                && a.unlocked.map(\.tier) == b.unlocked.map(\.tier)
        }
    }

    /// Adds a finished game and reports what is new.
    @discardableResult
    public mutating func add(_ game: GameSummary, playerName: String) -> Outcome {
        let before = achievementLevels()
        games += 1
        totalTicks += game.durationTicks
        creepsSent += game.creepsSent
        creepsKilled += game.creepsKilled
        towersBuilt += game.towersBuilt
        bestIncome = max(bestIncome, game.maxIncome)
        builtUltimate = builtUltimate || game.builtUltimate
        sentColossus = sentColossus || game.sentColossus
        var place: Int?
        switch game.mode {
        case let .computer(level):
            gamesByLevel[level.rawValue, default: 0] += 1
            if game.won {
                winsByLevel[level.rawValue, default: 0] += 1
                place = enter(game, name: playerName, key: Self.leaderboardKey(level, opponents: 1))
            }
        case .online:
            onlineGames += 1
            if game.won { onlineWins += 1 }
        case let .computerGroup(level, opponents):
            gamesByLevel[level.rawValue, default: 0] += 1
            if game.won {
                winsByLevel[level.rawValue, default: 0] += 1
                place = enter(game, name: playerName, key: Self.leaderboardKey(level, opponents: opponents))
            }
        }
        if game.won {
            wins += 1
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
            mapsWon.insert(game.mapID)
            if game.livesLost == 0 { flawlessWins += 1 }
            if game.livesLeft == 1 { closeWins += 1 }
            if game.seconds <= Self.fastWinSeconds { fastWins += 1 }
            if let defense = game.myDefense {
                if let stopped = defense.stoppedPermille, stopped >= Self.efficientStoppedPermille,
                   let used = defense.utilizationPermille, used >= Self.efficientUtilizationPermille {
                    efficientWins = (efficientWins ?? 0) + 1
                }
                // Lean: a smaller share of the income put into towers than every opponent.
                let others = game.opponentDefense.compactMap(\.towerSharePermille)
                if let mine = defense.towerSharePermille, let least = others.min(), mine < least {
                    leanWins = (leanWins ?? 0) + 1
                }
            }
        } else {
            currentStreak = 0
        }
        lastGame = game
        let after = achievementLevels()
        let unlocked = Achievement.all.compactMap { a -> (id: String, tier: Int)? in
            let new = after[a.id] ?? 0
            return new > (before[a.id] ?? 0) ? (a.id, new) : nil
        }
        return Outcome(unlocked: unlocked, leaderboardPlace: place)
    }

    /// Enters a win into a leaderboard; returns its place, if it made it there.
    private mutating func enter(_ game: GameSummary, name: String, key: String) -> Int? {
        let entry = LeaderboardEntry(name: name, mapID: game.mapID, durationTicks: game.durationTicks,
                                     livesLeft: game.livesLeft, date: game.date)
        var list = leaderboard[key, default: []]
        list.append(entry)
        list.sort(by: LeaderboardEntry.ranked)
        list = Array(list.prefix(Self.leaderboardSize))
        leaderboard[key] = list
        return list.firstIndex(of: entry).map { $0 + 1 }
    }

    /// Wins against several computers did not enter a leaderboard before version 0.4.3: enters the last game,
    /// if it is such a win (the only one still stored). Does nothing when it is already there.
    public mutating func enterLastGroupWin() {
        guard let game = lastGame, game.won, case let .computerGroup(level, opponents) = game.mode else { return }
        let key = Self.leaderboardKey(level, opponents: opponents)
        guard !(leaderboard[key] ?? []).contains(where: { $0.date == game.date }) else { return }
        let name = game.me.flatMap { game.playerNames?.indices.contains($0) == true ? game.playerNames?[$0] : nil } ?? ""
        _ = enter(game, name: name, key: key)
    }
}

/// An achievement with one or more tiers (e.g. 1, 10, 100 wins).
public struct Achievement: Sendable {
    public let id: String
    /// Thresholds of the tiers, ascending; a single threshold means a one-time achievement.
    public let tiers: [Int]
    /// The value the thresholds are compared with.
    public let value: @Sendable (PlayerRecord) -> Int

    /// Number of tiers reached (0 = none yet).
    public func tier(in record: PlayerRecord) -> Int {
        tier(value: value(record))
    }

    /// Number of tiers reached with this value (e.g. the larger of the device's and Game Center's).
    public func tier(value v: Int) -> Int {
        tiers.filter { v >= $0 }.count
    }

    /// Threshold of the next tier for this value, or nil when all tiers are reached.
    public func nextThreshold(value v: Int) -> Int? {
        tiers.first { v < $0 }
    }

    public func progress(in record: PlayerRecord) -> Int { value(record) }

    /// Threshold of the next tier, or nil when all tiers are reached.
    public func nextThreshold(in record: PlayerRecord) -> Int? {
        let t = tier(in: record)
        return t < tiers.count ? tiers[t] : nil
    }

    public static let all: [Achievement] = [
        Achievement(id: "wins", tiers: [1, 10, 100]) { $0.wins },
        Achievement(id: "winsHard", tiers: [1, 10, 50]) { $0.winsByLevel[Bot.Level.hard.rawValue] ?? 0 },
        Achievement(id: "flawless", tiers: [1, 10]) { $0.flawlessWins },
        Achievement(id: "closeCall", tiers: [1]) { $0.closeWins },
        Achievement(id: "fastWin", tiers: [1, 10]) { $0.fastWins },
        Achievement(id: "efficient", tiers: [1, 10]) { $0.efficientWins ?? 0 },
        Achievement(id: "lean", tiers: [1, 10]) { $0.leanWins ?? 0 },
        Achievement(id: "allMaps", tiers: [GameMap.all.count]) { r in GameMap.all.filter { r.mapsWon.contains($0.id) }.count },
        Achievement(id: "streak", tiers: [3, 5, 10]) { $0.bestStreak },
        Achievement(id: "onlineWins", tiers: [1, 10, 50]) { $0.onlineWins },
        Achievement(id: "creepsKilled", tiers: [100, 1_000, 10_000]) { $0.creepsKilled },
        Achievement(id: "creepsSent", tiers: [100, 1_000, 10_000]) { $0.creepsSent },
        Achievement(id: "towersBuilt", tiers: [50, 500, 5_000]) { $0.towersBuilt },
        Achievement(id: "income", tiers: [1_000, 10_000, 100_000]) { $0.bestIncome },
        Achievement(id: "ultimate", tiers: [1]) { $0.builtUltimate ? 1 : 0 },
        Achievement(id: "colossus", tiers: [1]) { $0.sentColossus ? 1 : 0 },
        Achievement(id: "games", tiers: [10, 100, 1_000]) { $0.games },
    ]
}
