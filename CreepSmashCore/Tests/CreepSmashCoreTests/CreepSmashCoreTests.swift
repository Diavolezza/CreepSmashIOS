import XCTest
@testable import CreepSmashCore

/// Test helpers: schedule commands directly and compute ticks.
final class TestDriver {
    let game: Game
    private var seq = 0

    init(players: Int = 2, rules: Rules = .original, map: GameMap = .originalBlue) {
        game = Game(map: map, playerNames: (0..<players).map { "P\($0)" }, rules: rules)
    }

    func run(until tick: Int) { while game.tick < tick && !game.isFinished { game.step() } }
    func run(ticks: Int) { run(until: game.tick + ticks) }

    /// Schedules a command for the next tick and computes that tick.
    @discardableResult
    func now(_ command: Command, player: Int = 0) -> [GameEvent] {
        seq += 1
        game.schedule(ScheduledCommand(tick: game.tick, player: player, sequence: seq, command: command))
        game.step()
        return game.events
    }

    func startGame() { run(until: game.rules.startTick + 1) }
}

extension Rules {
    /// Values of the Java original (starting credits 200) that the economy tests refer to.
    static var original: Rules {
        var r = Rules.standard
        r.startCredits = 200
        return r
    }

    static var rich: Rules {
        var r = Rules.standard
        r.startCredits = 1_000_000
        return r
    }
}

final class MapTests: XCTestCase {
    func testBlueMapParsesLikeOriginal() {
        let map = GameMap.originalBlue
        XCTAssertEqual(map.imageName, "map_blue.jpg")
        XCTAssertEqual(map.path.count, 75)
        XCTAssertEqual(map.path.first, GridPoint(x: 1, y: 15))
        XCTAssertEqual(map.path.last, GridPoint(x: 15, y: 1))
        XCTAssertTrue(map.blocked.isEmpty)
        XCTAssertFalse(map.isBuildable(GridPoint(x: 1, y: 15)), "path is not buildable")
        XCTAssertTrue(map.isBuildable(GridPoint(x: 0, y: 0)))
        XCTAssertFalse(map.isBuildable(GridPoint(x: 16, y: 0)), "outside")
    }

    func testCommentsAndBlockedCells() throws {
        let map = try GameMap.parse(name: "t", text: """
        # Kommentar, mit Komma
        bild.png
        SET_ALPHA_BACKGROUND_COLOR:OFF
        3;4
        0,0
        0,1
        """)
        XCTAssertEqual(map.imageName, "bild.png")
        XCTAssertEqual(map.path, [GridPoint(x: 0, y: 0), GridPoint(x: 0, y: 1)])
        XCTAssertEqual(map.blocked, [GridPoint(x: 3, y: 4)])
        XCTAssertFalse(map.isBuildable(GridPoint(x: 3, y: 4)))
    }

    func testPositionInterpolatesInMilliPixels() {
        let map = GameMap.originalBlue  // (1,15) -> (1,14): upwards
        XCTAssertEqual(map.position(segment: 0, step: 0).x, 30_000)
        XCTAssertEqual(map.position(segment: 0, step: 0).y, 310_000)
        XCTAssertEqual(map.position(segment: 0, step: 500_000).y, 300_000)
    }

    func testIsqrt() {
        for n in [0, 1, 2, 3, 4, 15, 16, 17, 999_999, 1_000_000, 123_456_789_012] {
            let r = isqrt(n)
            XCTAssertLessThanOrEqual(r * r, n)
            XCTAssertGreaterThan((r + 1) * (r + 1), n)
        }
    }
}

final class EconomyTests: XCTestCase {
    func testIncomeIsPaidAtStartAndEvery15Seconds() {
        let d = TestDriver()
        let rules = d.game.rules
        d.run(until: rules.startTick)
        XCTAssertEqual(d.game.players[0].credits, 200)
        d.run(ticks: 1)
        XCTAssertEqual(d.game.players[0].credits, 400, "first income payment at start")
        d.run(until: rules.startTick + rules.incomeIntervalTicks)
        XCTAssertEqual(d.game.players[0].credits, 400)
        d.run(ticks: 1)
        XCTAssertEqual(d.game.players[0].credits, 600)
    }

