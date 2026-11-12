import Foundation

// Network play for two to four players using the lockstep method.
//
// Every device computes the whole game. Only the commands are transmitted, each with the tick in which
// they are executed. A device computes tick t only once it knows the commands of all people still playing
// for t; until then it waits. Each device sends a bundle every `bundleTicks` ticks (by default every tick,
// 20 a second): "my commands up to and including tick T" – usually none. The input delay
// bridges the network latency and the time between bundles, so that normally there is no waiting. Every
// device chooses its own input delay from the round-trip time it measures (ping/pong inside the bundles):
// it only decides when its own commands are executed, and their ticks travel with them.
// Computer players are computed on every device alike (same seed), so they cause no traffic.
// A checksum over the game state (inside the bundles) reveals if the devices drift apart anyway.
//
// The devices form a star: every guest is connected only to the host (at first player 0). The host
// forwards each guest's packets to the other guests and decides everything that has to be decided
// once – who is out after a lost connection or a pause that was too long, and whose pause counts.
// If the host is gone while other people still play, the next person in player order takes over
// (handover): the others connect to it, it collects the last packets every device has, so that all
// continue from the same state, and the old host drops out in the first tick nobody has a packet of.
//
// All methods must be called on the same thread (in the app: the main thread).

/// Connection to another device, e.g. TCP on the local network or Game Center.
/// Must deliver messages completely, in order and without loss.
public protocol Transport: AnyObject {
    func send(_ data: Data)
    /// Called for every received message.
    var onReceive: ((Data) -> Void)? { get set }
    /// Called when the connection drops (not after our own `close()`).
    var onClose: (() -> Void)? { get set }
    func close()
}

/// A place in the lobby of a network game.
public enum Seat: Codable, Equatable, Sendable {
    case open
    case human(name: String)
    case computer(Bot.Level)
}

/// What the guests see of the lobby while they wait for the start.
public struct LobbyInfo: Codable, Equatable, Sendable {
    public var mapID: String
    /// Index 0 is the host.
    public var seats: [Seat]
    /// The receiver's seat.
    public var you: Int

    public init(mapID: String, seats: [Seat], you: Int) {
        self.mapID = mapID
        self.seats = seats
        self.you = you
    }
}

/// What all devices agree on before the start. The host (player 0) decides it.
public struct MatchSetup: Codable, Equatable, Sendable {
    public var mapID: String
    public var rules: Rules
    /// Index = player number; 0 is the host.
    public var names: [String]
    /// Per player: the level of the computer that plays this place, nil for a person.
    public var computers: [Bot.Level?]
    /// Seed of the computers' playing styles.
    public var seed: UInt64
    /// Code of the round; the devices find each other by it for a handover. Empty: no handover (quick game).
    public var code: String

    /// Names come from other devices: at most this many characters, no line breaks.
    public static let maxNameLength = 24
    public static func cleanName(_ name: String) -> String {
        String(name.filter { !$0.isNewline }.prefix(maxNameLength))
    }

    public init(mapID: String, rules: Rules = .standard, names: [String], computers: [Bot.Level?]? = nil,
                seed: UInt64 = 0, code: String = "") {
        self.mapID = mapID
        self.rules = rules
        self.names = names
        self.computers = computers ?? Array(repeating: nil, count: names.count)
        self.seed = seed
        self.code = code
    }

    /// Players played by people.
    public var humans: [Int] { names.indices.filter { computers[$0] == nil } }
}

/// The commands of one player for one tick, as sent.
public struct NetPacket: Codable, Equatable, Sendable {
    public var player: Int
    public var tick: Int
    public var commands: [ScheduledCommand]

    public init(player: Int, tick: Int, commands: [ScheduledCommand]) {
        self.player = player
        self.tick = tick
        self.commands = commands
    }
}

/// Checksum of the sender's state after computing `tick`.
public struct NetHash: Codable, Equatable, Sendable {
    public var tick: Int
    public var value: UInt64

    public init(tick: Int, value: UInt64) {
        self.tick = tick
        self.value = value
    }

    enum CodingKeys: String, CodingKey { case tick = "t", value = "v" }
}

/// What a device sends every few ticks: its commands up to and including `upTo` (usually none – then the
/// receiver knows that these ticks are empty), plus checksums and the round-trip measurement.
/// Short keys and no empty fields: this is by far the most frequent message.
public struct NetBundle: Codable, Equatable, Sendable {
    public var player: Int
    /// The sender's commands are complete up to and including this tick.
    public var upTo: Int
    /// Commands for the ticks after the previous bundle up to `upTo`, each with its tick.
    public var commands: [ScheduledCommand]
    /// Checksums computed since the previous bundle.
    public var hashes: [NetHash]?
    /// The sender's clock in milliseconds; the receiver sends it back in `pongs`.
    public var ping: Int?
    /// Answers to pings, by the player who sent the ping: their value plus the milliseconds it was held here.
    public var pongs: [Int: Int]?

    public init(player: Int, upTo: Int, commands: [ScheduledCommand] = [], hashes: [NetHash]? = nil,
                ping: Int? = nil, pongs: [Int: Int]? = nil) {
        self.player = player
        self.upTo = upTo
        self.commands = commands
        self.hashes = hashes
        self.ping = ping
        self.pongs = pongs
    }

    enum CodingKeys: String, CodingKey { case player = "p", upTo = "t", commands = "c", hashes = "h", ping = "i", pongs = "o" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        player = try c.decode(Int.self, forKey: .player)
        upTo = try c.decode(Int.self, forKey: .upTo)
        commands = try c.decodeIfPresent([ScheduledCommand].self, forKey: .commands) ?? []
        hashes = try c.decodeIfPresent([NetHash].self, forKey: .hashes)
        ping = try c.decodeIfPresent(Int.self, forKey: .ping)
        pongs = try c.decodeIfPresent([Int: Int].self, forKey: .pongs)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(player, forKey: .player)
        try c.encode(upTo, forKey: .upTo)
        if !commands.isEmpty { try c.encode(commands, forKey: .commands) }
        try c.encodeIfPresent(hashes, forKey: .hashes)
        try c.encodeIfPresent(ping, forKey: .ping)
        try c.encodeIfPresent(pongs, forKey: .pongs)
    }
}

/// Handover: what a device brings to the new host.
public struct NetResync: Codable, Equatable, Sendable {
    public var player: Int
    /// The next tick this device computes.
    public var nextTick: Int
    /// The last packets this device has (its own and those of the others).
    public var packets: [NetPacket]
}

/// Handover: a player who did not come along drops out in this tick.
public struct NetEnd: Codable, Equatable, Sendable {
    public var player: Int
    public var tick: Int
}

