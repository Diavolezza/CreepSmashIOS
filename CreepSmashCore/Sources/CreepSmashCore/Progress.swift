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
    /// Against two or three computer opponents. Counts for the totals and achievements, but not for the
    /// leaderboard and the statistics per difficulty (those compare games one against one).
    case computerGroup(Bot.Level, opponents: Int)
}

/// Values of one player at one moment of the game.
public struct PlayerSample: Codable, Equatable, Sendable {
    public var income: Int
    public var lives: Int
    public var damage: Int
    public var healthSent: Int

    public init(income: Int, lives: Int, damage: Int, healthSent: Int) {
        self.income = income
        self.lives = lives
        self.damage = damage
        self.healthSent = healthSent
    }
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

    public var seconds: Int { durationTicks * Rules.standard.tickMilliseconds / 1000 }

    public init(mode: GameMode, mapID: String, won: Bool, durationTicks: Int, livesLeft: Int, livesLost: Int,
                maxIncome: Int, creepsSent: Int, creepsKilled: Int, towersBuilt: Int, builtUltimate: Bool,
                sentColossus: Bool, samples: [GameSample], date: Date, opponentName: String? = nil,
                damageDealt: Int? = nil, healthSent: Int? = nil, playerNames: [String]? = nil, me: Int? = nil) {
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

    public init(me: Int, mode: GameMode) {
        self.me = me
        self.mode = mode
    }

    /// Call after every tick with the events of that tick.
    public mutating func observe(_ game: Game) {
        let board = game.players[me]
        maxIncome = max(maxIncome, board.income)
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
                           playerNames: playerNames ?? game.players.map(\.name), me: me)
    }

    private func sample(_ game: Game) -> GameSample? {
        guard let opponent = game.opponent(of: me) ?? game.players.indices.first(where: { $0 != me }) else { return nil }
        let board = game.players[me], other = game.players[opponent]
        return GameSample(tick: game.tick, myIncome: board.income, opponentIncome: other.income,
                          myLives: max(0, board.lives), opponentLives: max(0, other.lives),
                          myDamage: board.damageDealt, opponentDamage: other.damageDealt,
                          myHealthSent: board.healthSent, opponentHealthSent: other.healthSent,
                          players: game.players.map {
                              PlayerSample(income: $0.income, lives: max(0, $0.lives), damage: $0.damageDealt,
                                           healthSent: $0.healthSent)
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
    public var builtUltimate = false
    public var sentColossus = false
    public var mapsWon: Set<String> = []
    public var totalTicks = 0
    /// Fastest wins against the computer per level (raw value of `Bot.Level`), at most `leaderboardSize`.
    public var leaderboard: [String: [LeaderboardEntry]] = [:]
    /// The last game, for the evaluation after the game.
    public var lastGame: GameSummary?

    public static let leaderboardSize = 10
    /// A win in at most this many seconds of play counts as a fast win.
    public static let fastWinSeconds = 8 * 60

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
                let entry = LeaderboardEntry(name: playerName, mapID: game.mapID, durationTicks: game.durationTicks,
                                             livesLeft: game.livesLeft, date: game.date)
                var list = leaderboard[level.rawValue, default: []]
                list.append(entry)
                list.sort(by: LeaderboardEntry.ranked)
                list = Array(list.prefix(Self.leaderboardSize))
                leaderboard[level.rawValue] = list
                place = list.firstIndex(of: entry).map { $0 + 1 }
            }
        case .online:
            onlineGames += 1
            if game.won { onlineWins += 1 }
        case let .computerGroup(level, _):
            // Count for the level as well (only the leaderboard is for one-on-one games).
            gamesByLevel[level.rawValue, default: 0] += 1
            if game.won { winsByLevel[level.rawValue, default: 0] += 1 }
        }
        if game.won {
            wins += 1
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
            mapsWon.insert(game.mapID)
            if game.livesLost == 0 { flawlessWins += 1 }
            if game.livesLeft == 1 { closeWins += 1 }
            if game.seconds <= Self.fastWinSeconds { fastWins += 1 }
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
        let v = value(record)
        return tiers.filter { v >= $0 }.count
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
