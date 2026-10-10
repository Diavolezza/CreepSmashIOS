import Foundation

// Network play using the lockstep method.
//
// Both devices compute the whole game. Only the commands are transmitted, each with the tick in which
// they are executed. Each device sends a packet for EVERY tick (usually empty). A device computes
// tick t only once the opponent's packet for t has arrived; until then it waits. The input delay
// (`Rules.inputDelayTicks`) bridges the network latency, so that normally there is no waiting.
// A checksum over the game state reveals if the devices drift apart anyway.
//
// All methods must be called on the same thread (in the app: the main thread).

/// Connection to the other player, e.g. TCP on the local network or Game Center.
/// Must deliver messages completely, in order and without loss.
public protocol Transport: AnyObject {
    func send(_ data: Data)
    /// Called for every received message.
    var onReceive: ((Data) -> Void)? { get set }
    /// Called when the connection drops (not after our own `close()`).
    var onClose: (() -> Void)? { get set }
    func close()
}

/// What both devices agree on before the start. The host (player 0) decides it.
public struct MatchSetup: Codable, Equatable, Sendable {
    public var mapID: String
    public var rules: Rules
    /// Index = player number; 0 is the host.
    public var names: [String]

    public init(mapID: String, rules: Rules = .standard, names: [String]) {
        self.mapID = mapID
        self.rules = rules
        self.names = names
    }
}

/// Messages between the devices.
public enum NetMessage: Codable, Equatable, Sendable {
    /// Guest → host.
    case hello(protocolVersion: Int, name: String)
    /// Host → guest: the game starts with these settings.
    case welcome(MatchSetup)
    /// Host → guest: rejected; `reason` is the raw value of a `HandshakeFailure`.
    case reject(reason: String)
    /// Commands of one player for one tick (usually empty).
    case input(tick: Int, commands: [ScheduledCommand])
    /// Checksum of the state after computing `tick`.
    case hash(tick: Int, value: UInt64)
    /// Pause on (`true`, applies to both) or the one who paused continues (`false`: countdown, then both go on).
    case pause(Bool)
    /// The pause of the receiver lasted longer than `NetworkMatch.pauseLimit`: the receiver has lost.
    case pauseExpired
    /// Player leaves the game.
    case leave

    /// Must be increased on every change to rules, simulation or messages – only identical
    /// versions compute identically.
    public static let protocolVersion = 5

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    public static func decode(_ data: Data) -> NetMessage? {
        try? JSONDecoder().decode(NetMessage.self, from: data)
    }
}

/// Connection setup: the guest introduces itself, the host replies with the settings.
/// Afterwards a `NetworkMatch` is created on both sides.
public final class Handshake {
    /// Why setting up the game failed. The app turns this into a message in the player's language.
    public enum Failure: String, Sendable {
        case connectionLost, otherVersion, unknownMap
    }

    public enum Result {
        case ready(NetworkMatch)
        case failed(Failure)
    }

    private let transport: Transport
    private var completion: ((Result) -> Void)?

    private init(transport: Transport, completion: @escaping (Result) -> Void) {
        self.transport = transport
        self.completion = completion
    }

    /// Host: waits for `hello`, adds the guest's name and starts.
    @discardableResult
    public static func host(transport: Transport, mapID: String, rules: Rules = .standard, name: String,
                            completion: @escaping (Result) -> Void) -> Handshake {
        let h = Handshake(transport: transport, completion: completion)
        transport.onClose = { h.finish(.failed(.connectionLost)) }
        // The closures keep the handshake alive until the game replaces them or it fails.
        transport.onReceive = { data in
            guard case let .hello(version, guestName) = NetMessage.decode(data) else { return }
            guard version == NetMessage.protocolVersion else {
                transport.send(NetMessage.reject(reason: Failure.otherVersion.rawValue).encoded())
                h.finish(.failed(.otherVersion))
                return
            }
            let setup = MatchSetup(mapID: mapID, rules: rules, names: [name, guestName])
            transport.send(NetMessage.welcome(setup).encoded())
            guard let match = NetworkMatch(setup: setup, localPlayer: 0, transport: transport) else {
                return h.finish(.failed(.unknownMap))
            }
            h.finish(.ready(match))
        }
        return h
    }

    /// Guest: introduces itself and waits for the settings.
    @discardableResult
    public static func join(transport: Transport, name: String, completion: @escaping (Result) -> Void) -> Handshake {
        let h = Handshake(transport: transport, completion: completion)
        transport.onClose = { h.finish(.failed(.connectionLost)) }
        // The closures keep the handshake alive until the game replaces them or it fails.
        transport.onReceive = { data in
            switch NetMessage.decode(data) {
            case let .welcome(setup):
                guard let match = NetworkMatch(setup: setup, localPlayer: 1, transport: transport) else {
                    return h.finish(.failed(.unknownMap))
                }
                h.finish(.ready(match))
            case let .reject(reason):
                h.finish(.failed(Failure(rawValue: reason) ?? .otherVersion))
            default:
                break
            }
        }
        transport.send(NetMessage.hello(protocolVersion: NetMessage.protocolVersion, name: name).encoded())
        return h
    }