/// Messages between the devices.
public enum NetMessage: Codable, Equatable, Sendable {
    /// Guest → host.
    case hello(protocolVersion: Int, name: String)
    /// Host → guest: the lobby has changed.
    case lobby(LobbyInfo)
    /// Host → guest: the game starts with these settings; the receiver is `player`.
    case welcome(MatchSetup, player: Int)
    /// Host → guest: rejected or lobby closed; `reason` is the raw value of a `LobbyFailure`.
    case reject(reason: String)
    /// Commands of one player up to a tick, with checksums and ping/pong. The host forwards the guests'
    /// bundles; its own may also contain the surrender of a guest who is out.
    case inputs(NetBundle)
    /// Pause of `player` on (applies to all) or off (`false`: countdown, then everyone goes on).
    case pause(player: Int, on: Bool)
    /// Host → guests: the pause of `player` lasted longer than `NetworkMatch.pauseLimit`; the player is out.
    case pauseExpired(player: Int)
    /// Host → guests: `player` has left or lost the connection and is out.
    case dropped(player: Int)
    /// Host → guests: the devices compute differently; the game cannot go on.
    case desynced(tick: Int)
    /// The sender leaves the game.
    case leave
    /// Handover, guest → new host: own state and last packets.
    case resync(NetResync)
    /// Handover, new host → guests: the packets some devices were missing, and who drops out when.
    case resume(packets: [NetPacket], ended: [NetEnd])
    /// After the end: `player` wants a rematch (guest → host; the host passes it on). When all people still
    /// there want it, the host sends `welcome` with the new game over the same connections.
    case rematch(player: Int)

    /// Must be increased on every incompatible change to rules, simulation or messages – only identical
    /// versions compute identically. The app's minor version follows it (protocol 8 = 1.1), see build.sh.
    /// 8: bundles every few ticks instead of a packet per tick, input delay from the measured round trip.
    public static let protocolVersion = 8
    /// Version of the simulation alone (saved games carry it): increase it, and the protocol version,
    /// when rules or simulation change. Protocol 8 changed only the messages.
    public static let simulationVersion = 7

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    public static func decode(_ data: Data) -> NetMessage? {
        try? JSONDecoder().decode(NetMessage.self, from: data)
    }
}

/// Why joining or setting up a game failed. The app turns this into a message in the player's language.
public enum LobbyFailure: String, Sendable {
    case connectionLost, otherVersion, unknownMap, full, closed
}

// MARK: - Lobby

/// The host's lobby: up to four seats. Guests take the free seats in the order they arrive; the host
/// can give free seats to computers. `start()` creates the game on all devices.
public final class HostLobby {
    public private(set) var mapID: String
    public let rules: Rules
    /// Index 0 is the host.
    public private(set) var seats: [Seat]
    /// Starts by itself as soon as no seat is free any more (quick game).
    public var startsWhenFull = false
    /// Seats or map have changed.
    public var onChange: (() -> Void)?
    /// The game has started (also when started by `startsWhenFull`).
    public var onStart: ((NetworkMatch) -> Void)?
    /// Starting failed (unknown map – cannot happen with the built-in maps).
    public var onFailure: ((LobbyFailure) -> Void)?

    /// Connected, but no `hello` yet.
    private var waiting: [ObjectIdentifier: Transport] = [:]
    /// Guests by seat.
    private var seated: [Int: Transport] = [:]
    private var closed = false

    /// Code of the round (for a handover during the game); empty for a quick game.
    public let code: String

    public init(mapID: String, rules: Rules = .standard, name: String, seats: Int = 4, code: String = "") {
        precondition((2...4).contains(seats), "2 to 4 seats")
        self.code = code
        self.mapID = mapID
        self.rules = rules
        self.seats = [.human(name: name)] + Array(repeating: .open, count: seats - 1)
    }

    public var takenSeats: Int { seats.filter { $0 != .open }.count }
    public var guestCount: Int { seated.count }
    public var canStart: Bool { !closed && takenSeats >= 2 }

    /// A guest has connected.
    public func add(_ transport: Transport) {
        guard !closed else { return transport.close() }
        let id = ObjectIdentifier(transport)
        waiting[id] = transport
        transport.onClose = { [weak self] in self?.waiting[id] = nil }
        transport.onReceive = { [weak self, weak transport] data in
            guard let self, let transport else { return }
            self.hello(data, from: transport)
        }
    }

    /// Gives a free seat to a computer (`level`) or frees it again (nil). Seats of guests cannot be changed.
    public func setComputer(seat: Int, level: Bot.Level?) {
        guard !closed, seats.indices.contains(seat), seat > 0, seated[seat] == nil else { return }
        seats[seat] = level.map(Seat.computer) ?? .open
        changed()
    }

    public func setMap(_ id: String) {
        guard !closed, GameMap.named(id) != nil, id != mapID else { return }
        mapID = id
        changed()
    }

    /// Starts the game: the taken seats become the players in their order (host = player 0).
    @discardableResult
    public func start(seed: UInt64 = .random(in: .min ... .max)) -> NetworkMatch? {
        guard canStart else { return nil }
        closed = true
        let order = seats.indices.filter { seats[$0] != .open }
        var names: [String] = [], computers: [Bot.Level?] = []
        for seat in order {
            switch seats[seat] {
            case let .human(name):
                names.append(name)
                computers.append(nil)
            case let .computer(level):
                names.append("CPU\(computers.filter { $0 != nil }.count + 1)")
                computers.append(level)
            case .open:
                break
            }
        }
        let setup = MatchSetup(mapID: mapID, rules: rules, names: names, computers: computers, seed: seed, code: code)
        var links: [Int: Transport] = [:]
        for (player, seat) in order.enumerated() {
            if let transport = seated[seat] { links[player] = transport }
        }
        for transport in waiting.values {
            transport.onReceive = nil
            transport.onClose = nil
            transport.close()
        }
        waiting = [:]
        seated = [:]
        for (player, transport) in links {
            transport.send(NetMessage.welcome(setup, player: player).encoded())
        }
        guard let match = NetworkMatch(setup: setup, localPlayer: 0, links: links) else {
            links.values.forEach { $0.close() }
            onFailure?(.unknownMap)
            return nil
        }
        onStart?(match)
        return match
    }

    /// Closes the lobby without a game; the guests learn it.
    public func close() {
        guard !closed else { return }
        closed = true
        for transport in Array(waiting.values) + Array(seated.values) {
            transport.onReceive = nil
            transport.onClose = nil
            transport.send(NetMessage.reject(reason: LobbyFailure.closed.rawValue).encoded())
            transport.close()
        }
        waiting = [:]
        seated = [:]
    }

    private func hello(_ data: Data, from transport: Transport) {
        let id = ObjectIdentifier(transport)
        guard !closed, waiting[id] != nil, case let .hello(version, name) = NetMessage.decode(data) else { return }
        waiting[id] = nil
        guard version == NetMessage.protocolVersion else { return reject(transport, .otherVersion) }
        guard let seat = seats.firstIndex(of: .open) else { return reject(transport, .full) }
        seats[seat] = .human(name: MatchSetup.cleanName(name))
        seated[seat] = transport
        transport.onReceive = nil
        transport.onClose = { [weak self] in self?.guestLeft(seat: seat) }
        changed()
    }

