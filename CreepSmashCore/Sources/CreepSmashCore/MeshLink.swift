import Foundation

/// The devices of a round that can all reach each other directly (a Game Center match) – turned into the
/// point-to-point connections (`Transport`) the lobby, the game and the handover work with.
///
/// Every message carries a small header: the channel (0: lobby and game, 1: handover) and its kind (data,
/// closed, or the announcement which player index a device has in the game). The first message on a
/// channel from a device without a transport there reports a new connection (`onIncoming`), as an accepted
/// connection would.
///
/// Not thread-safe: call everything on the same queue (the main actor in the app).
public final class MeshLink {
    /// A device of the round, by a stable ID (Game Center: the player's `gamePlayerID`).
    public typealias Peer = String

    public static let gameChannel: UInt8 = 0
    public static let handoverChannel: UInt8 = 1

    fileprivate enum Kind: UInt8 { case data = 0, closed = 1, announce = 2 }

    public let me: Peer
    /// The other devices still in the round.
    public private(set) var peers: [Peer]
    /// Game player index → device, as the devices announced it after the start (see `announce(player:)`).
    public private(set) var playerPeers: [Int: Peer] = [:]
    /// Another device opened a connection on a channel: its transport (the message that opened it
    /// arrives right after this call).
    public var onIncoming: ((Peer, UInt8, Transport) -> Void)?

    private let sendRaw: (Data, [Peer]) -> Void
    private var links: [Key: Link] = [:]
    fileprivate struct Key: Hashable { let peer: Peer, channel: UInt8 }

    /// - Parameter send: sends a message to the given devices (reliable, in order).
    public init(me: Peer, peers: [Peer], send: @escaping (Data, [Peer]) -> Void) {
        self.me = me
        self.peers = peers.filter { $0 != me }
        self.sendRaw = send
    }

    /// The device that connects the others at the start: the one with the smallest ID, so every device
    /// comes to the same result without a message.
    public var host: Peer { (peers + [me]).min()! }

    /// The connection to `peer` on `channel` (the same object as long as it is open).
    public func transport(to peer: Peer, channel: UInt8 = MeshLink.gameChannel) -> Transport {
        let key = Key(peer: peer, channel: channel)
        if let link = links[key] { return link }
        let link = Link(link: self, key: key)
        links[key] = link
        return link
    }

    /// Closes all connections on a channel without telling the others (a new handover starts afresh).
    public func reset(channel: UInt8) {
        for key in links.keys where key.channel == channel { links[key]?.isClosed = true; links[key] = nil }
    }

    /// Tells all devices which player index this device has in the game (for a later handover).
    public func announce(player: Int) {
        playerPeers[player] = me
        var data = Data([0, Kind.announce.rawValue])
        data.append(contentsOf: withUnsafeBytes(of: Int32(player).bigEndian) { Array($0) })
        sendRaw(data, peers)
    }

    /// A message from another device arrived.
    public func received(_ data: Data, from peer: Peer) {
        guard data.count >= 2, let kind = Kind(rawValue: data[data.startIndex + 1]) else { return }
        let channel = data[data.startIndex]
        let payload = data.dropFirst(2)
        let key = Key(peer: peer, channel: channel)
        switch kind {
        case .announce:
            guard payload.count == 4 else { return }
            let index = payload.reduce(Int32(0)) { $0 << 8 | Int32($1) }
            playerPeers[Int(index)] = peer
        case .closed:
            guard let link = links.removeValue(forKey: key) else { return }
            link.isClosed = true
            link.onClose?()
        case .data:
            if let link = links[key] {
                link.onReceive?(Data(payload))
            } else {
                let link = Link(link: self, key: key)
                links[key] = link
                onIncoming?(peer, channel, link)
                link.onReceive?(Data(payload))
            }
        }
    }

    /// A device left the round or lost its connection: all its connections close.
    public func disconnected(_ peer: Peer) {
        peers.removeAll { $0 == peer }
        for key in links.keys where key.peer == peer {
            guard let link = links.removeValue(forKey: key) else { continue }
            link.isClosed = true
            link.onClose?()
        }
    }

    fileprivate func send(_ kind: Kind, _ payload: Data, key: Key) {
        guard peers.contains(key.peer) else { return }
        var data = Data([key.channel, kind.rawValue])
        data.append(payload)
        sendRaw(data, [key.peer])
    }

    fileprivate func closed(_ link: Link) {
        if links[link.key] === link { links[link.key] = nil }
        send(.closed, Data(), key: link.key)
    }

    fileprivate final class Link: Transport {
        let key: Key
        weak var link: MeshLink?
        var onReceive: ((Data) -> Void)?
        var onClose: (() -> Void)?
        var isClosed = false

        init(link: MeshLink, key: Key) {
            self.link = link
            self.key = key
        }

        func send(_ data: Data) {
            guard !isClosed else { return }
            link?.send(.data, data, key: key)
        }

        func close() {
            guard !isClosed else { return }
            isClosed = true
            link?.closed(self)
        }
    }
}

/// The app's part of a handover (see `NetworkMatch.Handover`) when the devices reach each other over a
/// `MeshLink`: the new host accepts the others on the handover channel, the others open a connection to
/// it there. Announces the own player index at once, so every device knows which device to connect to.
public final class MeshHandover {
    private let link: MeshLink
    private weak var match: NetworkMatch?

    public init(link: MeshLink, match: NetworkMatch) {
        self.link = link
        self.match = match
        link.announce(player: match.localPlayer)
    }

    /// Call with every change of `NetworkMatch.handover` (its `onHandover`).
    public func update(_ role: NetworkMatch.Handover?) {
        link.onIncoming = nil
        // After the handover the game runs on the connections it made; they stay.
        guard let role, let match else { return }
        // A new handover starts afresh (the connections of an earlier one led to the device that is gone).
        link.reset(channel: MeshLink.handoverChannel)
        switch role {
        case .host:
            link.onIncoming = { [weak match] _, channel, transport in
                guard channel == MeshLink.handoverChannel, let match else { return transport.close() }
                match.handoverGuest(transport)
            }
        case let .guest(host):
            // A device that never announced itself cannot be reached; the time limits of the handover
            // then move on to the next candidate.
            guard let peer = link.playerPeers[host], link.peers.contains(peer) else { return }
            match.handoverConnected(link.transport(to: peer, channel: MeshLink.handoverChannel))
        }
    }
}