    func testCommandsBeforeStartAreRejected() {
        let d = TestDriver()
        let events = d.now(.buildTower(kind: .basic, cell: GridPoint(x: 0, y: 0)))
        XCTAssertTrue(events.contains { if case .commandRejected(_, _, .notStarted) = $0 { return true }; return false })
        XCTAssertTrue(d.game.players[0].towers.isEmpty)
    }

    func testSendingCreepsCostsCreditsAndRaisesIncome() {
        let d = TestDriver()
        d.startGame()
        d.now(.sendCreeps(type: .mercury, count: 1))
        XCTAssertEqual(d.game.players[0].credits, 350)
        XCTAssertEqual(d.game.players[0].income, 205)
        XCTAssertEqual(d.game.players[1].creeps.count, 1)
        XCTAssertEqual(d.game.players[1].creeps[0].sender, 0)
    }

    func testWaveIsLimitedByCreditsAndWaveSize() {
        let d = TestDriver()
        d.startGame()
        d.now(.sendCreeps(type: .mercury, count: 20))  // 400 credits -> 8 creeps
        XCTAssertEqual(d.game.players[1].creeps.count, 8)
        XCTAssertEqual(d.game.players[0].credits, 0)
        let ticks = d.game.players[1].creeps.map(\.activeFromTick)
        XCTAssertEqual(ticks, Array(stride(from: ticks[0], to: ticks[0] + 8 * 3, by: 3)))

        let rich = TestDriver(rules: .rich)
        rich.startGame()
        rich.now(.sendCreeps(type: .mercury, count: 50))
        XCTAssertEqual(rich.game.players[1].creeps.count, 20)
    }

    func testNotEnoughCreditsIsRejected() {
        let d = TestDriver()
        d.startGame()
        let events = d.now(.sendCreeps(type: .ray, count: 1))
        XCTAssertTrue(events.contains { if case .commandRejected(_, _, .notEnoughCredits) = $0 { return true }; return false })
        XCTAssertEqual(d.game.players[0].credits, 400)
    }
}

final class CreepTests: XCTestCase {
    func testCreepWalksPathTakesLifeAndRestartsAtOpponent() {
        let d = TestDriver()
        d.startGame()
        d.now(.sendCreeps(type: .mercury, count: 1))
        // 74 segments of 1000 steps each at speed 70 -> reaches the end after about 1057 ticks.
        d.run(ticks: 1050)
        XCTAssertEqual(d.game.players[1].lives, 20)
        d.run(ticks: 20)
        XCTAssertEqual(d.game.players[1].lives, 19)
        XCTAssertEqual(d.game.players[0].lives, 20, "sender loses nothing")
        XCTAssertEqual(d.game.players[0].livesTaken, 1)
        XCTAssertEqual(d.game.players[1].creeps.count, 1, "with 2 players the creep walks again on the opponent's board")
        XCTAssertEqual(d.game.players[1].creeps[0].segment, 0)
    }

    func testRegeneration() {
        let d = TestDriver(rules: .rich)
        d.startGame()
        d.now(.sendCreeps(type: .zeus, count: 1))
        d.game.players[1].creeps[0].health -= 10_000
        d.run(ticks: 1)
        XCTAssertEqual(d.game.players[1].creeps[0].health, 1_500_000 - 9_500)
    }

    func testPlayerDiesAndGameEnds() {
        var rules = Rules.rich
        rules.startLives = 2
        let d = TestDriver(rules: rules)
        d.startGame()
        d.now(.sendCreeps(type: .expressRaptor, count: 2))
        d.run(ticks: 1_000)
        XCTAssertTrue(d.game.players[1].isDead)
        XCTAssertTrue(d.game.isFinished)
        XCTAssertEqual(d.game.winner, 0)
        XCTAssertEqual(d.game.players[0].rank, 1)
        XCTAssertEqual(d.game.players[1].rank, 2)
    }
}

final class TowerTests: XCTestCase {
    /// Cell next to the start of the path (1,15) -> (1,14) ...
    let besideStart = GridPoint(x: 0, y: 14)

