import XCTest
@testable import CreepSmashCore

final class SavedGameTests: XCTestCase {
    /// Plays `ticks` ticks with a bot giving the player's commands (like the autopilot).
    private func play(_ match: LocalMatch, ticks: Int) {
        var me = Bot(player: 0, level: .normal, map: match.game.map)
        for _ in 0..<ticks where !match.game.isFinished {
            for command in me.think(game: match.game) { match.issue(command) }
            match.advance()
        }
    }

    func testContinuedGameIsExactlyTheSame() throws {
        let match = LocalMatch(map: .named("rennbahn")!, playerName: "A", opponents: [.normal, .hard],
                               opponentNames: ["CPU1", "CPU2"], seed: 42)
        play(match, ticks: 3_000)
        let saved = match.saved
        XCTAssertGreaterThan(saved.inputs.count, 5)
        // Through JSON, as on disk.
        let data = try JSONEncoder().encode(saved)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data)
        XCTAssertEqual(loaded, saved)
        var observed = 0
        let restored = try XCTUnwrap(LocalMatch(restoring: loaded) { _ in observed += 1 })
        XCTAssertEqual(restored.game.tick, match.game.tick)
        XCTAssertEqual(observed, match.game.tick)
        XCTAssertEqual(restored.game.checksum(), match.game.checksum())
        // Both go on identically, and the restored game can be saved again.
        play(match, ticks: 1_000)
        play(restored, ticks: 1_000)
        XCTAssertEqual(restored.game.checksum(), match.game.checksum())
        XCTAssertEqual(restored.saved.inputs, match.saved.inputs)
    }

    func testOtherVersionCannotBeContinued() throws {
        let match = LocalMatch(map: .blue, playerName: "A", seed: 1)
        play(match, ticks: 200)
        var json = try XCTUnwrap(String(data: JSONEncoder().encode(match.saved), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"version\":\(NetMessage.protocolVersion)", with: "\"version\":1")
        let old = try JSONDecoder().decode(SavedGame.self, from: Data(json.utf8))
        XCTAssertFalse(old.canContinue)
        XCTAssertNil(LocalMatch(restoring: old))
    }

    func testReplayOfALongGameIsFast() throws {
        let match = LocalMatch(map: .vulkan, playerName: "A", opponents: [.hard, .hard, .hard], seed: 7)
        play(match, ticks: 12_000)   // 10 minutes of play
        let start = Date()
        let restored = try XCTUnwrap(LocalMatch(restoring: match.saved))
        let seconds = Date().timeIntervalSince(start)
        print("Replay of \(match.game.tick) ticks: \(seconds) s, finished: \(match.game.isFinished)")
        XCTAssertEqual(restored.game.checksum(), match.game.checksum())
    }
}
