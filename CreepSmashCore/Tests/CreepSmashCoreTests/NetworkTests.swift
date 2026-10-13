import XCTest
import Foundation
@testable import CreepSmashCore

/// Simulated network: messages arrive after a fixed number of frames, in order.
final class FakeNetwork {
    var now = 0
    var latency: Int
    /// `data` nil: the connection was closed by the other side.
    fileprivate var queue: [(due: Int, to: LoopbackTransport, data: Data?)] = []
    private(set) var messagesSent = 0

    init(latency: Int) { self.latency = latency }

    func pair() -> (LoopbackTransport, LoopbackTransport) {
        let a = LoopbackTransport(network: self), b = LoopbackTransport(network: self)
        a.peer = b; b.peer = a
        return (a, b)
    }

    fileprivate func post(_ data: Data, to: LoopbackTransport) {
        messagesSent += 1
        queue.append((now + latency, to, data))
    }

    fileprivate func postClose(to: LoopbackTransport) {
        queue.append((now + latency, to, nil))
    }

    /// Delivers all due messages.
    func deliver() {
        while let i = queue.firstIndex(where: { $0.due <= now }) {
            let m = queue.remove(at: i)
            guard !m.to.isClosed else { continue }
            if let data = m.data { m.to.onReceive?(data) } else { m.to.closedByPeer() }
        }
    }
}

final class LoopbackTransport: Transport {
    let network: FakeNetwork
    weak var peer: LoopbackTransport?
    var onReceive: ((Data) -> Void)?
    var onClose: (() -> Void)?
    fileprivate(set) var isClosed = false

    init(network: FakeNetwork) { self.network = network }

    fileprivate func closedByPeer() {
        isClosed = true
        onClose?()
    }

    /// Messages sent while muted are lost (to make devices miss packets before a crash).
    var muted = false

    func send(_ data: Data) {
        guard !isClosed, !muted, let peer else { return }
        network.post(data, to: peer)
    }

    /// The network between the two ends breaks: both learn it at once.
    func cut() {
        guard !isClosed, let peer, !peer.isClosed else { return }
        isClosed = true
        peer.isClosed = true
        onClose?()
        peer.onClose?()
    }

    /// Like TCP: messages sent before arrive first, then the other side learns that the connection is closed.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        if let peer { network.postClose(to: peer) }
    }
}

final class NetworkTests: XCTestCase {
    /// Sets up a game via the lobby: the host "Anna", the guests in this order, then the computers.
    /// Returns one game per device, the host's first.
    private func connect(_ net: FakeNetwork, guests: [String] = ["Bert"], computers: [Bot.Level] = [],
                         map: String = "neon", rules: Rules = .standard, code: String = "ROUND") -> [NetworkMatch] {
        let lobby = HostLobby(mapID: map, rules: rules, name: "Anna", seats: 1 + guests.count + computers.count, code: code)
        var lobbies: [GuestLobby] = []
        var matches: [Int: NetworkMatch] = [:]
        for (index, name) in guests.enumerated() {
            let (a, b) = net.pair()
            lobby.add(a)
            let guest = GuestLobby(transport: b, name: name)
            guest.onResult = { if case let .ready(match) = $0 { matches[index] = match } }
            lobbies.append(guest)
            settle(net)                             // seats are taken in the order of arrival
        }
        for (k, level) in computers.enumerated() {
            lobby.setComputer(seat: 1 + guests.count + k, level: level)
        }
        let host = lobby.start(seed: 42)!
        settle(net)
        XCTAssertEqual(lobbies.count, guests.count)
        return [host] + guests.indices.map { matches[$0]! }
    }

    private func settle(_ net: FakeNetwork) {
        for _ in 0..<(3 * net.latency + 3) { net.now += 1; net.deliver() }
    }