    func testBuildRulesAndBuildTime() {
        let d = TestDriver()
        d.startGame()
        var events = d.now(.buildTower(kind: .basic, cell: GridPoint(x: 1, y: 14)))
        XCTAssertTrue(events.contains { if case .commandRejected(_, _, .cellNotBuildable) = $0 { return true }; return false })
        d.now(.buildTower(kind: .basic, cell: besideStart))
        XCTAssertEqual(d.game.players[0].credits, 350)
        events = d.now(.buildTower(kind: .basic, cell: besideStart))
        XCTAssertTrue(events.contains { if case .commandRejected(_, _, .cellOccupied) = $0 { return true }; return false })
        XCTAssertFalse(d.game.players[0].towers[0].activity.isReady)
        d.run(ticks: d.game.rules.actionTicks)
        XCTAssertTrue(d.game.players[0].towers[0].activity.isReady)
    }

    func testUpgradeAndSell() {
        let d = TestDriver(rules: .rich)
        d.startGame()
        d.now(.buildTower(kind: .basic, cell: besideStart))
        d.run(ticks: 40)
        let id = d.game.players[0].towers[0].id
        let before = d.game.players[0].credits
        d.now(.upgradeTower(id: id))
        XCTAssertEqual(d.game.players[0].credits, before - 100)
        d.run(ticks: 40)
        XCTAssertEqual(d.game.players[0].towers[0].level, 2)
        XCTAssertEqual(d.game.players[0].towers[0].totalPrice, 150)
        d.now(.sellTower(id: id))
        d.run(ticks: 40)
        XCTAssertTrue(d.game.players[0].towers.isEmpty)
        XCTAssertEqual(d.game.players[0].credits, before - 100 + 112, "75 % of 150, rounded down")
    }

    func testNoShotsWhileUpgrading() {
        let d = TestDriver(rules: .rich)
        d.startGame()
        d.now(.buildTower(kind: .speed, cell: besideStart), player: 1)
        d.run(ticks: 40)
        let id = d.game.players[1].towers[0].id
        func shots(_ events: [GameEvent]) -> Int {
            events.reduce(0) { n, e in if case .laserShot(1, id, _, _) = e { return n + 1 }; return n }
        }
        d.now(.sendCreeps(type: .demeter, count: 1), player: 0)
        var count = shots(d.now(.upgradeTower(id: id), player: 1))
        // The upgrade takes actionTicks steps including the one of the command; in the last one the
        // tower is ready again and may fire.
        for _ in 1..<(d.game.rules.actionTicks - 1) { d.game.step(); count += shots(d.game.events) }
        XCTAssertEqual(count, 0, "no shots while upgrading")
        XCTAssertEqual(d.game.players[1].towers[0].level, 1)
        count = 0
        for _ in 0..<40 { d.game.step(); count += shots(d.game.events) }
        XCTAssertEqual(d.game.players[1].towers[0].level, 2)
        XCTAssertGreaterThan(count, 0, "fires again after the upgrade")
    }

    func testLaserKillsCreepAndPaysBounty() {
        let d = TestDriver(rules: .rich)
        d.startGame()
        d.now(.buildTower(kind: .speed, cell: besideStart), player: 1)
        d.run(ticks: 40)
        let credits = d.game.players[1].credits
        d.now(.sendCreeps(type: .mercury, count: 1), player: 0)
        d.run(ticks: 60)
        XCTAssertTrue(d.game.players[1].creeps.isEmpty, "300 health, 225 damage per shot -> 2 hits")
        XCTAssertEqual(d.game.players[1].credits, credits + 5)
    }

    func testSlowTowerSlowsButNotImmuneCreeps() {
        let d = TestDriver(rules: .rich)
        d.startGame()
        d.now(.buildTower(kind: .slow, cell: besideStart), player: 1)
        d.run(ticks: 40)
        d.now(.sendCreeps(type: .ray, count: 1), player: 0)     // immune
        d.now(.sendCreeps(type: .demeter, count: 1), player: 0)
        d.run(ticks: 30)
        let ray = d.game.players[1].creeps.first { $0.type == .ray }!
        let demeter = d.game.players[1].creeps.first { $0.type == .demeter }!
        XCTAssertEqual(ray.speed, 65_000)
        XCTAssertEqual(demeter.speed, 42_000, "60 * (1 - 0.3)")
        XCTAssertGreaterThan(demeter.slowTicks, 0)
    }