    private func finish(_ result: Result) {
        guard let completion else { return }
        self.completion = nil
        if case .failed = result {
            transport.onReceive = nil
            transport.onClose = nil
            transport.close()
        }
        completion(result)
    }
}

/// Game against a human on another device.
public final class NetworkMatch: Match {
    public enum Status: Equatable {
        case running
        /// Opponent has left the game or the connection has dropped.
        case opponentGone
        /// The devices computed differently (bug in the simulation).
        case desynced(tick: Int)
        /// A pause lasted longer than `pauseLimit`; the player who paused has lost.
        case pauseExpired(loser: Int)
    }

    /// A pause. Only the player who paused can end it; then a countdown runs on both devices.
    public struct Pause: Equatable, Sendable {
        public let player: Int
        public let since: Date
        /// The game goes on at this moment (countdown running); nil while it is still paused.
        public internal(set) var resumesAt: Date?
    }

    /// If the player who paused does not continue within this time, the other one wins.
    public static let pauseLimit: TimeInterval = 120
    /// Countdown before the game goes on after a pause.
    public static let resumeCountdown: TimeInterval = 3
    /// The current pause (nil: running). No ticks are computed while it lasts, countdown included.
    public private(set) var pause: Pause?
    public var isPaused: Bool { pause != nil }
    /// Clock for the pause (tests set their own).
    public var clock: () -> Date = Date.init

    public let game: Game
    public let localPlayer: Int
    public let setup: MatchSetup
    public private(set) var status: Status = .running
    /// Opponent pressed or released pause.
    public var onPeerPause: ((Bool) -> Void)?
    /// Status has changed.
    public var onStatusChange: ((Status) -> Void)?
    /// Interval between checksums in ticks.
    public var hashInterval = 20

    private let transport: Transport
    private var remotePlayer: Int { 1 - localPlayer }
    private var sequence = 0
    /// Own commands not yet sent, keyed by execution tick.
    private var outgoing: [Int: [ScheduledCommand]] = [:]
    /// Last tick for which our own packet has already been sent.
    private var lastSentTick: Int
    /// Last tick for which the opponent's packet has arrived (`Int.max` if the opponent is gone).
    private var remoteReadyTick: Int
    private var localHashes: [Int: UInt64] = [:]
    private var remoteHashes: [Int: UInt64] = [:]

    public init?(setup: MatchSetup, localPlayer: Int, transport: Transport) {
        guard setup.names.count == 2, let map = GameMap.named(setup.mapID) else { return nil }
        self.setup = setup
        self.localPlayer = localPlayer
        self.transport = transport
        game = Game(map: map, playerNames: setup.names, rules: setup.rules)
        // For the first ticks (before the input delay) there are no packets – they count as empty.
        lastSentTick = setup.rules.inputDelayTicks - 1
        remoteReadyTick = setup.rules.inputDelayTicks - 1
        transport.onReceive = { [weak self] data in self?.receive(data) }
        transport.onClose = { [weak self] in self?.opponentGone() }
    }

    /// Is the game currently waiting for the opponent's packet?
    public var isWaitingForOpponent: Bool {
        !game.isFinished && remoteReadyTick < game.tick
    }

    /// Execution at the earliest after the input delay and never in a tick that has already been sent.
    private var nextCommandTick: Int { max(game.tick + game.rules.inputDelayTicks, lastSentTick + 1) }

    public func issue(_ command: Command) {
        let tick = nextCommandTick
        sequence += 1
        let scheduled = ScheduledCommand(tick: tick, player: localPlayer, sequence: sequence, command: command)
        game.schedule(scheduled)
        outgoing[tick, default: []].append(scheduled)
    }

    @discardableResult
    public func advance() -> Bool {
        guard !game.isFinished, pause == nil else { return false }
        if case .desynced = status { return false }
        flush(upTo: game.tick + game.rules.inputDelayTicks)
        guard remoteReadyTick >= game.tick else { return false }
        game.step()
        let done = game.tick - 1
        if done % hashInterval == 0 && status == .running {
            let value = game.checksum()
            localHashes[done] = value
            transport.send(NetMessage.hash(tick: done, value: value).encoded())
            compareHash(done)
        }
        return true
    }

    /// Pauses the game for both devices. Ignored while the opponent's pause lasts. Pausing again during
    /// the own countdown keeps the time already paused (the limit is not reset).
    public func pauseGame() {
        guard status == .running, !game.isFinished else { return }
        if let current = pause {
            guard current.player == localPlayer, current.resumesAt != nil else { return }
            pause?.resumesAt = nil
        } else {
            pause = Pause(player: localPlayer, since: clock())
        }
        transport.send(NetMessage.pause(true).encoded())
    }