    /// Runs all devices for some frames.
    private func run(_ net: FakeNetwork, _ matches: [NetworkMatch], frames: Int = 10) {
        for _ in 0..<frames {
            net.now += 1
            net.deliver()
            for m in matches { m.updatePause(); m.advance() }
        }
    }

    /// The connection of `match` to `player` (the guest's only connection is to the host, 0).
    private func link(_ match: NetworkMatch, to player: Int) -> LoopbackTransport {
        let links = Mirror(reflecting: match).children.first { $0.label == "links" }!.value as! [Int: Transport]
        return links[player] as! LoopbackTransport
    }

    /// Compares the games at the same tick: devices that are behind catch up first.
    private func assertSameGame(_ matches: [NetworkMatch], net: FakeNetwork? = nil,
                                file: StaticString = #filePath, line: UInt = #line) {
        if let net {
            let target = matches.map(\.game.tick).max()!
            for _ in 0..<500 where matches.contains(where: { $0.game.tick < target && !$0.game.isFinished }) {
                net.now += 1
                net.deliver()
                for m in matches where m.game.tick < target { m.advance() }
            }
        }
        let first = matches[0].game
        for m in matches.dropFirst() {
            XCTAssertEqual(m.game.tick, first.tick, file: file, line: line)
            XCTAssertEqual(m.game.checksum(), first.checksum(), file: file, line: line)
            XCTAssertEqual(m.game.winner, first.winner, file: file, line: line)
        }
    }

    // MARK: Lobby

    func testLobbyAgreesOnSetup() {
        let net = FakeNetwork(latency: 2)
        let devices = connect(net, map: "canyon")
        let (host, guest) = (devices[0], devices[1])
        XCTAssertEqual(host.setup, guest.setup)
        XCTAssertEqual(host.setup.names, ["Anna", "Bert"])
        XCTAssertEqual(host.localPlayer, 0)
        XCTAssertEqual(guest.localPlayer, 1)
        XCTAssertEqual(guest.game.map.id, "canyon")
    }

    func testLobbyRejectsOtherVersion() {
        let net = FakeNetwork(latency: 1)
        let (a, b) = net.pair()
        let lobby = HostLobby(mapID: "neon", name: "Anna")
        lobby.add(a)
        var reason: String?
        b.onReceive = { data in
            if case let .reject(r) = NetMessage.decode(data) { reason = r }
        }
        b.send(NetMessage.hello(protocolVersion: NetMessage.protocolVersion + 1, name: "Alt").encoded())
        settle(net)
        XCTAssertEqual(reason, LobbyFailure.otherVersion.rawValue)
        XCTAssertEqual(lobby.takenSeats, 1)
    }

    func testGuestsTakeTheFreeSeatsAndSeeTheLobby() {
        let net = FakeNetwork(latency: 1)
        let lobby = HostLobby(mapID: "neon", name: "Anna", seats: 4)
        lobby.setComputer(seat: 2, level: .hard)
        var guests: [GuestLobby] = []
        var failures: [LobbyFailure] = []
        for name in ["Bert", "Cleo", "Dora"] {
            let (a, b) = net.pair()
            lobby.add(a)
            let guest = GuestLobby(transport: b, name: name)
            guest.onResult = { if case let .failed(f) = $0 { failures.append(f) } }
            guests.append(guest)
            settle(net)
        }
        XCTAssertEqual(lobby.seats, [.human(name: "Anna"), .human(name: "Bert"), .computer(.hard), .human(name: "Cleo")])
        XCTAssertEqual(failures, [.full], "Dora finds no free seat")
        XCTAssertEqual(guests[1].info?.you, 3)
        XCTAssertEqual(guests[0].info?.seats, lobby.seats)
        // A guest leaves: the seat is free again, the others see it.
        guests[0].leave()
        settle(net)
        XCTAssertEqual(lobby.seats[1], .open)
        XCTAssertEqual(guests[1].info?.seats[1], .open)
        // Seats of guests cannot be given to computers.
        lobby.setComputer(seat: 3, level: .easy)
        XCTAssertEqual(lobby.seats[3], .human(name: "Cleo"))
    }

