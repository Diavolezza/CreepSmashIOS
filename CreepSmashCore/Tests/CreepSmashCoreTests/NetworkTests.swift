import XCTest
import Foundation
@testable import CreepSmashCore

/// Simulated network: messages arrive after a fixed number of frames, in order.
final class FakeNetwork {
    var now = 0
    var latency: Int
    fileprivate var queue: [(due: Int, to: LoopbackTransport, data: Data)] = []
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

    /// Delivers all due messages.
    func deliver() {
        while let i = queue.firstIndex(where: { $0.due <= now }) {
            let m = queue.remove(at: i)
            if !m.to.isClosed { m.to.onReceive?(m.data) }
        }
    }
}

final class LoopbackTransport: Transport {
    let network: FakeNetwork
    weak var peer: LoopbackTransport?
    var onReceive: ((Data) -> Void)?
    var onClose: (() -> Void)?
    private(set) var isClosed = false

    init(network: FakeNetwork) { self.network = network }

    func send(_ data: Data) {
        guard !isClosed, let peer else { return }
        network.post(data, to: peer)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        peer?.onClose?()
    }
}

final class NetworkTests: XCTestCase {
    /// Sets up two connected games via the handshake.
    private func connect(_ net: FakeNetwork, map: String = "neon", rules: Rules = .standard) -> (NetworkMatch, NetworkMatch) {
        let (a, b) = net.pair()
        var host: NetworkMatch?, guest: NetworkMatch?
        Handshake.host(transport: a, mapID: map, rules: rules, name: "Anna") {
            if case let .ready(m) = $0 { host = m }
        }
        Handshake.join(transport: b, name: "Bert") {
            if case let .ready(m) = $0 { guest = m }
        }
        for _ in 0..<(3 * net.latency + 3) { net.now += 1; net.deliver() }
        return (host!, guest!)
    }

    func testHandshakeAgreesOnSetup() {
        let net = FakeNetwork(latency: 2)
        let (host, guest) = connect(net, map: "canyon")
        XCTAssertEqual(host.setup, guest.setup)
        XCTAssertEqual(host.setup.names, ["Anna", "Bert"])
        XCTAssertEqual(host.localPlayer, 0)
        XCTAssertEqual(guest.localPlayer, 1)
        XCTAssertEqual(guest.game.map.id, "canyon")
    }

    func testHandshakeRejectsOtherVersion() {
        let net = FakeNetwork(latency: 1)
        let (a, b) = net.pair()
        var hostResult: Handshake.Failure?
        var guestResult: String?
        Handshake.host(transport: a, mapID: "neon", name: "Anna") {
            if case let .failed(reason) = $0 { hostResult = reason }
        }
        b.onReceive = { data in
            if case let .reject(reason) = NetMessage.decode(data) { guestResult = reason }
        }
        b.send(NetMessage.hello(protocolVersion: NetMessage.protocolVersion + 1, name: "Alt").encoded())
        for _ in 0..<5 { net.now += 1; net.deliver() }
        XCTAssertNotNil(hostResult)
        XCTAssertNotNil(guestResult)
    }

    /// Two computer opponents play against each other over the simulated network. Both devices must
    /// compute the same game – even if one device is slower.
    private func playOut(latency: Int, slowGuest: Bool) {
        let net = FakeNetwork(latency: latency)
        var rules = Rules.standard
        rules.startLives = 3
        let (host, guest) = connect(net, rules: rules)
        var botA = Bot(player: 0, level: .hard, map: host.game.map)
        var botB = Bot(player: 1, level: .normal, map: guest.game.map)
        var waits = 0
        var frame = 0
        while !(host.game.isFinished && guest.game.isFinished) && frame < 200_000 {
            frame += 1
            net.now += 1
            net.deliver()
            for c in botA.think(game: host.game) { host.issue(c) }
            if !host.advance() && !host.game.isFinished { waits += 1 }
            if !slowGuest || frame % 3 != 0 {
                for c in botB.think(game: guest.game) { guest.issue(c) }
                guest.advance()
            }
        }
        XCTAssertTrue(host.game.isFinished)
        XCTAssertTrue(guest.game.isFinished)
        XCTAssertEqual(host.status, .running)
        XCTAssertEqual(guest.status, .running)
        XCTAssertEqual(host.game.tick, guest.game.tick)
        XCTAssertEqual(host.game.checksum(), guest.game.checksum())
        XCTAssertEqual(host.game.winner, guest.game.winner)
        if slowGuest { XCTAssertGreaterThan(waits, 0, "The fast host must wait for the slow guest") }
    }

    func testBothDevicesComputeTheSameGame() {
        playOut(latency: 2, slowGuest: false)
    }

    func testSlowDeviceAndHighLatencyStayInSync() {
        playOut(latency: 9, slowGuest: true)
    }