    /// Ends the own pause: after the countdown both devices go on.
    public func resumeGame() {
        guard status == .running, let current = pause, current.player == localPlayer, current.resumesAt == nil else { return }
        pause?.resumesAt = clock().addingTimeInterval(Self.resumeCountdown)
        transport.send(NetMessage.pause(false).encoded())
    }

    /// To be called regularly (every frame): ends the countdown and enforces the pause limit.
    public func updatePause() {
        guard status == .running, let current = pause else { return }
        if let at = current.resumesAt {
            if clock() >= at { pause = nil }
        } else if clock().timeIntervalSince(current.since) >= Self.pauseLimit {
            end(loser: current.player)
        }
    }

    /// Surrenders and disconnects. The opponent wins.
    public func leave() {
        guard status == .running else { transport.close(); return }
        let tick = nextCommandTick
        issue(.surrender)
        flush(upTo: tick)
        transport.send(NetMessage.leave.encoded())
        transport.onReceive = nil
        transport.onClose = nil
        transport.close()
        status = .opponentGone
    }

    // MARK: - Internal

    /// Sends our own packets up to and including `tick` (empty ones too).
    private func flush(upTo tick: Int) {
        guard status == .running, tick > lastSentTick else { return }
        for t in (lastSentTick + 1)...tick {
            transport.send(NetMessage.input(tick: t, commands: outgoing.removeValue(forKey: t) ?? []).encoded())
        }
        lastSentTick = tick
    }

    private func receive(_ data: Data) {
        guard let message = NetMessage.decode(data) else { return }
        switch message {
        case let .input(tick, commands):
            for c in commands where c.player == remotePlayer && c.tick == tick && tick >= game.tick {
                game.schedule(c)
            }
            remoteReadyTick = max(remoteReadyTick, tick)
        case let .hash(tick, value):
            remoteHashes[tick] = value
            compareHash(tick)
        case .pause(true):
            if let current = pause {
                if current.player == remotePlayer {
                    pause?.resumesAt = nil                  // paused again during the countdown
                } else if current.resumesAt == nil && localPlayer < remotePlayer {
                    break                                   // both paused at the same moment: the host's pause counts
                } else {
                    pause = Pause(player: remotePlayer, since: clock())
                }
            } else {
                pause = Pause(player: remotePlayer, since: clock())
            }
            onPeerPause?(true)
        case .pause(false):
            if let current = pause, current.player == remotePlayer, current.resumesAt == nil {
                pause?.resumesAt = clock().addingTimeInterval(Self.resumeCountdown)
            }
            onPeerPause?(false)
        case .pauseExpired:
            end(loser: localPlayer)
        case .leave:
            opponentGone()
        case .hello, .welcome, .reject:
            break
        }
    }

    private func compareHash(_ tick: Int) {
        guard let mine = localHashes[tick], let theirs = remoteHashes[tick] else { return }
        localHashes[tick] = nil
        remoteHashes[tick] = nil
        if mine != theirs {
            setStatus(.desynced(tick: tick))
        }
    }

    /// A pause lasted too long: the player who paused surrenders, the game ends for this device
    /// (the other one learns it by `pauseExpired` or `leave`).
    private func end(loser: Int) {
        guard status == .running else { return }
        if loser == localPlayer {
            let tick = nextCommandTick
            issue(.surrender)
            flush(upTo: tick)
            transport.send(NetMessage.leave.encoded())
        } else {
            transport.send(NetMessage.pauseExpired.encoded())
            if !game.isFinished {
                let tick = max(game.tick, remoteReadyTick + 1)
                game.schedule(ScheduledCommand(tick: tick, player: remotePlayer, sequence: Int.max, command: .surrender))
            }
        }
        transport.onReceive = nil
        transport.onClose = nil
        remoteReadyTick = .max
        pause = nil
        setStatus(.pauseExpired(loser: loser))
    }

    /// The opponent is gone: they surrender in the next free tick, all further packets count as empty.
    private func opponentGone() {
        guard status == .running else { return }
        // Back from a pause that was too long (the app was in the background, the connection has
        // dropped meanwhile): it is not the opponent who has lost but we.
        if let current = pause, current.player == localPlayer, current.resumesAt == nil,
           clock().timeIntervalSince(current.since) >= Self.pauseLimit {
            return end(loser: localPlayer)
        }
        // The other side ended the game because of our timeout just now, or the other device's own
        // limit ran out first: report it as the expired pause it is.
        if let current = pause, current.player == remotePlayer, current.resumesAt == nil,
           clock().timeIntervalSince(current.since) >= Self.pauseLimit - 5 {
            return end(loser: remotePlayer)
        }
        pause = nil
        transport.onReceive = nil
        transport.onClose = nil
        if !game.isFinished {
            let tick = max(game.tick, remoteReadyTick + 1)
            game.schedule(ScheduledCommand(tick: tick, player: remotePlayer, sequence: Int.max, command: .surrender))
        }
        remoteReadyTick = .max
        setStatus(.opponentGone)
    }

    private func setStatus(_ new: Status) {
        guard status != new else { return }
        status = new
        onStatusChange?(new)
    }
}