    func testClosingTheLobbyTellsTheGuests() {
        let net = FakeNetwork(latency: 1)
        let lobby = HostLobby(mapID: "neon", name: "Anna")
        let (a, b) = net.pair()
        lobby.add(a)
        let guest = GuestLobby(transport: b, name: "Bert")
        var failure: LobbyFailure?
        guest.onResult = { if case let .failed(f) = $0 { failure = f } }
        settle(net)
        lobby.close()
        settle(net)
        XCTAssertEqual(failure, .closed)
    }

    func testQuickGameStartsWhenTheSecondPlayerArrives() {
        let net = FakeNetwork(latency: 1)
        let lobby = HostLobby(mapID: "neon", name: "Anna", seats: 2)
        lobby.startsWhenFull = true
        var host: NetworkMatch?, guest: NetworkMatch?
        lobby.onStart = { host = $0 }
        let (a, b) = net.pair()
        lobby.add(a)
        let guestLobby = GuestLobby(transport: b, name: "Bert")
        guestLobby.onResult = { if case let .ready(m) = $0 { guest = m } }
        settle(net)
        XCTAssertNotNil(host)
        XCTAssertEqual(guest?.setup.names, ["Anna", "Bert"])
    }

    func testComputerSeatsBecomePlayersAfterThePeople() {
        let net = FakeNetwork(latency: 1)
        let devices = connect(net, guests: ["Bert"], computers: [.easy, .hard])
        XCTAssertEqual(devices[0].setup.names, ["Anna", "Bert", "CPU1", "CPU2"])
        XCTAssertEqual(devices[1].setup.computers, [nil, nil, .easy, .hard])
        XCTAssertEqual(devices[1].setup.seed, 42)
    }

    // MARK: Playing

    /// Computer opponents play for the people over the simulated network. All devices must compute
    /// the same game – even if one device is slower.
    private func playOut(guests: [String], computers: [Bot.Level] = [], latency: Int, slowGuest: Bool) {
        let net = FakeNetwork(latency: latency)
        var rules = Rules.standard
        rules.startLives = 3
        let devices = connect(net, guests: guests, computers: computers, rules: rules)
        let levels: [Bot.Level] = [.hard, .normal, .easy, .normal]
        var pilots = devices.map { Bot(player: $0.localPlayer, level: levels[$0.localPlayer], map: $0.game.map) }
        var waits = 0
        var frame = 0
        while !devices.allSatisfy(\.game.isFinished) && frame < 300_000 {
            frame += 1
            net.now += 1
            net.deliver()
            for (i, device) in devices.enumerated() {
                if slowGuest && i == devices.count - 1 && frame % 3 == 0 { continue }
                for c in pilots[i].think(game: device.game) { device.issue(c) }
                if !device.advance() && !device.game.isFinished && i == 0 { waits += 1 }
            }
        }
        XCTAssertTrue(devices.allSatisfy(\.game.isFinished))
        XCTAssertTrue(devices.allSatisfy { $0.status == .running })
        assertSameGame(devices)
        if slowGuest { XCTAssertGreaterThan(waits, 0, "The fast host must wait for the slow guest") }
    }

    func testBothDevicesComputeTheSameGame() {
        playOut(guests: ["Bert"], latency: 2, slowGuest: false)
    }

    func testSlowDeviceAndHighLatencyStayInSync() {
        playOut(guests: ["Bert"], latency: 9, slowGuest: true)
    }

    func testFourDevicesComputeTheSameGame() {
        playOut(guests: ["Bert", "Cleo", "Dora"], latency: 3, slowGuest: true)
    }

    func testTwoPeopleAndTwoComputersComputeTheSameGame() {
        playOut(guests: ["Bert"], computers: [.normal, .hard], latency: 2, slowGuest: false)
    }

