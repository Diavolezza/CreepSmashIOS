import Foundation

/// A game against the computer that can be continued later, even after the app has been closed.
///
/// The simulation is deterministic, so the setup of the game and the inputs of the player are enough:
/// continuing replays them, and the computer opponents decide exactly as before.
public struct SavedGame: Codable, Equatable, Sendable {
    /// A command of the player and the tick at which it was given.
    public struct Input: Codable, Equatable, Sendable {
        public let tick: Int
        public let command: Command
    }

    /// Simulation version the game was played with (`NetMessage.protocolVersion`); another version
    /// would compute differently, so such a game cannot be continued.
    public let version: Int
    public let mapID: String
    public let rules: Rules
    public let playerName: String
    public let opponents: [Bot.Level]
    public let opponentNames: [String]?
    public let seed: UInt64?
    public internal(set) var inputs: [Input] = []
    /// Ticks computed when the game was saved.
    public internal(set) var tick = 0
    /// When the game was saved.
    public internal(set) var date = Date()

    /// The game can be continued with this version of the app.
    public var canContinue: Bool { version == NetMessage.protocolVersion && GameMap.named(mapID) != nil }
}

extension LocalMatch {
    /// The game as it stands, for continuing it later.
    public var saved: SavedGame {
        var game = record
        game.tick = self.game.tick
        game.date = Date()
        return game
    }

    /// Rebuilds a saved game by replaying it. `eachTick` is called after every computed tick
    /// (to collect the statistics again). Returns nil if the game cannot be continued.
    public convenience init?(restoring saved: SavedGame, eachTick: (Game) -> Void = { _ in }) {
        guard saved.canContinue, let map = GameMap.named(saved.mapID) else { return nil }
        self.init(map: map, rules: saved.rules, playerName: saved.playerName, opponents: saved.opponents,
                  opponentNames: saved.opponentNames, seed: saved.seed)
        var next = 0
        while true {
            while next < saved.inputs.count, saved.inputs[next].tick == game.tick {
                issue(saved.inputs[next].command)
                next += 1
            }
            guard game.tick < saved.tick else { break }
            advance()
            eachTick(game)
            if game.isFinished { return nil }
        }
        guard next == saved.inputs.count else { return nil }
    }
}