    private func reject(_ transport: Transport, _ reason: LobbyFailure) {
        transport.onReceive = nil
        transport.onClose = nil
        transport.send(NetMessage.reject(reason: reason.rawValue).encoded())
        transport.close()
    }

    private func guestLeft(seat: Int) {
        guard !closed else { return }
        seated[seat] = nil
        seats[seat] = .open
        changed()
    }

    private func changed() {
        for (seat, transport) in seated {
            transport.send(NetMessage.lobby(LobbyInfo(mapID: mapID, seats: seats, you: seat)).encoded())
        }
        onChange?()
        if startsWhenFull && !seats.contains(.open) { start() }
    }
}

/// A guest in the host's lobby: introduces itself, follows the lobby and gets the game at the start.
public final class GuestLobby {
    public enum Result {
        case ready(NetworkMatch)
        case failed(LobbyFailure)
    }

    /// The lobby as the host last reported it (nil until the first report).
    public private(set) var info: LobbyInfo?
    public var onChange: (() -> Void)?
    public var onResult: ((Result) -> Void)?

    private let transport: Transport
    private var finished = false

    public init(transport: Transport, name: String) {
        self.transport = transport
        transport.onClose = { [weak self] in self?.finish(.failed(.connectionLost)) }
        transport.onReceive = { [weak self] data in self?.receive(data) }
        transport.send(NetMessage.hello(protocolVersion: NetMessage.protocolVersion, name: name).encoded())
    }

    /// Leaves the lobby.
    public func leave() {
        guard !finished else { return }
        finished = true
        transport.onReceive = nil
        transport.onClose = nil
        transport.close()
    }

    private func receive(_ data: Data) {
        switch NetMessage.decode(data) {
        case let .lobby(info):
            self.info = info
            onChange?()
        case let .welcome(setup, player):
            guard let match = NetworkMatch(setup: setup, localPlayer: player, links: [0: transport]) else {
                return finish(.failed(.unknownMap))
            }
            finish(.ready(match))
        case let .reject(reason):
            finish(.failed(LobbyFailure(rawValue: reason) ?? .otherVersion))
        default:
            break
        }
    }

    private func finish(_ result: Result) {
        guard !finished else { return }
        finished = true
        if case .failed = result {
            transport.onReceive = nil
            transport.onClose = nil
            transport.close()
        }
        onResult?(result)
    }
}

// MARK: - Game

/// Game against people on other devices (and computers computed on every device).
public final class NetworkMatch: Match {
    public enum Status: Equatable {
        case running
        /// This device has left the game.
        case left
        /// The own pause lasted longer than `pauseLimit`: out of the game, counts as given up.
        case pauseExpired
        /// The connection to the others is lost (the host is gone and no handover worked): the round is over here.
        case hostGone
        /// The connection to the last other person still playing dropped without a goodbye (network, app
        /// stopped). The game stands still until the app has decided: `opponentsGone()` if this device is
        /// online (the others lost the network or stopped the app: they are out), otherwise the round ends
        /// without a winner. An explicit `leave()` is a surrender instead.
        case connectionLost
        /// The devices computed differently (bug in the simulation).
        case desynced(tick: Int)
    }

    /// Things that happen to other players; the game goes on.
    public enum Event: Equatable, Sendable {
        /// Left the game or lost the connection: out.
        case playerLeft(Int)
        /// Did not continue within `pauseLimit` after pausing: out.
        case pauseExpired(Int)
        /// After a handover this player's device connects the others.
        case newHost(Int)
    }

    /// Role of this device while the host role is handed over (the app connects the devices).
    public enum Handover: Equatable, Sendable {
        /// This device takes over: it must be reachable for the others, see `handoverGuest(_:)`.
        case host
        /// This device connects to the device of `player`, see `handoverConnected(_:)`.
        case guest(of: Int)
    }

    /// A pause. Only the player who paused can end it; then a countdown runs on all devices.
    public struct Pause: Equatable, Sendable {
        public let player: Int
        public let since: Date
        /// The game goes on at this moment (countdown running); nil while it is still paused.
        public internal(set) var resumesAt: Date?
    }

    /// If the player who paused does not continue within this time, the player is out.
    public static let pauseLimit: TimeInterval = 120
    /// Countdown before the game goes on after a pause (and after a handover).
    public static let resumeCountdown: TimeInterval = 3
    /// Handover: how long a guest tries to reach a candidate before it tries the next one.
    public static let handoverConnectTimeout: TimeInterval = 6
    /// Handover: how long the new host waits for the others.
    public static let handoverWaitTimeout: TimeInterval = 12
    /// Handover: how long a connected guest waits for the new host's answer.
    public static let handoverResumeTimeout: TimeInterval = 15
    /// Ticks of packets every device keeps for a handover.
    static let historyTicks = 200
    /// A bundle is sent every this many ticks. Every tick (20 a second, as up to protocol 7): the game must not
    /// stall, not even rarely. Every 2 ticks saved a third of the extra energy of online play, every 4 ticks
    /// almost two thirds – but the game stalled now and then (measured, docs/energy.md). Game feel comes first.
    /// The input delay grows with it – the commands of a bundle must arrive before their ticks are computed.
    public static let defaultBundleTicks = 1
    /// The input delay never goes beyond 400 ms: with a worse connection the game rather waits now and then
    /// (and shows a hint) than reacting late to every tap.
    public static let maxInputDelay = 8
    /// A ping every this many seconds (inside a bundle).
    static let pingInterval: TimeInterval = 2
    /// Round trips remembered per connection; the largest of them counts.
    static let roundTripSamples = 5
    /// A bundle may cover at most this many ticks (from another device: checked).
    static let maxBundleSpan = 2 * historyTicks

    /// The current pause (nil: running). No ticks are computed while it lasts, countdown included.
    public private(set) var pause: Pause?
    public var isPaused: Bool { pause != nil }
    /// Clock for pause and handover (tests set their own).
    public var clock: () -> Date = Date.init