    func testComputersPlayOnEveryDevice() {
        let net = FakeNetwork(latency: 2)
        let devices = connect(net, guests: ["Bert"], computers: [.hard])
        run(net, devices, frames: 600)
        XCTAssertFalse(devices[1].game.players[2].towers.isEmpty, "the computer builds")
        assertSameGame(devices, net: net)
    }

    func testCommandsIssuedWhileWaitingAreNotLost() {
        let net = FakeNetwork(latency: 10)
        let devices = connect(net)
        let (host, guest) = (devices[0], devices[1])
        // Host runs ahead until it has to wait, and then issues a command in every seventh frame.
        var issued = 0
        for frame in 0..<400 {
            net.now += 1
            net.deliver()
            if host.game.isStarted, issued < 3, frame % 7 == 0 {
                host.issue(.sendCreeps(type: .mercury, count: 1))
                issued += 1
            }
            host.advance()
            guest.advance()
        }
        XCTAssertEqual(issued, 3)
        XCTAssertEqual(guest.game.players[0].income, host.game.players[0].income)
        XCTAssertEqual(host.game.players[0].income, Rules.standard.startIncome + 3 * CreepType.mercury.stats.income)
    }

    func testCommandsOfOneGuestReachTheOtherGuests() {
        let net = FakeNetwork(latency: 2)
        let devices = connect(net, guests: ["Bert", "Cleo"])
        while !devices[2].game.isStarted { run(net, devices, frames: 1) }
        devices[2].issue(.sendCreeps(type: .mercury, count: 1))
        run(net, devices, frames: 40)
        for device in devices {
            XCTAssertEqual(device.game.players[2].income, Rules.standard.startIncome + CreepType.mercury.stats.income)
        }
        assertSameGame(devices, net: net)
    }

    // MARK: Leaving

    func testLeavingLetsTheOpponentWin() {
        let net = FakeNetwork(latency: 2)
        let devices = connect(net)
        let (host, guest) = (devices[0], devices[1])
        var events: [NetworkMatch.Event] = []
        host.onEvent = { events.append($0) }
        run(net, devices, frames: 150)
        guest.leave()
        XCTAssertEqual(guest.status, .left)
        run(net, [host], frames: 50)
        XCTAssertEqual(events, [.playerLeft(1)])
        XCTAssertEqual(host.status, .running)
        XCTAssertTrue(host.game.isFinished)
        XCTAssertEqual(host.game.winner, 0)
    }

    func testLostConnectionLetsTheOpponentWin() {
        let net = FakeNetwork(latency: 2)
        let devices = connect(net)
        let (host, guest) = (devices[0], devices[1])
        run(net, devices, frames: 150)
        link(guest, to: 0).close()                  // without the guest sending anything
        run(net, [host], frames: 50)
        XCTAssertEqual(host.game.winner, 0)
    }

    func testTheHostLeavingLetsTheGuestWin() {
        let net = FakeNetwork(latency: 2)
        let devices = connect(net, guests: ["Bert"], computers: [.easy])
        let (host, guest) = (devices[0], devices[1])
        var events: [NetworkMatch.Event] = []
        guest.onEvent = { events.append($0) }
        run(net, devices, frames: 150)
        host.leave()
        run(net, [guest], frames: 50)
        // Only computers are left besides the guest: the game goes on on the guest's device.
        XCTAssertEqual(events, [.playerLeft(0)])
        XCTAssertEqual(guest.status, .running)
        XCTAssertTrue(guest.game.players[0].isDead)
        XCTAssertFalse(guest.game.isFinished)
    }

