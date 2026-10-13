import XCTest
@testable import CreepSmashCore

/// Efficiency of the defense in the evaluation: damage per credit put into towers, and utilization.
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

    func testEfficiencyValuesArePlausible() {
        var lines: [String] = []
        for seed: UInt64 in [1, 2] {
            for s in play(seed: seed) {
                let spent = s.towerSpent ?? 0, value = s.towerValue ?? 0
                XCTAssertGreaterThan(spent, 0)
                // What stands at the end was paid for (selling refunds less than it cost).
                XCTAssertGreaterThanOrEqual(spent, value * 3 / 4)
                XCTAssertNotNil(s.damagePerCredit)
                XCTAssertTrue((1...1000).contains(s.towerBusyPermille ?? 0))
                lines.append("EFF won=\(s.won) dpc=\(s.damagePerCredit ?? -1) busy=\(s.towerBusyPermille ?? -1) spent=\(spent)")
            }
        }
        print(lines.joined(separator: "\n"))
    }
}