    func testCommandsIssuedWhileWaitingAreNotLost() {
        let net = FakeNetwork(latency: 10)
        let (host, guest) = connect(net)
        // Host runs ahead until it has to wait, and then issues a tower command in every frame.
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

    func testLeavingLetsTheOpponentWin() {
        let net = FakeNetwork(latency: 2)
        let (host, guest) = connect(net)
        for _ in 0..<150 { net.now += 1; net.deliver(); host.advance(); guest.advance() }
        guest.leave()
        for _ in 0..<50 { net.now += 1; net.deliver(); host.advance() }
        XCTAssertEqual(host.status, .opponentGone)
        XCTAssertTrue(host.game.isFinished)
        XCTAssertEqual(host.game.winner, 0)
    }

    func testLostConnectionLetsTheOpponentWin() {
        let net = FakeNetwork(latency: 2)
        let (host, guest) = connect(net)
        var statusChanges: [NetworkMatch.Status] = []
        host.onStatusChange = { statusChanges.append($0) }
        for _ in 0..<150 { net.now += 1; net.deliver(); host.advance(); guest.advance() }
        // Connection drops without the guest sending anything.
        (guestTransport(of: guest) as? LoopbackTransport)?.close()
        for _ in 0..<50 { net.now += 1; net.deliver(); host.advance() }
        XCTAssertEqual(statusChanges, [.opponentGone])
        XCTAssertEqual(host.game.winner, 0)
    }

    func testDifferentStateIsDetected() {
        let net = FakeNetwork(latency: 1)
        let (host, guest) = connect(net)
        for _ in 0..<150 { net.now += 1; net.deliver(); host.advance(); guest.advance() }
        // Corrupt the state on one device.
        guest.game.players[1].credits += 1
        for _ in 0..<60 { net.now += 1; net.deliver(); host.advance(); guest.advance() }
        if case .desynced = host.status {} else { XCTFail("Host does not detect the divergence: \(host.status)") }
    }

    // MARK: - Pause

    /// Two connected games with a shared, adjustable clock.
    private func pausable(_ net: FakeNetwork) -> (NetworkMatch, NetworkMatch, (TimeInterval) -> Void) {
        let (host, guest) = connect(net)
        var now = Date(timeIntervalSince1970: 1_000_000)
        host.clock = { now }
        guest.clock = { now }
        for _ in 0..<100 { net.now += 1; net.deliver(); host.advance(); guest.advance() }
        return (host, guest, { now += $0 })
    }

    private func run(_ net: FakeNetwork, _ matches: NetworkMatch..., frames: Int = 10) {
        for _ in 0..<frames {
            net.now += 1
            net.deliver()
            for m in matches { m.updatePause(); m.advance() }
        }
    }

    func testOnlyThePlayerWhoPausedCanGoOnAfterACountdown() {
        let net = FakeNetwork(latency: 2)
        let (host, guest, wait) = pausable(net)
        guest.pauseGame()
        run(net, host, guest)
        XCTAssertEqual(host.pause?.player, 1)
        XCTAssertEqual(guest.pause?.player, 1)
        let ticks = (host.game.tick, guest.game.tick)
        run(net, host, guest, frames: 50)
        XCTAssertEqual(host.game.tick, ticks.0, "no ticks during the pause")
        XCTAssertEqual(guest.game.tick, ticks.1)
        host.resumeGame()                       // not the host's pause
        run(net, host, guest)
        XCTAssertNil(host.pause?.resumesAt)
        guest.resumeGame()
        run(net, host, guest)
        XCTAssertNotNil(host.pause?.resumesAt, "countdown on both devices")
        XCTAssertNotNil(guest.pause?.resumesAt)
        wait(NetworkMatch.resumeCountdown)
        run(net, host, guest, frames: 50)
        XCTAssertFalse(host.isPaused)
        XCTAssertFalse(guest.isPaused)
        XCTAssertGreaterThan(host.game.tick, ticks.0)
        XCTAssertEqual(host.status, .running)
    }

    func testPausingAgainDuringTheCountdownKeepsTheTimePaused() {
        let net = FakeNetwork(latency: 2)
        let (host, guest, wait) = pausable(net)
        host.pauseGame()
        run(net, host, guest)
        wait(100)
        host.resumeGame()
        run(net, host, guest)
        host.pauseGame()                        // e.g. the app went to the background during the countdown
        run(net, host, guest)
        XCTAssertNil(guest.pause?.resumesAt)
        wait(25)                                // 125 s in total
        run(net, host, guest, frames: 60)
        XCTAssertEqual(guest.status, .pauseExpired(loser: 0))
    }

    func testPausingAtTheSameMomentCountsAsTheHostsPause() {
        let net = FakeNetwork(latency: 2)
        let (host, guest, _) = pausable(net)
        host.pauseGame()
        guest.pauseGame()
        run(net, host, guest)
        XCTAssertEqual(host.pause?.player, 0)
        XCTAssertEqual(guest.pause?.player, 0)
    }

    func testAPauseOfMoreThanTwoMinutesLetsTheOtherPlayerWin() {
        let net = FakeNetwork(latency: 2)
        let (host, guest, wait) = pausable(net)
        guest.pauseGame()
        run(net, host, guest)
        wait(NetworkMatch.pauseLimit - 1)
        run(net, host, guest)
        XCTAssertEqual(host.status, .running)
        wait(2)
        // Only the waiting device notices (the other one may be in the background).
        run(net, host, frames: 60)
        XCTAssertEqual(host.status, .pauseExpired(loser: 1))
        XCTAssertTrue(host.game.isFinished)
        XCTAssertEqual(host.game.winner, 0)
        // The device that paused learns it as soon as it runs again.
        run(net, guest, frames: 60)
        XCTAssertEqual(guest.status, .pauseExpired(loser: 1))
        XCTAssertTrue(guest.game.isFinished)
        XCTAssertEqual(guest.game.winner, 0)
    }

    func testBackFromATooLongPauseAfterTheConnectionDroppedIsALoss() {
        let net = FakeNetwork(latency: 2)
        let (host, guest, wait) = pausable(net)
        guest.pauseGame()
        run(net, host, guest)
        wait(NetworkMatch.pauseLimit + 30)
        // The connection dropped meanwhile; the paused device must not win by it.
        (guestTransport(of: host) as? LoopbackTransport)?.close()
        run(net, guest, frames: 60)
        XCTAssertEqual(guest.status, .pauseExpired(loser: 1))
        XCTAssertEqual(guest.game.winner, 0)
    }

    private func guestTransport(of match: NetworkMatch) -> Transport {
        Mirror(reflecting: match).children.first { $0.label == "transport" }!.value as! Transport
    }
}
