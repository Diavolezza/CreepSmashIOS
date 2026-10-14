import XCTest
@testable import CreepSmashCore

/// Devices that all reach each other (like a Game Center match), with a delay of `latency` frames.
private final class FakeMesh {
    var now = 0
    let latency: Int
    private(set) var links: [MeshLink.Peer: MeshLink] = [:]
    private var queue: [(due: Int, from: MeshLink.Peer, to: MeshLink.Peer, data: Data?)] = []

    init(peers: [MeshLink.Peer], latency: Int = 2) {
        self.latency = latency
        for peer in peers {
            links[peer] = MeshLink(me: peer, peers: peers) { [unowned self] data, targets in
                for target in targets { self.queue.append((self.now + self.latency, peer, target, data)) }
            }
        }
    }

    /// A device leaves the round; the others notice it after the delay (data nil).
    func drop(_ peer: MeshLink.Peer) {
        links[peer] = nil
        queue.removeAll { $0.from == peer }
        for other in links.keys { queue.append((now + latency, peer, other, nil)) }
    }

    func deliver() {
        while let i = queue.firstIndex(where: { $0.due <= now }) {
            let m = queue.remove(at: i)
            guard let link = links[m.to] else { continue }
            if let data = m.data { link.received(data, from: m.from) } else { link.disconnected(m.from) }
        }
    }
}

final class MeshLinkTests: XCTestCase {
    func testEveryDeviceChoosesTheSameHost() {
        let mesh = FakeMesh(peers: ["G3", "G1", "G2"])
        XCTAssertEqual(Set(mesh.links.values.map(\.host)), ["G1"])
    }

    func testMessagesGoToTheRightConnectionAndClosingIsReported() {
        let mesh = FakeMesh(peers: ["A", "B"], latency: 1)
        let a = mesh.links["A"]!, b = mesh.links["B"]!
        var incoming: [(MeshLink.Peer, UInt8)] = []
        var received: [String] = []
        var closed = false
        b.onIncoming = { peer, channel, transport in
            incoming.append((peer, channel))
            transport.onReceive = { received.append(String(decoding: $0, as: UTF8.self)) }
            transport.onClose = { closed = true }
        }
        let ab = a.transport(to: "B", channel: 1)
        XCTAssertTrue(ab === a.transport(to: "B", channel: 1), "one connection per device and channel")
        ab.send(Data("hello".utf8))
        ab.send(Data("again".utf8))
        mesh.now += 1; mesh.deliver()
        XCTAssertEqual(incoming.map(\.0), ["A"])
        XCTAssertEqual(incoming.map(\.1), [1])
        XCTAssertEqual(received, ["hello", "again"])
        ab.close()
        mesh.now += 1; mesh.deliver()
        XCTAssertTrue(closed)
    }

    /// Lobby, game and handover over the mesh, as with Game Center: the device with the smallest ID opens
    /// the round, the others join; when it leaves, the next player takes over.
    func testARoundOverTheMeshSurvivesTheHostLeaving() {
        let mesh = FakeMesh(peers: ["P2", "P0", "P1"])
        let hostPeer = mesh.links["P0"]!.host
        XCTAssertEqual(hostPeer, "P0")
        var matches: [MeshLink.Peer: NetworkMatch] = [:]
        let lobby = HostLobby(mapID: "neon", name: "Anna", seats: 3, code: "MESH")
        lobby.startsWhenFull = true
        lobby.onStart = { matches[hostPeer] = $0 }
        let hostLink = mesh.links[hostPeer]!
        for peer in hostLink.peers.sorted() { lobby.add(hostLink.transport(to: peer)) }
        var guests: [GuestLobby] = []
        for (peer, link) in mesh.links where peer != hostPeer {
            let guest = GuestLobby(transport: link.transport(to: link.host), name: peer == "P1" ? "Bert" : "Cleo")
            guest.onResult = { if case let .ready(match) = $0 { matches[peer] = match } }
            guests.append(guest)
        }
        for _ in 0..<40 where matches.count < 3 { mesh.now += 1; mesh.deliver() }
        XCTAssertEqual(matches.count, 3, "the round starts when it is full")
        // Pause countdown and handover time limits run on a clock: 0.1 s per frame.
        var now = Date(timeIntervalSince1970: 1_000_000)
        for match in matches.values { match.clock = { now } }
        var handovers: [MeshHandover] = []
        for (peer, match) in matches {
            let handover = MeshHandover(link: mesh.links[peer]!, match: match)
            match.onHandover = { handover.update($0) }
            handovers.append(handover)
        }
        func run(_ frames: Int) {
            for _ in 0..<frames {
                mesh.now += 1
                mesh.deliver()
                now += 0.1
                for match in matches.values { match.updatePause(); match.advance() }
            }
        }
        run(120)
        let ticks = Set(matches.values.map(\.game.tick))
        XCTAssertGreaterThan(ticks.min()!, 50)
        // The host leaves: the next player (index 1) takes over and the game goes on.
        let host = matches.removeValue(forKey: hostPeer)!
        host.leave()
        mesh.drop(hostPeer)
        run(300)
        for match in matches.values {
            XCTAssertEqual(match.status, .running)
            XCTAssertEqual(match.hostPlayer, 1)
            XCTAssertNil(match.handover)
            XCTAssertTrue(match.game.players[0].isDead)
        }
        let others = Array(matches.values)
        for _ in 0..<300 where others.map(\.game.tick).min()! < others.map(\.game.tick).max()! {
            mesh.now += 1; mesh.deliver()
            let target = others.map(\.game.tick).max()!
            for m in others where m.game.tick < target { m.advance() }
        }
        XCTAssertEqual(others[0].game.tick, others[1].game.tick)
        XCTAssertEqual(others[0].game.checksum(), others[1].game.checksum())
        XCTAssertGreaterThan(others[0].game.tick, 280, "the game went on after the handover")
        _ = handovers
    }
}
