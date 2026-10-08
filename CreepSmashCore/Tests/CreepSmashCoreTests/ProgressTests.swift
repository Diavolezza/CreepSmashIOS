import XCTest
@testable import CreepSmashCore

final class ProgressTests: XCTestCase {
    private func summary(won: Bool, level: Bot.Level = .normal, map: String = "blue", seconds: Int = 600,
                         livesLeft: Int = 12, livesLost: Int = 8, kills: Int = 50) -> GameSummary {
        GameSummary(mode: .computer(level), mapID: map, won: won, durationTicks: seconds * 20, livesLeft: livesLeft,
                    livesLost: livesLost, maxIncome: 2_000, creepsSent: 40, creepsKilled: kills, towersBuilt: 12,
                    builtUltimate: false, sentColossus: false, samples: [], date: Date(timeIntervalSince1970: 0))
    }

    func testGroupGamesCountForTheirLevelButNotTheLeaderboard() {
        var record = PlayerRecord()
        let group = GameSummary(mode: .computerGroup(.normal, opponents: 3), mapID: "blue", won: true,
                                durationTicks: 12_000, livesLeft: 10, livesLost: 10, maxIncome: 2_000, creepsSent: 40,
                                creepsKilled: 50, towersBuilt: 12, builtUltimate: false, sentColossus: false,
                                samples: [], date: Date(timeIntervalSince1970: 0))
        record.add(group, playerName: "Me")
        record.add(summary(won: false, level: .normal), playerName: "Me")
        XCTAssertEqual(record.gamesByLevel["normal"], 2)
        XCTAssertEqual(record.winsByLevel["normal"], 1)
        XCTAssertNil(record.leaderboard["normal"], "only one-on-one wins enter the leaderboard")
    }

    func testStatsOfARealGame() {
        let match = LocalMatch(map: .neon, playerName: "Me", opponents: [.easy])
        var me = Bot(player: 0, level: .hard, map: .neon)
        var stats = GameStats(me: 0, mode: .computer(.easy))
        while !match.game.isFinished && match.game.tick < 40_000 {
            for c in me.think(game: match.game) { match.issue(c) }
            match.advance()
            stats.observe(match.game)
        }
        let s = stats.summary(game: match.game, won: match.game.winner == 0)
        XCTAssertTrue(s.won)
        XCTAssertGreaterThan(s.creepsSent, 0)
        XCTAssertGreaterThan(s.creepsKilled, 0)
        XCTAssertGreaterThan(s.towersBuilt, 0)
        XCTAssertEqual(s.livesLeft, match.game.players[0].lives)
        XCTAssertEqual(s.livesLost, Rules.standard.startLives - s.livesLeft)
        XCTAssertFalse(s.samples.isEmpty)
        XCTAssertEqual(s.samples.first?.myIncome, Rules.standard.startIncome)
        // The course ends with the final state.
        XCTAssertEqual(s.samples.last?.tick, match.game.tick)
        XCTAssertEqual(s.samples.last?.opponentLives, 0)
        XCTAssertGreaterThan(s.damageDealt ?? 0, 0)
        XCTAssertGreaterThan(s.healthSent ?? 0, 0)
        XCTAssertEqual(s.samples.last?.myDamage, s.damageDealt)
        // Every player is recorded on his own, so a course does not jump when the next opponent changes.
        XCTAssertEqual(s.samples.last?.players?.count, match.game.players.count)
        XCTAssertEqual(s.samples.last?.players?[0].damage, s.damageDealt)
        XCTAssertEqual(s.me, 0)
    }

    func testTieredAchievementsAndStreak() {
        var record = PlayerRecord()
        let first = record.add(summary(won: true), playerName: "A")
        XCTAssertTrue(first.unlocked.contains { $0.id == "wins" && $0.tier == 1 })
        for _ in 0..<8 { record.add(summary(won: true), playerName: "A") }
        let tenth = record.add(summary(won: true), playerName: "A")
        XCTAssertTrue(tenth.unlocked.contains { $0.id == "wins" && $0.tier == 2 })
        XCTAssertTrue(tenth.unlocked.contains { $0.id == "games" && $0.tier == 1 })
        XCTAssertEqual(record.bestStreak, 10)
        record.add(summary(won: false), playerName: "A")
        XCTAssertEqual(record.currentStreak, 0)
        XCTAssertEqual(record.bestStreak, 10)
        let wins = Achievement.all.first { $0.id == "wins" }!
        XCTAssertEqual(wins.tier(in: record), 2)
        XCTAssertEqual(wins.nextThreshold(in: record), 100)
    }

    func testSpecialWins() {
        var record = PlayerRecord()
        let out = record.add(summary(won: true, level: .hard, seconds: 300, livesLeft: 20, livesLost: 0), playerName: "A")
        let ids = Set(out.unlocked.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["wins", "winsHard", "flawless", "fastWin"]))
        let close = record.add(summary(won: true, livesLeft: 1, livesLost: 19), playerName: "A")
        XCTAssertTrue(close.unlocked.contains { $0.id == "closeCall" })
        for map in GameMap.all.map(\.id) { record.add(summary(won: true, map: map), playerName: "A") }
        XCTAssertEqual(Achievement.all.first { $0.id == "allMaps" }!.tier(in: record), 1)
    }

    func testLeaderboardKeepsTheFastestWins() {
        var record = PlayerRecord()
        for s in [700, 500, 900, 400] { record.add(summary(won: true, seconds: s), playerName: "A") }
        record.add(summary(won: false, seconds: 100), playerName: "A")
        let board = record.leaderboard[Bot.Level.normal.rawValue]!
        XCTAssertEqual(board.map(\.seconds), [400, 500, 700, 900])
        let out = record.add(summary(won: true, seconds: 450), playerName: "B")
        XCTAssertEqual(out.leaderboardPlace, 2)
        for _ in 0..<20 { record.add(summary(won: true, seconds: 1000), playerName: "C") }
        XCTAssertEqual(record.leaderboard[Bot.Level.normal.rawValue]!.count, PlayerRecord.leaderboardSize)
        let slow = record.add(summary(won: true, seconds: 2000), playerName: "D")
        XCTAssertNil(slow.leaderboardPlace)
    }

    func testOlderRecordWithoutOpponentNameDecodes() throws {
        var record = PlayerRecord()
        record.add(summary(won: true), playerName: "A")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        var last = json["lastGame"] as! [String: Any]
        last.removeValue(forKey: "opponentName")
        json["lastGame"] = last
        let decoded = try JSONDecoder().decode(PlayerRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.lastGame?.opponentName)
    }

    func testRecordSurvivesEncoding() throws {
        var record = PlayerRecord()
        record.add(summary(won: true), playerName: "A")
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(PlayerRecord.self, from: data), record)
    }
}