    func testAGuestLeavingDoesNotStopTheOthers() {
        let net = FakeNetwork(latency: 2)
        let devices = connect(net, guests: ["Bert", "Cleo", "Dora"])
        var events: [NetworkMatch.Event] = []
        devices[3].onEvent = { events.append($0) }
        run(net, devices, frames: 150)
        link(devices[2], to: 0).close()             // Cleo's connection drops
        let others = [devices[0], devices[1], devices[3]]
        run(net, others, frames: 100)
        XCTAssertEqual(events, [.playerLeft(2)])
        for device in others {
            XCTAssertTrue(device.game.players[2].isDead)
            XCTAssertEqual(device.status, .running)
            XCTAssertFalse(device.waitingFor.contains(2))
        }
        assertSameGame(others, net: net)
        XCTAssertGreaterThan(devices[0].game.tick, 200, "the others go on")
    }

    func testWithoutACodeTheRoundEndsWhenTheHostLeaves() {
        let net = FakeNetwork(latency: 2)
        let devices = connect(net, guests: ["Bert", "Cleo"], code: "")
        run(net, devices, frames: 150)
        devices[0].leave()
        run(net, Array(devices.dropFirst()), frames: 20)
        XCTAssertEqual(devices[1].status, .hostGone)
        XCTAssertEqual(devices[2].status, .hostGone)
    }

    func testNobodyWaitsForAPlayerWhoIsOut() {
        let net = FakeNetwork(latency: 2)
        let devices = connect(net, guests: ["Bert", "Cleo"])
        run(net, devices, frames: 150)
        devices[2].issue(.surrender)
        run(net, devices, frames: 20)
        // Cleo is out and stops running (e.g. watches nothing); the others go on.
        let tick = devices[0].game.tick
        run(net, Array(devices.prefix(2)), frames: 100)
        XCTAssertGreaterThan(devices[0].game.tick, tick + 50)
        assertSameGame(Array(devices.prefix(2)), net: net)
    }

    func testDifferentStateIsDetected() {
        let net = FakeNetwork(latency: 1)
        let devices = connect(net, guests: ["Bert", "Cleo"])
        run(net, devices, frames: 150)
        devices[2].game.players[1].credits += 1     // corrupt the state on one device
        run(net, devices, frames: 60)
        for device in devices {
            if case .desynced = device.status {} else { XCTFail("not detected: \(device.status)") }
        }
    }

    // MARK: Pause

    /// Connected games with a shared, adjustable clock.
    private func pausable(_ net: FakeNetwork, guests: [String] = ["Bert"]) -> ([NetworkMatch], (TimeInterval) -> Void) {
        let devices = connect(net, guests: guests)
        var now = Date(timeIntervalSince1970: 1_000_000)
        for d in devices { d.clock = { now } }
        run(net, devices, frames: 100)
        return (devices, { now += $0 })
    }

    func testOnlyThePlayerWhoPausedCanGoOnAfterACountdown() {
        let net = FakeNetwork(latency: 2)
        let (devices, wait) = pausable(net, guests: ["Bert", "Cleo"])
        devices[1].pauseGame()
        run(net, devices)
        XCTAssertEqual(devices.map { $0.pause?.player }, [1, 1, 1])
        let ticks = devices.map(\.game.tick)
        run(net, devices, frames: 50)
        XCTAssertEqual(devices.map(\.game.tick), ticks, "no ticks during the pause")
        devices[0].resumeGame()                     // not the host's pause
        devices[2].resumeGame()
        run(net, devices)
        XCTAssertTrue(devices.allSatisfy { $0.pause?.resumesAt == nil })
        devices[1].resumeGame()
        run(net, devices)
        XCTAssertTrue(devices.allSatisfy { $0.pause?.resumesAt != nil }, "countdown on all devices")
        wait(NetworkMatch.resumeCountdown)
        run(net, devices, frames: 50)
        XCTAssertTrue(devices.allSatisfy { !$0.isPaused })
        XCTAssertGreaterThan(devices[0].game.tick, ticks[0])
        assertSameGame(devices, net: net)
    }

    func testPausingAtTheSameMomentCountsAsTheHostsPause() {
        let net = FakeNetwork(latency: 2)
        let (devices, _) = pausable(net)
        devices[0].pauseGame()
        devices[1].pauseGame()
        run(net, devices)
        XCTAssertEqual(devices.map { $0.pause?.player }, [0, 0])
    }