    func testSplashHitsSeveralCreeps() {
        let d = TestDriver(rules: .rich)
        d.startGame()
        d.now(.buildTower(kind: .splash, cell: besideStart), player: 1)
        d.run(ticks: 40)
        var splashCount = 0
        func collect(_ events: [GameEvent]) {
            for case let .laserShot(_, _, _, splash) in events { splashCount = max(splashCount, splash.count) }
        }
        collect(d.now(.sendCreeps(type: .largeManta, count: 3), player: 0))
        for _ in 0..<60 { d.game.step(); collect(d.game.events) }
        XCTAssertEqual(splashCount, 2, "all three creeps are within the splash radius")
        XCTAssertTrue(d.game.players[1].creeps.allSatisfy { $0.health < 3_500 })
    }

    func testRocketFliesAndExplodes() {
        let d = TestDriver(rules: .rich)
        d.startGame()
        d.now(.buildTower(kind: .rocket, cell: besideStart), player: 1)
        d.run(ticks: 40)
        var launched = false, exploded = false
        var events = d.now(.sendCreeps(type: .largeManta, count: 1), player: 0)
        for _ in 0..<200 {
            for e in events {
                if case .rocketLaunched = e { launched = true }
                if case .explosion = e { exploded = true }
            }
            d.game.step()
            events = d.game.events
        }
        XCTAssertTrue(launched)
        XCTAssertTrue(exploded)
        XCTAssertTrue(d.game.players[1].creeps.isEmpty || d.game.players[1].creeps[0].health < 3_500)
    }

    func testStrategiesPickAsNamed() {
        let d = TestDriver(rules: .rich)
        d.startGame()
        d.now(.sendCreeps(type: .mercury, count: 1), player: 0)
        d.now(.sendCreeps(type: .largeManta, count: 1), player: 0)
        d.run(ticks: 30)
        var tower = Tower(id: 999, kind: .ultimate, cell: GridPoint(x: 3, y: 10), activity: .ready,
                          strategy: .strongest, totalPrice: 0)
        XCTAssertEqual(d.game.players[1].creeps.count, 2)
        tower.strategy = .strongest
        d.game.players[1].towers = [tower]
        d.run(ticks: 1)
        XCTAssertEqual(d.game.players[1].creeps.map(\.type), [.mercury], "Strongest hits the Manta")

        d.now(.sendCreeps(type: .largeManta, count: 1), player: 0)
        d.run(ticks: 30)
        tower = d.game.players[1].towers[0]
        tower.strategy = .weakest
        tower.cooldown = 0
        d.game.players[1].towers = [tower]
        d.run(ticks: 1)
        XCTAssertEqual(d.game.players[1].creeps.map(\.type), [.largeManta], "Weakest hits the Mercury")
    }
}

final class DeterminismTests: XCTestCase {
    /// Two instances with the same commands (in a different insertion order) must stay identical.
    func testSameCommandsGiveSameChecksums() {
        func play(reversed: Bool) -> [UInt64] {
            let game = Game(map: .originalBlue, playerNames: ["A", "B"], rules: .rich)
            var commands: [ScheduledCommand] = []
            var s = 0
            func add(_ tick: Int, _ p: Int, _ c: Command) { s += 1; commands.append(.init(tick: tick, player: p, sequence: s, command: c)) }
            add(120, 0, .buildTower(kind: .splash, cell: GridPoint(x: 0, y: 14)))
            add(120, 1, .buildTower(kind: .rocket, cell: GridPoint(x: 0, y: 14)))
            add(121, 1, .buildTower(kind: .slow, cell: GridPoint(x: 2, y: 13)))
            add(130, 0, .sendCreeps(type: .largeManta, count: 10))
            add(130, 1, .sendCreeps(type: .mako, count: 20))
            add(400, 0, .sendCreeps(type: .ray, count: 5))
            add(500, 1, .buildTower(kind: .speed, cell: GridPoint(x: 6, y: 13)))
            for c in (reversed ? commands.reversed() : commands) { game.schedule(c) }
            var sums: [UInt64] = []
            for _ in 0..<3_000 { game.step(); if game.tick % 20 == 0 { sums.append(game.checksum()) } }
            return sums
        }
        let a = play(reversed: false)
        XCTAssertEqual(a, play(reversed: true))
        XCTAssertEqual(Set(a).count, a.count, "state changes continuously")
    }