    public let game: Game
    public let localPlayer: Int
    public let setup: MatchSetup
    /// The player whose device connects the others (0 until a handover).
    public private(set) var hostPlayer = 0
    public var isHost: Bool { localPlayer == hostPlayer }
    /// Per remote person: the last tick whose packet has arrived (diagnostics: compared with `game.tick`).
    public var receivedTicks: [Int: Int] { readyTick }
    public private(set) var status: Status = .running
    /// The role of this device during a handover (nil: no handover running).
    public private(set) var handover: Handover?
    /// Status has changed.
    public var onStatusChange: ((Status) -> Void)?
    /// Another player is out (left, connection lost, pause too long), or a new host.
    public var onEvent: ((Event) -> Void)?
    /// The handover role has changed (nil: the handover is over).
    public var onHandover: ((Handover?) -> Void)?
    /// Diagnostics: connection events worth a line in the network log.
    public var onLog: ((String) -> Void)?
    /// After the end: everybody wanted a rematch – the new game on the same connections (same map, same
    /// players, new seed). This match is over then.
    public var onRematch: ((NetworkMatch) -> Void)?
    /// The players who want a rematch (after the end), the own one included.
    public private(set) var rematchVotes: Set<Int> = []
    /// Called when `rematchVotes` changes.
    public var onRematchVotes: (() -> Void)?
    /// Interval between checksums in ticks.
    public var hashInterval = 20
    /// Bundle interval of this device (each device chooses its own; measurements change it).
    public var bundleTicks = NetworkMatch.defaultBundleTicks {
        didSet { bundleTicks = min(10, max(1, bundleTicks)); updateInputDelay() }
    }
    /// Ticks between an own command and its execution. Chosen by this device from the measured round trip:
    /// bundle interval + the way to the others (half the round trip with two people, a whole one with more:
    /// guest – host – guest) + 1 tick of reserve, at most `maxInputDelay`.
    public private(set) var inputDelay: Int
    /// The largest round trip to the other devices in milliseconds (nil: not measured yet).
    public private(set) var roundTripMilliseconds: Int?
    /// Messages and bytes this device has sent and received (diagnostics and energy measurements).
    public private(set) var messagesSent = 0, bytesSent = 0, messagesReceived = 0, bytesReceived = 0

    /// Host: the guests by player number. Guest: only the host.
    private var links: [Int: Transport]
    /// People on other devices.
    private let remoteHumans: [Int]
    /// Last tick for which each remote person's packet has arrived.
    private var readyTick: [Int: Int]
    /// Remote people who are out because they left or lost the connection; nobody waits for them.
    private var gone: Set<Int> = []
    private var bots: [Bot]
    private var botSequence = 0
    private var sequence = 0
    /// Own commands not yet sent, keyed by execution tick (the host's also contain surrenders of guests).
    private var outgoing: [Int: [ScheduledCommand]] = [:]
    /// Last tick for which our own packet has already been sent.
    private var lastSentTick: Int
    /// The packets of the last `historyTicks` ticks (own and received), for a handover.
    private var history: [NetPacket] = []
    private var localHashes: [Int: UInt64] = [:]
    /// Own checksums not yet sent.
    private var pendingHashes: [NetHash] = []
    /// Round trips in milliseconds by connection (the last few).
    private var roundTrips: [Int: [Int]] = [:]
    /// Pings to answer in the next bundle: value and arrival, by player.
    private var echoes: [Int: (value: Int, at: Date)] = [:]
    private var lastPing: Date?
    /// Checksums from other devices: host – of each guest; guest – of the host.
    private var remoteHashes: [Int: [Int: UInt64]] = [:]

    /// A running handover.
    private struct Migration {
        var oldHost: Int
        /// Possible new hosts in order; the first one is tried.
        var candidates: [Int]
        /// Start of the current role.
        var since: Date
        /// Guest: the connection to the new host.
        var link: Transport?
        /// New host: guests that have reported.
        var guests: [Int: (transport: Transport, resync: NetResync)] = [:]
        /// New host: connected, not reported yet.
        var pending: [ObjectIdentifier: Transport] = [:]
    }
    private var migration: Migration?

    public init?(setup received: MatchSetup, localPlayer: Int, links: [Int: Transport]) {
        // The setup comes from the host: checked completely before it is used.
        var setup = received
        let count = setup.names.count
        guard (2...4).contains(count), setup.computers.count == count, setup.names.indices.contains(localPlayer),
              setup.computers[0] == nil, setup.computers[localPlayer] == nil, setup.rules.isPlausible,
              let map = GameMap.named(setup.mapID) else { return nil }
        setup.names = setup.names.map(MatchSetup.cleanName)
        self.setup = setup
        self.localPlayer = localPlayer
        self.links = links
        game = Game(map: map, playerNames: setup.names, rules: setup.rules)
        remoteHumans = setup.humans.filter { $0 != localPlayer }
        // For the first ticks (before the input delay of the rules) there are no packets – they count as empty.
        lastSentTick = setup.rules.inputDelayTicks - 1
        inputDelay = max(setup.rules.inputDelayTicks, Self.defaultBundleTicks + 2)
        readyTick = Dictionary(uniqueKeysWithValues: remoteHumans.map { ($0, setup.rules.inputDelayTicks - 1) })
        let computers = setup.names.indices.filter { setup.computers[$0] != nil }
        let styles = Bot.Style.varied(count: computers.count, seed: setup.seed)
        bots = computers.enumerated().map { index, player in
            Bot(player: player, level: setup.computers[player]!, map: map, style: styles[index])
        }
        attach(links)
    }

    /// Remote people whose packet for the next tick is still missing.
    public var waitingFor: [Int] {
        guard !game.isFinished, migration == nil else { return [] }
        return remoteHumans.filter { mustWait(for: $0) }
    }

    /// Is the game currently waiting for another device?
    public var isWaitingForOpponent: Bool { !waitingFor.isEmpty }

    private func mustWait(for player: Int) -> Bool {
        // A player who is out has no commands left that count (they are rejected), so nobody waits.
        !gone.contains(player) && !game.players[player].isDead && (readyTick[player] ?? .max) < game.tick
    }

    /// Execution at the earliest after the input delay and never in a tick that has already been sent.
    private var nextCommandTick: Int { max(game.tick + inputDelay, lastSentTick + 1) }

    public func issue(_ command: Command) {
        let tick = nextCommandTick
        sequence += 1
        let scheduled = ScheduledCommand(tick: tick, player: localPlayer, sequence: sequence, command: command)
        game.schedule(scheduled)
        outgoing[tick, default: []].append(scheduled)
    }

    @discardableResult
    public func advance() -> Bool {
        guard status == .running, migration == nil, !game.isFinished, pause == nil else { return false }
        // A bundle every `bundleTicks` ticks; it promises the commands up to the input delay ahead.
        let horizon = game.tick + inputDelay
        if horizon - lastSentTick >= bundleTicks { flush(upTo: horizon) }
        guard !isWaitingForOpponent else { return false }
        for i in bots.indices {
            for command in bots[i].think(game: game) {
                botSequence += 1
                game.schedule(ScheduledCommand(tick: game.tick + game.rules.inputDelayTicks, player: bots[i].player,
                                               sequence: botSequence, command: command))
            }
        }
        game.step()
        let done = game.tick - 1
        if done % 50 == 0 {
            history.removeAll { $0.tick < done - Self.historyTicks }
        }
        if done % hashInterval == 0 && status == .running {
            let value = game.checksum()
            localHashes[done] = value
            localHashes = localHashes.filter { $0.key > done - 50 * hashInterval }
            pendingHashes.append(NetHash(tick: done, value: value))
            for player in remoteHashes.keys { compareHash(done, with: player) }
        }
        return true
    }