    func testTwoGuestsPausingAtTheSameMomentAgreeOnOnePause() {
        let net = FakeNetwork(latency: 2)
        let (devices, _) = pausable(net, guests: ["Bert", "Cleo"])
        devices[2].pauseGame()
        devices[1].pauseGame()
        run(net, devices)
        let player = devices[0].pause?.player
        XCTAssertNotNil(player)
        XCTAssertEqual(devices.map { $0.pause?.player }, [player, player, player])
    }

    func testPausingAgainDuringTheCountdownKeepsTheTimePaused() {
        let net = FakeNetwork(latency: 2)
        let (devices, wait) = pausable(net)
        let (host, guest) = (devices[0], devices[1])
        var events: [NetworkMatch.Event] = []
        guest.onEvent = { events.append($0) }
        host.pauseGame()
        run(net, devices)
        wait(100)
        host.resumeGame()
        run(net, devices)
        host.pauseGame()                            // e.g. the app went to the background during the countdown
        run(net, devices)
        XCTAssertNil(guest.pause?.resumesAt)
        wait(25)                                    // 125 s in total
        run(net, devices)
        XCTAssertEqual(events, [.pauseExpired(0)])
        wait(NetworkMatch.resumeCountdown)
        run(net, devices, frames: 60)
        XCTAssertTrue(guest.game.isFinished)
        XCTAssertEqual(guest.game.winner, 1)
        assertSameGame(devices)
    }

    func testAPauseOfMoreThanTwoMinutesPutsThePlayerOut() {
        let net = FakeNetwork(latency: 2)
        let (devices, wait) = pausable(net, guests: ["Bert", "Cleo"])
        var events: [NetworkMatch.Event] = []
        devices[2].onEvent = { events.append($0) }
        devices[1].pauseGame()
        run(net, devices)
        wait(NetworkMatch.pauseLimit - 1)
        run(net, devices)
        XCTAssertTrue(devices.allSatisfy { $0.status == .running })
        wait(2)
        // Bert's device is in the background; the host decides.
        let others = [devices[0], devices[2]]
        run(net, others)
        XCTAssertEqual(events, [.pauseExpired(1)])
        wait(NetworkMatch.resumeCountdown)
        run(net, others, frames: 60)
        for device in others {
            XCTAssertTrue(device.game.players[1].isDead)
            XCTAssertFalse(device.isPaused)
            XCTAssertEqual(device.status, .running)
        }
        assertSameGame(others, net: net)
        // Bert's device learns it as soon as it runs again.
        run(net, [devices[1]], frames: 10)
        XCTAssertEqual(devices[1].status, .pauseExpired)
        XCTAssertTrue(devices[1].game.players[1].isDead)
    }

    func testAPauseOfMoreThanTwoMinutesLetsTheOtherPlayerWin() {
        let net = FakeNetwork(latency: 2)
        let (devices, wait) = pausable(net)
        let (host, guest) = (devices[0], devices[1])
        guest.pauseGame()
        run(net, devices)
        wait(NetworkMatch.pauseLimit + 1)
        run(net, [host], frames: 60)
        wait(NetworkMatch.resumeCountdown)
        run(net, [host], frames: 60)
        XCTAssertTrue(host.game.isFinished)
        XCTAssertEqual(host.game.winner, 0)
        run(net, [guest], frames: 10)
        XCTAssertEqual(guest.status, .pauseExpired)
        XCTAssertEqual(guest.game.winner, 0)
    }

