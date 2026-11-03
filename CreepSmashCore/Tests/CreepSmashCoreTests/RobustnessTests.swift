import XCTest
import Foundation
@testable import CreepSmashCore

/// Values from outside (other devices, Game Center, saved files) are checked: wrong ones are ignored or
/// refused, they never stop the app.
final class RobustnessTests: XCTestCase {
    func testCommandsForUnknownPlayersOrPastTicksAreIgnored() {
        let game = Game(map: .blue, playerNames: ["A", "B"])
        game.schedule(ScheduledCommand(tick: game.tick, player: 7, sequence: 0, command: .surrender))
        game.schedule(ScheduledCommand(tick: game.tick, player: -1, sequence: 0, command: .surrender))
        game.step()
        game.schedule(ScheduledCommand(tick: 0, player: 0, sequence: 0, command: .surrender))
        for _ in 0..<5 { game.step() }
        XCTAssertFalse(game.players[0].isDead)
        XCTAssertFalse(game.players[1].isDead)
    }

    func testStandardRulesArePlausibleOthersNot() {
        XCTAssertTrue(Rules.standard.isPlausible)
        var rules = Rules.standard
        rules.tickMilliseconds = 0
        XCTAssertFalse(rules.isPlausible)
        rules = .standard
        rules.waveSize = 1_000_000
        XCTAssertFalse(rules.isPlausible)
    }

    func testSetupWithImplausibleRulesIsRefused() {
        var rules = Rules.standard
        rules.incomeIntervalTicks = 0
        let setup = MatchSetup(mapID: "neon", rules: rules, names: ["A", "B"])
        XCTAssertNil(NetworkMatch(setup: setup, localPlayer: 1, links: [:]))
        XCTAssertNotNil(NetworkMatch(setup: MatchSetup(mapID: "neon", names: ["A", "B"]), localPlayer: 1, links: [:]))
    }

    func testNamesFromOtherDevicesAreShortened() {
        let long = String(repeating: "x", count: 500) + "\nyy"
        let match = NetworkMatch(setup: MatchSetup(mapID: "neon", names: ["A", long]), localPlayer: 0, links: [:])
        XCTAssertEqual(match?.setup.names[1].count, MatchSetup.maxNameLength)
    }

    func testDamagedSavedGameCannotContinue() throws {
        let match = LocalMatch(map: .named("rennbahn")!, playerName: "A", opponents: [.normal])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(match.saved)) as! [String: Any]
        var rules = json["rules"] as! [String: Any]
        rules["tickMilliseconds"] = 0
        json["rules"] = rules
        let damaged = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(damaged.canContinue)
        XCTAssertNil(LocalMatch(restoring: damaged))
        XCTAssertTrue(match.saved.canContinue)
    }
}