    /// Pauses the game for everyone. Ignored while another player's pause lasts and for players who
    /// are out. Pausing again during the own countdown keeps the time already paused (the limit is not reset).
    public func pauseGame() {
        guard status == .running, migration == nil, !game.isFinished, !game.players[localPlayer].isDead else { return }
        if let current = pause {
            guard current.player == localPlayer, current.resumesAt != nil else { return }
            pause?.resumesAt = nil
        } else {
            pause = Pause(player: localPlayer, since: clock())
        }
        broadcast(.pause(player: localPlayer, on: true))
    }

    /// Ends the own pause: after the countdown everyone goes on.
    public func resumeGame() {
        guard status == .running, let current = pause, current.player == localPlayer, current.resumesAt == nil else { return }
        pause?.resumesAt = clock().addingTimeInterval(Self.resumeCountdown)
        broadcast(.pause(player: localPlayer, on: false))
    }

    /// To be called regularly (every frame): ends the countdown, enforces the pause limit (host) and
    /// the time limits of a handover.
    public func updatePause() {
        guard status == .running else { return }
        if let migration {
            return updateHandover(migration)
        }
        guard let current = pause else { return }
        if let at = current.resumesAt {
            if clock() >= at { pause = nil }
            return
        }
        let paused = clock().timeIntervalSince(current.since)
        if isHost {
            if paused >= Self.pauseLimit { expirePause(of: current.player) }
        } else if current.player == hostPlayer && paused >= Self.pauseLimit + 10 {
            hostGone(explicit: false)                       // the host does not answer any more
        }
    }

    /// Gives up and disconnects. If the host leaves, the others hand over the host role.
    public func leave() {
        guard status == .running, migration == nil else {
            abandonHandover()
            closeLinks()
            if status == .running { status = .left }
            return
        }
        if !game.isFinished && !game.players[localPlayer].isDead {
            let tick = nextCommandTick
            issue(.surrender)
            flush(upTo: tick)
        }
        broadcast(.leave)
        closeLinks()
        status = .left
    }

    // MARK: Rematch

    /// People still in the round (connected, not left) – the players of a rematch besides the computers.
    private var presentHumans: [Int] {
        setup.humans.filter { $0 == localPlayer || (!gone.contains($0) && remoteHumans.contains($0)) }
    }

    /// A rematch is possible: the game is over and at least one other person is still there.
    public var canRematch: Bool {
        status == .running && migration == nil && game.isFinished && presentHumans.count >= 2
    }

    /// The own wish for a rematch; the host starts it once everybody still there wants it.
    public func requestRematch() {
        guard canRematch, !rematchVotes.contains(localPlayer) else { return }
        rematchVotes.insert(localPlayer)
        onRematchVotes?()
        broadcast(.rematch(player: localPlayer))
        if isHost { startRematchIfAgreed() }
    }

    private func receivedRematch(_ player: Int, from link: Int) {
        guard game.isFinished, setup.humans.contains(player), !gone.contains(player) else { return }
        if isHost {
            guard player == link else { return }
            rematchVotes.insert(player)
            broadcast(.rematch(player: player), except: link)
            onRematchVotes?()
            startRematchIfAgreed()
        } else {
            rematchVotes.insert(player)
            onRematchVotes?()
        }
    }

    /// Host: everybody still there wants a rematch – the new game: the host becomes player 0, the others follow
    /// in their old order (people who left are not in it any more), same map, rules and computers, new seed.
    private func startRematchIfAgreed() {
        let humans = presentHumans
        guard isHost, canRematch, Set(humans).isSubset(of: rematchVotes) else { return }
        let order = [localPlayer] + setup.names.indices.filter { $0 != localPlayer && (setup.computers[$0] != nil || humans.contains($0)) }
        let next = MatchSetup(mapID: setup.mapID, rules: setup.rules, names: order.map { setup.names[$0] },
                              computers: order.map { setup.computers[$0] }, seed: .random(in: .min ... .max), code: setup.code)
        var newLinks: [Int: Transport] = [:]
        for (index, old) in order.enumerated() where old != localPlayer {
            guard setup.computers[old] == nil, let transport = links[old] else { continue }
            transport.send(NetMessage.welcome(next, player: index).encoded())
            newLinks[index] = transport
        }
        handOverLinks()
        guard let match = NetworkMatch(setup: next, localPlayer: 0, links: newLinks) else { return }
        match.clock = clock
        onRematch?(match)
    }

    /// Guest: the host sends the rematch.
    private func receivedRematchWelcome(_ setup: MatchSetup, player: Int, from link: Int) {
        guard !isHost, link == hostPlayer, game.isFinished, let transport = links[link] else { return }
        handOverLinks()
        guard let match = NetworkMatch(setup: setup, localPlayer: player, links: [0: transport]) else {
            transport.close()
            return setStatus(.hostGone)
        }
        match.clock = clock
        onRematch?(match)
    }

    /// The connections go on in the rematch: this match lets go of them without closing them.
    private func handOverLinks() {
        for transport in links.values {
            transport.onReceive = nil
            transport.onClose = nil
        }
        links = [:]
        status = .left
    }

    // MARK: Handover (called by the app)

    /// Guest during a handover: the connection to the new host is established.
    public func handoverConnected(_ transport: Transport) {
        guard status == .running, var m = migration, case let .guest(host) = handover, m.link == nil else {
            return transport.close()
        }
        m.link = transport
        m.since = clock()
        migration = m
        transport.onReceive = { [weak self] data in self?.handoverMessage(data, from: host) }
        transport.onClose = { [weak self] in self?.handoverLost(host) }
        let resync = NetResync(player: localPlayer, nextTick: game.tick, packets: history)
        transport.send(NetMessage.resync(resync).encoded())
    }

    /// New host during a handover: another device has connected.
    public func handoverGuest(_ transport: Transport) {
        guard status == .running, migration != nil, handover == .host else { return transport.close() }
        let id = ObjectIdentifier(transport)
        migration?.pending[id] = transport
        transport.onReceive = { [weak self, weak transport] data in
            guard let self, let transport else { return }
            self.handoverResync(data, from: transport)
        }
        transport.onClose = { [weak self] in self?.migration?.pending[id] = nil }
    }

    // MARK: - Internal

    private func attach(_ newLinks: [Int: Transport]) {
        links = newLinks
        for (player, transport) in newLinks {
            transport.onReceive = { [weak self] data in self?.receive(data, from: player) }
            transport.onClose = { [weak self] in self?.linkClosed(player) }
        }
    }

