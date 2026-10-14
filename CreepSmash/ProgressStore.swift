import SwiftUI
import CreepSmashCore

/// Keeps the player's statistics, leaderboard and achievements (`PlayerRecord`) on the device.
@MainActor
@Observable
final class ProgressStore {
    static let shared = ProgressStore()

    private static let key = "playerRecord.v1"
    private(set) var record: PlayerRecord

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(PlayerRecord.self, from: data) {
            record = saved
        } else {
            record = PlayerRecord()
        }
    }

    /// Adds a finished game, saves and reports what is new.
    func add(_ summary: GameSummary, playerName: String) -> PlayerRecord.Outcome {
        let outcome = record.add(summary, playerName: playerName)
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        return outcome
    }
}

/// Texts and look of the achievements.
extension Achievement {
    var title: String {
        switch id {
        case "wins": L("Victor")
        case "winsHard": L("Tough nut")
        case "flawless": L("Flawless")
        case "closeCall": L("Close call")
        case "fastWin": L("Lightning win")
        case "efficient": L("Efficient")
        case "noZombies": L("No zombies")
        case "lean": L("Lean")
        case "allMaps": L("Globetrotter")
        case "streak": L("On a roll")
        case "onlineWins": L("Duelist")
        case "creepsKilled": L("Exterminator")
        case "creepsSent": L("Invader")
        case "towersBuilt": L("Master builder")
        case "income": L("Tycoon")
        case "ultimate": L("Ultimate")
        case "colossus": L("Colossal")
        case "games": L("Veteran")
        default: id
        }
    }

    /// What has to be done for the given threshold.
    func requirement(_ threshold: Int) -> String {
        let n = Format.credits(threshold)
        switch id {
        case "wins": return L("Win \(n) games")
        case "winsHard": return L("Beat the computer on Hard \(n) times")
        case "flawless": return L("Win \(n) games without losing a life")
        case "closeCall": return L("Win with only one life left")
        case "fastWin": return L("Win \(n) games within 8 minutes")
        case "efficient": return L("Win \(n) games with at least \(100 - PlayerRecord.efficientPercent) % lower defense costs than your opponents")
        case "noZombies": return L("Win \(n) games of at least 5 minutes without a zombie tower")
        case "lean": return L("Win \(n) games with less put into towers than every opponent")
        case "allMaps": return L("Win on every map")
        case "streak": return L("Win \(n) games in a row")
        case "onlineWins": return L("Win \(n) multiplayer games")
        case "creepsKilled": return L("Shoot down \(n) creeps")
        case "creepsSent": return L("Send \(n) creeps")
        case "towersBuilt": return L("Build \(n) towers")
        case "income": return L("Reach an income of \(n)")
        case "ultimate": return L("Build an Ultimate tower")
        case "colossus": return L("Send a Fat Colossus")
        case "games": return L("Play \(n) games")
        default: return n
        }
    }

    var symbol: String {
        switch id {
        case "wins", "winsHard": "trophy.fill"
        case "flawless": "heart.fill"
        case "closeCall": "heart.slash.fill"
        case "fastWin": "bolt.fill"
        case "efficient": "leaf.fill"
        case "noZombies": "moon.zzz.fill"
        case "lean": "scalemass.fill"
        case "allMaps": "map.fill"
        case "streak": "flame.fill"
        case "onlineWins": "person.2.fill"
        case "creepsKilled": "scope"
        case "creepsSent": "arrow.up.right"
        case "towersBuilt": "building.2.fill"
        case "income": "dollarsign.circle.fill"
        case "ultimate": "star.fill"
        case "colossus": "tortoise.fill"
        default: "rosette"
        }
    }

    /// Medal color of a tier: bronze, silver, gold (one-time achievements are gold).
    func color(tier: Int) -> Color {
        guard tier > 0 else { return .gray.opacity(0.4) }
        let rank = tiers.count == 1 ? 3 : tier + (3 - tiers.count)
        switch rank {
        case ...1: return Color(red: 0.8, green: 0.5, blue: 0.25)
        case 2: return Color(white: 0.8)
        default: return Theme.gold
        }
    }
}
