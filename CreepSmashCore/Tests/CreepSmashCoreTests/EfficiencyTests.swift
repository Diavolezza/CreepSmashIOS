import XCTest
@testable import CreepSmashCore

/// Efficiency of the defense in the evaluation: effectiveness, utilization, share of the income, zombie towers.
final class EfficiencyTests: XCTestCase {
    /// Computers play each other; returns the summary of every player.
    private func play(seed: UInt64, map: GameMap = .blue) -> [GameSummary] {
        let match = LocalMatch(map: map, playerName: "P0", opponents: [.normal, .hard, .normal], seed: seed)
        var pilot = Bot(player: 0, level: .hard, map: map, style: Bot.Style.varied(count: 4, seed: seed &+ 1)[3])
        var stats = (0..<4).map { GameStats(me: $0, mode: .computer(.normal)) }
        while !match.game.isFinished && match.game.tick < 20 * 60 * 20 {
            for c in pilot.think(game: match.game) { match.issue(c) }
            match.advance()
            for i in stats.indices { stats[i].observe(match.game) }
        }
        return stats.map { $0.summary(game: match.game, won: match.game.winner == $0.me) }
    }

    func testDefenseRecordsArePlausible() {
        var lines: [String] = []
        for seed: UInt64 in [1, 2] {
            let summaries = play(seed: seed)
            for s in summaries {
                guard let d = s.myDefense else { return XCTFail("no defense record") }
                // Every device sees the same records for all players.
                XCTAssertEqual(s.defense, summaries[0].defense)
                XCTAssertGreaterThan(d.towerSpent, 0)
                XCTAssertGreaterThan(d.healthArrived, 0)
                XCTAssertLessThanOrEqual(d.healthStopped, d.healthArrived + 1_000_000, "regeneration aside, no more than arrived")
                XCTAssertTrue((0...1000).contains(d.stoppedPermille ?? -1))
                XCTAssertNotNil(d.utilizationPermille)
                XCTAssertTrue((1...1000).contains(d.towerSharePermille ?? -1))
                XCTAssertLessThanOrEqual(d.zombieValue, s.towerValue ?? 0)
                XCTAssertNotNil(s.samples.last?.players?.first?.capacity)
                lines.append("EFF won=\(s.won) stopped=\(d.stoppedPermille ?? -1) used=\(d.utilizationPermille ?? -1) share=\(d.towerSharePermille ?? -1) zombies=\(d.zombieTowers)/\(d.zombieValue)")
            }
        }
        print(lines.joined(separator: "\n"))
    }

    /// Towers of a player who is out no longer count as idle (they are not wasted, there is just nothing to do).
    func testTowersOfAPlayerWhoIsOutAreNoZombies() {
        for seed: UInt64 in [3, 4] {
            for s in play(seed: seed, map: GameMap.all[Int(seed) + 4]) where !s.won {
                XCTAssertLessThan(s.myDefense?.zombieTowers ?? 0, 4, "seed \(seed)")
            }
        }
    }
}