    /// Host: to all guests still in; guest: to the host.
    private func broadcast(_ message: NetMessage, except: Int? = nil) {
        let data = message.encoded()
        for (player, transport) in links where player != except && !gone.contains(player) {
            send(data, over: transport)
        }
    }

    /// Sends our own commands up to and including `tick` in one bundle (also when there are none), with the
    /// checksums since the last bundle, the answers to pings and, every few seconds, an own ping.
    private func flush(upTo tick: Int) {
        guard status == .running, tick > lastSentTick else { return }
        var bundle = NetBundle(player: localPlayer, upTo: tick)
        for t in (lastSentTick + 1)...tick {
            let commands = outgoing.removeValue(forKey: t) ?? []
            history.append(NetPacket(player: localPlayer, tick: t, commands: commands))
            bundle.commands += commands
        }
        lastSentTick = tick
        let now = clock()
        if !pendingHashes.isEmpty {
            bundle.hashes = pendingHashes
            pendingHashes = []
        }
        if !echoes.isEmpty {
            bundle.pongs = echoes.mapValues { $0.value + Self.milliseconds(now.timeIntervalSince($0.at)) }
            echoes = [:]
        }
        if lastPing.map({ now.timeIntervalSince($0) >= Self.pingInterval || now < $0 }) ?? true {
            bundle.ping = Self.milliseconds(now.timeIntervalSinceReferenceDate)
            lastPing = now
        }
        broadcast(.inputs(bundle))
    }

    /// Milliseconds of a plausible clock (about 35,000 years either way).
    private static let clockLimit = 1 << 50

    private static func milliseconds(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, abs(seconds) < 1e12 else { return 0 }
        return Int((seconds * 1000).rounded())
    }

    /// Ping and pong of a bundle from the device at the other end of `link` (not forwarded ones).
    private func measure(_ bundle: NetBundle, from link: Int) {
        let now = clock()
        // Values from another device: a ping far outside any clock is not answered (it could overflow),
        // only plausible round trips count (0 to 30 s).
        if let ping = bundle.ping, (-Self.clockLimit...Self.clockLimit).contains(ping) { echoes[link] = (ping, now) }
        guard let pong = bundle.pongs?[localPlayer] else { return }
        let (rtt, overflow) = Self.milliseconds(now.timeIntervalSinceReferenceDate).subtractingReportingOverflow(pong)
        guard !overflow, (0...30_000).contains(rtt) else { return }
        roundTrips[link, default: []].append(rtt)
        roundTrips[link] = Array(roundTrips[link]!.suffix(Self.roundTripSamples))
        updateInputDelay()
    }

    /// Input delay from the largest round trip to a device still connected.
    private func updateInputDelay() {
        let current = roundTrips.filter { links[$0.key] != nil && !gone.contains($0.key) }
        let worst = current.values.compactMap({ $0.max() }).max()
        roundTripMilliseconds = worst
        let tickMs = max(1, game.rules.tickMilliseconds)
        // Two people: the way to the other device is half the round trip. Three or four: a command of a guest
        // goes via the host to the other guests – two ways, about a whole round trip.
        let way = setup.humans.count > 2 ? (worst ?? 0) : (worst ?? 0) / 2
        let latency = (way + tickMs - 1) / tickMs
        inputDelay = min(max(Self.maxInputDelay, bundleTicks + 1),
                         max(game.rules.inputDelayTicks, bundleTicks + 1 + latency + 1))
    }

    private func send(_ data: Data, over transport: Transport) {
        messagesSent += 1
        bytesSent += data.count
        transport.send(data)
    }

    private func receive(_ data: Data, from link: Int) {
        messagesReceived += 1
        bytesReceived += data.count
        guard status == .running, migration == nil, let message = NetMessage.decode(data) else { return }
        switch message {
        case let .inputs(bundle):
            let player = bundle.player
            if isHost {
                guard player == link, !gone.contains(link) else { return }
                accept(bundle.commands, of: player, upTo: bundle.upTo)
                // Forward to the other guests (they are connected only to the host).
                for (other, transport) in links where other != link && !gone.contains(other) {
                    send(data, over: transport)
                }
            } else {
                guard !gone.contains(player) else { return }
                accept(bundle.commands, of: player, upTo: bundle.upTo)
            }
            // Checksums and round trip only from the device at the other end (forwarded bundles carry those
            // of another guest).
            guard player == link else { return }
            for hash in bundle.hashes ?? [] {
                remoteHashes[link, default: [:]][hash.tick] = hash.value
                compareHash(hash.tick, with: link)
            }
            measure(bundle, from: link)
        case let .pause(player, on):
            if isHost { hostReceivedPause(from: link, on: on) } else { guestReceivedPause(of: player, on: on) }
        case let .pauseExpired(player):
            guard !isHost else { return }
            if player == localPlayer { outForPause() } else { pauseExpired(of: player) }
        case let .dropped(player):
            guard !isHost else { return }
            dropped(player)
        case let .desynced(tick):
            setStatus(.desynced(tick: tick))
        case .leave:
            onLog?("net: player \(link) left")
            if isHost { drop(link, explicit: true) } else { hostGone(explicit: true) }
        case let .rematch(player):
            receivedRematch(player, from: link)
        case let .welcome(setup, player):
            receivedRematchWelcome(setup, player: player, from: link)
        case .hello, .lobby, .reject, .resync, .resume:
            break
        }
    }

    /// The commands of another person up to and including `upTo`; each tick counts once (a handover may
    /// bring a packet again). Ticks without commands are empty.
    private func accept(_ commands: [ScheduledCommand], of player: Int, upTo: Int) {
        guard let ready = readyTick[player], upTo > ready, upTo - ready <= Self.maxBundleSpan else { return }
        readyTick[player] = upTo
        let valid = commands.filter { $0.tick > ready && $0.tick <= upTo }
        for t in (ready + 1)...upTo {
            history.append(NetPacket(player: player, tick: t, commands: valid.filter { $0.tick == t }))
        }
        // Only the host puts another player's command into its bundles: the surrender of a player who is out.
        for c in valid where c.tick >= game.tick && (c.player == player || c.command == .surrender)
                && game.players.indices.contains(c.player) {
            game.schedule(c)
        }
    }

    private func linkClosed(_ player: Int) {
        onLog?("net: connection to player \(player) closed")
        if isHost { drop(player, explicit: false) } else { hostGone(explicit: false) }
    }

    private func compareHash(_ tick: Int, with player: Int) {
        guard let mine = localHashes[tick], let theirs = remoteHashes[player]?[tick] else { return }
        remoteHashes[player]?[tick] = nil
        guard mine != theirs else { return }
        if isHost && game.players[player].isDead {
            // A player who is out and only watches has fallen out of step (e.g. after a handover): only
            // this device leaves, the game is not affected.
            return drop(player, explicit: true)
        }
        if isHost { broadcast(.desynced(tick: tick)) }
        setStatus(.desynced(tick: tick))
    }

