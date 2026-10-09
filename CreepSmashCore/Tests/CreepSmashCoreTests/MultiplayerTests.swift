import XCTest
@testable import CreepSmashCore

final class MultiplayerTests: XCTestCase {
    private func game(players: Int) -> Game {
        let g = Game(map: .blue, playerNames: (0..<players).map { "P\($0)" })
        while !g.isStarted { g.step() }
        return g
    }

    private func run(_ g: Game, player: Int, _ command: Command) {
        g.schedule(ScheduledCommand(tick: g.tick, player: player, sequence: 1, command: command))
        g.step()
    }

    func testNextModeSendsToTheNextPlayerInTheRing() {
        let g = game(players: 4)
        run(g, player: 3, .sendCreeps(type: .mercury, count: 1))
        XCTAssertEqual(g.players[0].creeps.count, 1)
        XCTAssertEqual(g.opponents(of: 3), [0, 1, 2])
    }

    func testAllModeSendsToEveryOpponentAndCountsPerRecipient() {
        let g = game(players: 4)
        run(g, player: 0, .setSendMode(.all))
        XCTAssertEqual(g.recipientCount(of: 0), 3)
        while g.ticksUntilIncome < 2 { g.step() }  // no income payment in between
        let credits = g.players[0].credits, income = g.players[0].income
        run(g, player: 0, .sendCreeps(type: .mercury, count: 1))
        XCTAssertEqual((1...3).map { g.players[$0].creeps.count }, [1, 1, 1])
        XCTAssertEqual(credits - g.players[0].credits, 3 * CreepType.mercury.stats.price)
        XCTAssertEqual(g.players[0].income - income, 3 * CreepType.mercury.stats.income)
    }

    func testRandomModeIsDeterministicAndHitsALivingOpponent() {
        let a = game(players: 4), b = game(players: 4)
        for g in [a, b] {
            run(g, player: 1, .setSendMode(.random))
            for _ in 0..<12 { run(g, player: 1, .sendCreeps(type: .mercury, count: 1)) }
        }
        XCTAssertEqual(a.checksum(), b.checksum())
        XCTAssertEqual(a.players[1].creeps.count, 0)
        XCTAssertEqual([0, 2, 3].map { a.players[$0].creeps.count }.reduce(0, +), 12)
        // Over a dozen draws more than one opponent gets creeps.
        XCTAssertGreaterThan([0, 2, 3].filter { a.players[$0].creeps.count > 0 }.count, 1)
    }

    func testFourPlayerGameAgainstComputersFinishes() {
        let match = LocalMatch(map: .neon, playerName: "Me", opponents: [.easy, .normal, .hard])
        var me = Bot(player: 0, level: .normal, map: .neon)
        while !match.game.isFinished && match.game.tick < 60_000 {
            for c in me.think(game: match.game) { match.issue(c) }
            match.advance()
        }
        XCTAssertTrue(match.game.isFinished)
        XCTAssertEqual(match.game.players.compactMap(\.rank).sorted(), [1, 2, 3, 4])
    }

    func testComputerOpponentsGetDifferentStyles() {
        let styles = Bot.Style.varied(count: 3, seed: 42)
        XCTAssertEqual(Set(styles.compactMap(\.favorite)).count, 3, "every opponent likes another tower")
        XCTAssertEqual(styles, Bot.Style.varied(count: 3, seed: 42), "the same seed gives the same styles")
        // Two styled bots on the same map build differently within the first minute.
        let match = LocalMatch(map: .neon, playerName: "Me", opponents: [.normal, .normal, .normal], seed: 7)
        while match.game.tick < 1_400 { match.advance() }
        let layouts = (1...3).map { p in Set(match.game.players[p].towers.map { "\($0.kind.rawValue)@\($0.cell.x),\($0.cell.y)" }) }
        XCTAssertGreaterThan(Set(layouts).count, 1, "the computers do not all build the same")
    }
}