    func testBotsPlayAFullGame() {
        let match = LocalMatch(map: .blue, playerName: "Mensch", opponents: [.hard])
        // The "Mensch" (human) player also gets a bot so that the game is actually played.
        var human = Bot(player: 0, level: .normal, map: .blue)
        var sent = 0, built = 0
        while !match.game.isFinished && match.game.tick < 40_000 {
            for c in human.think(game: match.game) { match.issue(c) }
            match.advance()
            for e in match.game.events {
                if case .creepsSent = e { sent += 1 }
                if case .towerBuilt = e { built += 1 }
            }
        }
        XCTAssertGreaterThan(sent, 10)
        XCTAssertGreaterThan(built, 4)
        print("Bot game: tick \(match.game.tick), finished: \(match.game.isFinished), winner: \(String(describing: match.game.winner)), lives: \(match.game.players.map(\.lives)), income: \(match.game.players.map(\.income)), towers: \(match.game.players.map(\.towers.count))")
    }
}

final class AllMapsTests: XCTestCase {
    func testAllBuiltInMapsParseAndRun() {
        XCTAssertEqual(GameMap.all.count, 14)
        XCTAssertEqual(Set(GameMap.all.map(\.id)).count, 14)
        for map in GameMap.all {
            XCTAssertFalse(map.imageName.isEmpty, map.id)
            XCTAssertGreaterThanOrEqual(map.path.count, 20, map.id)
            // A bot-vs-bot game runs for a few minutes on every map without errors.
            let match = LocalMatch(map: map, playerName: "A", opponents: [.normal])
            var bot = Bot(player: 0, level: .normal, map: map)
            for _ in 0..<4_000 where !match.game.isFinished {
                for c in bot.think(game: match.game) { match.issue(c) }
                match.advance()
            }
            XCTAssertGreaterThan(match.game.players[0].towers.count, 0, map.id)
        }
    }

    func testSkippedCellsOnStraightsBelongToPath() throws {
        let map = try GameMap.parse(name: "t", text: "bild.png\n0,5\n0,2\n3,2\n")
        XCTAssertTrue(map.pathCells.contains(GridPoint(x: 0, y: 4)))
        XCTAssertFalse(map.isBuildable(GridPoint(x: 1, y: 2)))
    }

    func testSpecialSectionsOfTheMaps() throws {
        XCTAssertEqual(GameMap.blue.features, [])
        XCTAssertEqual(GameMap.named("rennbahn")?.features, [.fastLanes, .loops])
        XCTAssertEqual(GameMap.named("wurmloch")?.features, [.jumps])
        XCTAssertEqual(GameMap.named("polarlicht")?.features, [.uTurns])
        XCTAssertEqual(GameMap.named("kreuzung")?.features, [.loops])
        XCTAssertEqual(GameMap.named("pendel")?.features, [.fastLanes, .uTurns])
        XCTAssertEqual(GameMap.named("asteroiden")?.features, [.diagonals])
        XCTAssertEqual(GameMap.named("stromschnellen")?.features, [.fastLanes])
        // The cells a jump flies over stay free; the cells a fast lane skips do not.
        let wormhole = try XCTUnwrap(GameMap.named("wurmloch"))
        XCTAssertTrue(wormhole.isBuildable(GridPoint(x: 8, y: 6)))
        let rapids = try XCTUnwrap(GameMap.named("stromschnellen"))
        XCTAssertFalse(rapids.isBuildable(GridPoint(x: 13, y: 5)))
    }

    func testCreepsAreFasterOnAFastLane() throws {
        // Same distance (8 cells), once cell by cell and once as a fast lane with a point every 4 cells.
        let slow = try GameMap.parse(name: "s", text: "b.png\n" + (0...8).map { "\($0),5" }.joined(separator: "\n"))
        let fast = try GameMap.parse(name: "f", text: "b.png\n0,5\n4,5\n8,5\n")
        func ticksToCross(_ map: GameMap) -> Int {
            let game = Game(map: map, playerNames: ["A", "B"])
            while !game.isStarted { game.step() }
            game.schedule(ScheduledCommand(tick: game.tick, player: 0, sequence: 0, command: .sendCreeps(type: .mercury, count: 1)))
            let lives = game.players[1].lives
            var ticks = 0
            while game.players[1].lives == lives && ticks < 2_000 { game.step(); ticks += 1 }
            return ticks
        }
        let slowTicks = ticksToCross(slow), fastTicks = ticksToCross(fast)
        XCTAssertLessThan(fastTicks * 3, slowTicks, "slow \(slowTicks), fast \(fastTicks)")
    }
}