    // MARK: Pause

    /// Host: a guest pressed pause or continue. The host decides whose pause counts.
    private func hostReceivedPause(from player: Int, on: Bool) {
        guard !gone.contains(player) else { return }
        let now = clock()
        if on {
            if let current = pause, current.player != player, current.resumesAt == nil {
                // Another pause came first (with two pauses at the same moment: the host's): tell the guest.
                links[player]?.send(NetMessage.pause(player: current.player, on: true).encoded())
                return
            }
            if let current = pause, current.player == player {
                pause?.resumesAt = nil
            } else {
                pause = Pause(player: player, since: now)
            }
            broadcast(.pause(player: player, on: true), except: player)
        } else {
            guard let current = pause, current.player == player, current.resumesAt == nil else { return }
            pause?.resumesAt = now.addingTimeInterval(Self.resumeCountdown)
            broadcast(.pause(player: player, on: false), except: player)
        }
    }

    /// Guest: the host reports a pause (it may replace our own one if another one came first).
    private func guestReceivedPause(of player: Int, on: Bool) {
        if on {
            if let current = pause, current.player == player {
                pause?.resumesAt = nil                      // paused again during the countdown
            } else {
                pause = Pause(player: player, since: clock())
            }
        } else if let current = pause, current.player == player, current.resumesAt == nil {
            pause?.resumesAt = clock().addingTimeInterval(Self.resumeCountdown)
        }
    }

    /// Host: a pause lasted too long. The player who paused is out; the others go on after the countdown.
    private func expirePause(of player: Int) {
        guard let current = pause else { return }
        let now = clock()
        pause = Pause(player: player, since: current.since, resumesAt: now.addingTimeInterval(Self.resumeCountdown))
        broadcast(.pauseExpired(player: player))
        if player == localPlayer {
            if !game.isFinished && !game.players[localPlayer].isDead { issue(.surrender) }
        } else {
            // The guest closes the connection itself when it learns it (closing here could cut off the message).
            remove(player)
        }
        onEvent?(.pauseExpired(player))
    }

    /// Guest: another player's pause lasted too long; that player is out, the countdown runs.
    private func pauseExpired(of player: Int) {
        let now = clock()
        pause = Pause(player: player, since: pause?.since ?? now, resumesAt: now.addingTimeInterval(Self.resumeCountdown))
        if player != hostPlayer { gone.insert(player) }
        onEvent?(.pauseExpired(player))
    }

    /// Guest: the own pause lasted too long. Out of the game; this device stops playing.
    private func outForPause() {
        pause = nil
        abandonHandover()
        closeLinks()
        if !game.isFinished && !game.players[localPlayer].isDead {
            // Only here: the player is out, the game goes on on the other devices without this one.
            game.schedule(ScheduledCommand(tick: game.tick, player: localPlayer, sequence: .max, command: .surrender))
            game.step()
        }
        setStatus(.pauseExpired)
    }

    // MARK: Players leaving

    /// Host: a guest has left (`explicit`) or lost the connection.
    private func drop(_ player: Int, explicit: Bool) {
        guard status == .running, !gone.contains(player) else { return }
        if !explicit && isLastOpponent(player) { return lostConnection() }
        if let transport = links.removeValue(forKey: player) {
            transport.onReceive = nil
            transport.onClose = nil
            transport.close()
        }
        remove(player)
        if pause?.player == player { pause = nil }
        broadcast(.dropped(player: player))
        onEvent?(.playerLeft(player))
    }

    /// Host: nobody waits for `player` any more; the player surrenders in the next own packet, so
    /// that every device lets the player drop out in the same tick.
    private func remove(_ player: Int) {
        gone.insert(player)
        guard !game.isFinished, !game.players[player].isDead else { return }
        // All packets of the player that arrived here have been forwarded already; later ticks count as empty.
        let tick = max(nextCommandTick, (readyTick[player] ?? 0) + 1)
        let surrender = ScheduledCommand(tick: tick, player: player, sequence: .max, command: .surrender)
        game.schedule(surrender)
        outgoing[tick, default: []].append(surrender)
    }

    /// Guest: the host reports that another guest is out.
    private func dropped(_ player: Int) {
        gone.insert(player)
        if pause?.player == player { pause = nil }
        onEvent?(.playerLeft(player))
    }

    /// Whether `player` is the last other person still in the game: losing the connection to them leaves
    /// nobody who could confirm a win.
    private func isLastOpponent(_ player: Int) -> Bool {
        guard !game.isFinished, !game.players[player].isDead else { return false }
        return !remoteHumans.contains { $0 != player && !gone.contains($0) && !game.players[$0].isDead }
    }

    /// The connection to the last opponent dropped without a goodbye: the game stands still until the app
    /// decides who is to blame (otherwise both sides would count the other one's surrender and both win).
    private func lostConnection() {
        pause = nil
        closeLinks()
        setStatus(.connectionLost)
    }

    /// After `connectionLost`, when this device is online: the others lost their network or stopped the app.
    /// They give up; the game goes on here (to the end, or against the computers).
    public func opponentsGone() {
        guard status == .connectionLost, !game.isFinished else { return }
        let others = remoteHumans.filter { !gone.contains($0) && !game.players[$0].isDead }
        for player in others {
            gone.insert(player)
            let tick = max(game.tick, (readyTick[player] ?? 0) + 1)
            game.schedule(ScheduledCommand(tick: tick, player: player, sequence: .max, command: .surrender))
        }
        setStatus(.running)
        for player in others { onEvent?(.playerLeft(player)) }
    }

    /// Guest: the connection to the host is gone (host left – `explicit` –, crashed, or the network dropped).
    private func hostGone(explicit: Bool) {
        guard status == .running, migration == nil else { return }
        closeLinks()
        let now = clock()
        // Back from a pause that was too long (the app was in the background, the connection has dropped
        // meanwhile): it is not the others who have lost, but we.
        if let current = pause, current.player == localPlayer, current.resumesAt == nil,
           now.timeIntervalSince(current.since) >= Self.pauseLimit {
            return outForPause()
        }
        guard !game.isFinished else { return }
        let host = hostPlayer
        let others = remoteHumans.filter { $0 != host && !gone.contains($0) && !game.players[$0].isDead }
        if !others.isEmpty {
            pause = nil
            // Without a code the devices cannot find each other again.
            guard !setup.code.isEmpty else { return setStatus(.hostGone) }
            let candidates = setup.humans.filter { $0 != host && !gone.contains($0) }
            migration = Migration(oldHost: host, candidates: candidates, since: now)
            return nextHandoverRole()
        }
        // Only the host was left besides us and the computers.
        let hostPauseExpired = pause.map {
            $0.player == host && $0.resumesAt == nil && now.timeIntervalSince($0.since) >= Self.pauseLimit - 5
        } ?? false
        // Lost without a goodbye: nobody wins. Otherwise the host gives up, the game goes on here.
        if !explicit && !hostPauseExpired && !game.players[host].isDead { return lostConnection() }
        pause = nil
        gone.insert(host)
        if !game.players[host].isDead {
            let tick = max(game.tick, (readyTick[host] ?? 0) + 1)
            game.schedule(ScheduledCommand(tick: tick, player: host, sequence: .max, command: .surrender))
        }
        onEvent?(hostPauseExpired ? .pauseExpired(host) : .playerLeft(host))
    }

