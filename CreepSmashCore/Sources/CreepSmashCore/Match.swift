/// Common interface for a running game – locally against bots or (later) over the network via lockstep.
public protocol Match: AnyObject {
    var game: Game { get }
    var localPlayer: Int { get }
    /// Issues a command of the local player. It is executed after the input delay.
    func issue(_ command: Command)
    /// Computes one tick if possible. - Returns: `false` if waiting for other players.
    @discardableResult func advance() -> Bool
}

/// Game on one device against one or more computer opponents.
public final class LocalMatch: Match {
    public let game: Game
    public let localPlayer = 0
    private var bots: [Bot]
    private var sequences: [Int]
    /// Setup and inputs of the player, for saving the game (see `SavedGame`).
    private(set) var record: SavedGame

    public init(map: GameMap, rules: Rules = .standard, playerName: String,
                opponents: [Bot.Level] = [.normal], opponentNames: [String]? = nil, seed: UInt64? = nil) {
        let names = [playerName] + (opponentNames ?? opponents.indices.map { "Computer \($0 + 1)" })
        game = Game(map: map, playerNames: names, rules: rules)
        // With a seed every computer opponent gets its own playing style; without one (tests) all play
        // the neutral style, so games can be repeated exactly.
        let styles = seed.map { Bot.Style.varied(count: opponents.count, seed: $0) }
            ?? Array(repeating: .standard, count: opponents.count)
        bots = opponents.enumerated().map {
            Bot(player: $0.offset + 1, level: $0.element, map: map, style: styles[$0.offset])
        }
        sequences = Array(repeating: 0, count: names.count)
        record = SavedGame(version: NetMessage.protocolVersion, mapID: map.id, rules: rules, playerName: playerName,
                           opponents: opponents, opponentNames: opponentNames, seed: seed)
    }

    public func issue(_ command: Command) {
        record.inputs.append(SavedGame.Input(tick: game.tick, command: command))
        enqueue(command, player: localPlayer)
    }

    @discardableResult
    public func advance() -> Bool {
        for i in bots.indices {
            for command in bots[i].think(game: game) {
                enqueue(command, player: bots[i].player)
            }
        }
        game.step()
        return true
    }

    private func enqueue(_ command: Command, player: Int) {
        sequences[player] += 1
        game.schedule(ScheduledCommand(tick: game.tick + game.rules.inputDelayTicks, player: player,
                                       sequence: sequences[player], command: command))
    }
}