    func testBackFromATooLongPauseAfterTheConnectionDroppedIsALoss() {
        let net = FakeNetwork(latency: 2)
        let (devices, wait) = pausable(net)
        let guest = devices[1]
        guest.pauseGame()
        run(net, devices)
        wait(NetworkMatch.pauseLimit + 30)
        // The connection dropped meanwhile; the paused device must not win by it.
        link(devices[0], to: 1).close()
        run(net, [guest], frames: 60)
        XCTAssertEqual(guest.status, .pauseExpired)
        XCTAssertEqual(guest.game.winner, 0)
    }

    func testPlayersWhoAreOutCannotPause() {
        let net = FakeNetwork(latency: 2)
        let (devices, _) = pausable(net, guests: ["Bert", "Cleo"])
        devices[2].issue(.surrender)
        run(net, devices, frames: 20)
        devices[2].pauseGame()
        run(net, devices)
        XCTAssertTrue(devices.allSatisfy { !$0.isPaused })
    }

    // MARK: Handover

    /// Connected games with a shared, adjustable clock (also for the time limits of a handover).
    private func clocked(_ devices: [NetworkMatch]) -> (TimeInterval) -> Void {
        var now = Date(timeIntervalSince1970: 1_000_000)
        for d in devices { d.clock = { now } }
        return { now += $0 }
    }

    /// Runs the devices and plays the app's part in a handover; the clock goes on 0.1 s per frame.
    private func run(_ net: FakeNetwork, _ matches: [NetworkMatch], hub: HandoverHub, wait: (TimeInterval) -> Void,
                     frames: Int) {
        for _ in 0..<frames {
            net.now += 1
            net.deliver()
            hub.connect(matches)
            wait(0.1)
            for m in matches { m.updatePause(); m.advance() }
        }
    }

    func testTheNextPlayerTakesOverWhenTheHostLeaves() {
        let net = FakeNetwork(latency: 2)
        let devices = connect(net, guests: ["Bert", "Cleo"])
        let wait = clocked(devices)
        let hub = HandoverHub(net: net)
        var events: [NetworkMatch.Event] = []
        devices[2].onEvent = { events.append($0) }
        run(net, devices, frames: 150)
        devices[0].leave()
        let others = Array(devices.dropFirst())
        run(net, others, hub: hub, wait: wait, frames: 150)
        XCTAssertEqual(events, [.playerLeft(0), .newHost(1)])
        for device in others {
            XCTAssertEqual(device.status, .running)
            XCTAssertEqual(device.hostPlayer, 1)
            XCTAssertNil(device.handover)
            XCTAssertTrue(device.game.players[0].isDead)
        }
        XCTAssertGreaterThan(devices[1].game.tick, 250, "the game goes on")
        assertSameGame(others, net: net)
        // The new host also forwards: a command of Cleo reaches Bert.
        devices[2].issue(.sendCreeps(type: .mercury, count: 1))
        run(net, others, hub: hub, wait: wait, frames: 30)
        XCTAssertEqual(devices[1].game.players[2].income, devices[2].game.players[2].income)
        assertSameGame(others, net: net)
    }

    func testAHandoverGivesEveryDeviceThePacketsItMissed() {
        let net = FakeNetwork(latency: 5)
        let devices = connect(net, guests: ["Bert", "Cleo", "Dora"])
        let wait = clocked(devices)
        let hub = HandoverHub(net: net)
        var pilots = devices.map { Bot(player: $0.localPlayer, level: .normal, map: $0.game.map) }
        func play(_ matches: [NetworkMatch], frames: Int, crashing: Bool = false) {
            for _ in 0..<frames {
                net.now += 1
                net.deliver()
                hub.connect(matches)
                wait(0.1)
                for m in matches {
                    for c in pilots[m.localPlayer].think(game: m.game) { m.issue(c) }
                    m.updatePause()
                    m.advance()
                }
            }
        }
        play(devices, frames: 300)
        // Dora's connection to the host fails silently a little before the host crashes: she misses the last
        // packets of the host and of the others; the others have them.
        link(devices[0], to: 3).muted = true
        play(devices, frames: 6)
        for player in 1...3 { link(devices[0], to: player).close() }
        let others = Array(devices.dropFirst())
        play(others, frames: 6)                     // the last packets arrive, the handover starts
        XCTAssertTrue(others.allSatisfy { $0.handover != nil })
        XCTAssertLessThan(devices[3].game.tick, devices[1].game.tick, "Dora is behind")
        play(others, frames: 200)
        for device in others {
            XCTAssertEqual(device.status, .running)
            XCTAssertEqual(device.hostPlayer, 1)
            XCTAssertTrue(device.game.players[0].isDead)
        }
        assertSameGame(others, net: net)
    }