    // MARK: Handover

    /// The first candidate becomes the new host; the others connect to it.
    private func nextHandoverRole() {
        guard var m = migration else { return }
        if let link = m.link {
            link.onReceive = nil
            link.onClose = nil
            link.close()
            m.link = nil
        }
        m.since = clock()
        migration = m
        guard let first = m.candidates.first else { return handoverFailed() }
        let role: Handover = first == localPlayer ? .host : .guest(of: first)
        handover = role
        onHandover?(role)
        if role == .host && m.candidates.count == 1 { finishHandover() }   // nobody else to wait for
    }

    private func updateHandover(_ m: Migration) {
        let waited = clock().timeIntervalSince(m.since)
        switch handover {
        case .host:
            if waited >= Self.handoverWaitTimeout { finishHandover() }
        case let .guest(host):
            if waited >= (m.link == nil ? Self.handoverConnectTimeout : Self.handoverResumeTimeout) { handoverLost(host) }
        case nil:
            break
        }
    }

    /// Guest: the candidate cannot be reached (or did not answer): try the next one.
    private func handoverLost(_ candidate: Int) {
        guard migration != nil else { return }
        migration?.candidates.removeAll { $0 == candidate }
        nextHandoverRole()
    }

    /// Guest: the new host answers.
    private func handoverMessage(_ data: Data, from host: Int) {
        guard let m = migration, let link = m.link, handover == .guest(of: host) else { return }
        switch NetMessage.decode(data) {
        case let .resume(packets, ended):
            completeHandover(host: host, links: [host: link], packets: packets, ended: ended)
        case .reject:
            handoverLost(host)
        default:
            break
        }
    }

    /// New host: a device reports its state.
    private func handoverResync(_ data: Data, from transport: Transport) {
        guard var m = migration, handover == .host, case let .resync(resync) = NetMessage.decode(data) else { return }
        m.pending[ObjectIdentifier(transport)] = nil
        let player = resync.player
        guard player != localPlayer, m.candidates.contains(player), m.guests[player] == nil else {
            migration = m
            transport.onReceive = nil
            transport.onClose = nil
            transport.send(NetMessage.reject(reason: LobbyFailure.closed.rawValue).encoded())
            return transport.close()
        }
        transport.onReceive = nil
        transport.onClose = { [weak self] in self?.migration?.guests[player] = nil }
        m.guests[player] = (transport, resync)
        migration = m
        if Set(m.guests.keys) == Set(m.candidates.filter { $0 != localPlayer }) { finishHandover() }
    }

    /// New host: everybody is there (or the time is up). Puts together the last packets of all devices
    /// and determines when the players who did not come along drop out.
    private func finishHandover() {
        guard let m = migration, handover == .host else { return }
        for transport in m.pending.values {
            transport.onReceive = nil
            transport.onClose = nil
            transport.close()
        }
        // Alone: we cannot tell whether the others are gone or only we are cut off.
        guard !m.guests.isEmpty else { return handoverFailed() }
        let resyncs = m.guests.values.map { $0.resync }
        var known: [Int: [Int: [ScheduledCommand]]] = [:]
        for packet in history + resyncs.flatMap(\.packets) {
            known[packet.player, default: [:]][packet.tick] = packet.commands
        }
        let ticks = [game.tick] + resyncs.map(\.nextTick)
        let firstTick = ticks.min()!, lastTick = ticks.max()!
        let continuing = Set([localPlayer] + m.guests.keys)
        // A player who did not come along drops out after the last tick of which any device has a packet –
        // and not before a tick some device has already computed.
        let ended = setup.humans.filter { !continuing.contains($0) }.map { player in
            NetEnd(player: player, tick: max((known[player]?.keys.max() ?? -1) + 1, lastTick))
        }
        let packets = known.flatMap { player, byTick in
            byTick.filter { $0.key >= firstTick }.map { NetPacket(player: player, tick: $0.key, commands: $0.value) }
        }.sorted { ($0.tick, $0.player) < ($1.tick, $1.player) }
        let message = NetMessage.resume(packets: packets, ended: ended).encoded()
        var newLinks: [Int: Transport] = [:]
        for (player, guest) in m.guests {
            newLinks[player] = guest.transport
            guest.transport.send(message)
        }
        completeHandover(host: localPlayer, links: newLinks, packets: packets, ended: ended)
    }

    /// All devices: continue with the new host from the same state.
    private func completeHandover(host: Int, links newLinks: [Int: Transport], packets: [NetPacket], ended: [NetEnd]) {
        migration = nil
        hostPlayer = host
        attach(newLinks)
        for packet in packets where packet.player != localPlayer {
            accept(packet.commands, of: packet.player, upTo: packet.tick)
        }
        var left: [Int] = []
        // From the new host: only players of this game count.
        for end in ended where setup.names.indices.contains(end.player) && end.player != localPlayer {
            if !gone.contains(end.player) { left.append(end.player) }
            gone.insert(end.player)
            if !game.isFinished && end.tick >= game.tick {
                game.schedule(ScheduledCommand(tick: end.tick, player: end.player, sequence: .max, command: .surrender))
            }
        }
        remoteHashes = [:]
        let now = clock()
        pause = Pause(player: host, since: now, resumesAt: now.addingTimeInterval(Self.resumeCountdown))
        handover = nil
        onHandover?(nil)
        for player in left { onEvent?(.playerLeft(player)) }
        onEvent?(.newHost(host))
    }

    private func handoverFailed() {
        abandonHandover()
        closeLinks()
        setStatus(.hostGone)
    }

    /// Ends a running handover without result (closes its connections).
    private func abandonHandover() {
        guard let m = migration else { return }
        migration = nil
        for transport in [m.link].compactMap({ $0 }) + m.guests.values.map({ $0.transport }) + Array(m.pending.values) {
            transport.onReceive = nil
            transport.onClose = nil
            transport.close()
        }
        if handover != nil {
            handover = nil
            onHandover?(nil)
        }
    }

    private func closeLinks() {
        for transport in links.values {
            transport.onReceive = nil
            transport.onClose = nil
            transport.close()
        }
        links = [:]
    }

    private func setStatus(_ new: Status) {
        guard status != new else { return }
        status = new
        onStatusChange?(new)
    }
}
