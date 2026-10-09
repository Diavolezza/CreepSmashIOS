import Foundation
import CreepSmashCore

/// The interrupted game against the computer, as a file in Application Support. There is at most one;
/// starting a new game against the computer replaces it.
enum SavedGameStore {
    private static var url: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("saved-game.json")
    }

    /// The saved game, if there is one that this version of the app can continue.
    static func load() -> SavedGame? {
        guard let data = try? Data(contentsOf: url),
              let game = try? JSONDecoder().decode(SavedGame.self, from: data), game.canContinue else { return nil }
        return game
    }

    static func save(_ game: SavedGame) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(game).write(to: url, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

extension SavedGame {
    var mode: GameMode {
        let level = opponents.first ?? .normal
        return opponents.count == 1 ? .computer(level) : .computerGroup(level, opponents: opponents.count)
    }

    /// One line for the menu: map, difficulty, opponents and game time.
    var caption: String {
        let map = GameMap.named(mapID).map { L(key: $0.name) } ?? mapID
        let count = opponents.count == 1 ? L("1 opponent") : L("\(opponents.count) opponents")
        let time = GameScreen.duration(ticks: max(0, tick - rules.startTick), rules: rules)
        return [map, (opponents.first ?? .normal).label, count, time].joined(separator: " · ")
    }
}