    func testAnUnreachableCandidateIsSkipped() {
        let net = FakeNetwork(latency: 2)
        let devices = connect(net, guests: ["Bert", "Cleo", "Dora"])
        let wait = clocked(devices)
        let hub = HandoverHub(net: net)
        run(net, devices, frames: 150)
        devices[0].leave()
        // Bert's device does not run any more (e.g. out of reach); Cleo and Dora wait for it, then Cleo takes over.
        hub.unreachable = [1]
        let others = [devices[2], devices[3]]
        run(net, others, hub: hub, wait: wait, frames: 250)
        for device in others {
            XCTAssertEqual(device.status, .running)
            XCTAssertEqual(device.hostPlayer, 2)
            XCTAssertTrue(device.game.players[0].isDead)
            XCTAssertTrue(device.game.players[1].isDead)
        }
        assertSameGame(others, net: net)
    }

    func testAGuestCutOffFromTheHostDoesNotPlayOnAlone() {
        let net = FakeNetwork(latency: 2)
        let devices = connect(net, guests: ["Bert", "Cleo"])
        let wait = clocked(devices)
        let hub = HandoverHub(net: net)
        run(net, devices, frames: 150)
        link(devices[2], to: 0).cut()               // only Cleo loses the connection
        run(net, devices, hub: hub, wait: wait, frames: 250)
        XCTAssertEqual(devices[2].status, .hostGone, "nobody else takes over: the round is over for Cleo")
        for device in devices.prefix(2) {
            XCTAssertEqual(device.status, .running)
            XCTAssertEqual(device.hostPlayer, 0)
            XCTAssertTrue(device.game.players[2].isDead)
        }
        assertSameGame(Array(devices.prefix(2)), net: net)
    }

    func testAWatchingPlayerOutOfStepOnlyLeavesItself() {
        let net = FakeNetwork(latency: 1)
        let devices = connect(net, guests: ["Bert", "Cleo"])
        var events: [NetworkMatch.Event] = []
        devices[1].onEvent = { events.append($0) }
        run(net, devices, frames: 150)
        devices[2].issue(.surrender)
        run(net, devices, frames: 20)
        devices[2].game.players[0].credits += 1     // Cleo is out and watches; her device falls out of step
        run(net, devices, frames: 60)
        XCTAssertEqual(devices[0].status, .running)
        XCTAssertEqual(devices[1].status, .running)
        XCTAssertEqual(events, [.playerLeft(2)])
    }
}

/// Plays the app's part in a handover: connects each guest to the device that took over.
final class HandoverHub {
    let net: FakeNetwork
    /// Devices nobody can reach.
    var unreachable: Set<Int> = []
    private var tried: [ObjectIdentifier: Int] = [:]

    init(net: FakeNetwork) { self.net = net }

    func connect(_ matches: [NetworkMatch]) {
        for guest in matches {
            let id = ObjectIdentifier(guest)
            guard case let .guest(host)? = guest.handover else { tried[id] = nil; continue }
            guard tried[id] != host, !unreachable.contains(host), !unreachable.contains(guest.localPlayer),
                  let newHost = matches.first(where: { $0.localPlayer == host && $0.handover == .host }) else { continue }
            tried[id] = host
            let (a, b) = net.pair()
            newHost.handoverGuest(a)
            guest.handoverConnected(b)
        }
    }
}
