import XCTest
@testable import CreepSmashCore

/// The computers should build pressure with strong waves, not mainly send masses of weak creeps.
final class BotPressureTests: XCTestCase {
    private struct Waves {
        var count = 0, creeps = 0, credits = 0, masses = 0
    }

    /// Four computers with playing styles play each other; returns per player what they sent.
    private func play(seed: UInt64, map: GameMap = .blue) -> [Waves] {
        let match = LocalMatch(map: map, playerName: "P0", opponents: [.normal, .hard, .normal], seed: seed)
        var pilot = Bot(player: 0, level: .hard, map: map, style: Bot.Style.varied(count: 4, seed: seed &+ 1)[3])
        var waves = Array(repeating: Waves(), count: 4)
        while !match.game.isFinished && match.game.tick < 20 * 60 * 20 {
            for c in pilot.think(game: match.game) { match.issue(c) }
            match.advance()
            for case let .creepsSent(from, _, type, count) in match.game.events {
                waves[from].count += 1
                waves[from].creeps += count
                waves[from].credits += type.stats.price * count
                // A mass: more than six creeps of a type that costs less than a tenth of the income.
                if count > 6 && type.stats.price * 10 < match.game.players[from].income { waves[from].masses += 1 }
            }
        }
        return waves
    }

    func testComputersSendStrongWavesRatherThanMasses() {
        var total = Waves()
        for seed: UInt64 in [1, 2, 3] {
            for w in play(seed: seed) {
                total.count += w.count; total.creeps += w.creeps; total.credits += w.credits; total.masses += w.masses
            }
        }
        // Masses are still sent when they get clearly more creeps through than a strong wave (before this
        // rule, with swarm-loving styles, about every fifth wave was one).
        let massShare = Double(total.masses) / Double(max(1, total.count))
        print("PRESSURE waves \(total.count) masses \(massShare)")
        XCTAssertLessThan(massShare, 0.15, "masses of weak creeps are the exception")
    }
}
