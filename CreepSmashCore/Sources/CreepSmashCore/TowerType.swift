public enum WeaponKind: String, Codable, Sendable {
    case laser, slower, splashLaser, slowerSplash, rocket
}

public struct TowerStats: Sendable {
    public let price: Int
    /// Range in pixels.
    public let range: Int
    /// Ticks between two shots.
    public let reloadTicks: Int
    public let damage: Int
    /// Splash radius in pixels (0 = no splash).
    public let splashRadius: Int
    /// Damage reduction at the edge of the splash radius in per mille (700 = 0.7).
    public let splashReductionPermille: Int
    /// Slowdown in per mille (300 = 30 %).
    public let slowPermille: Int
    public let slowTicks: Int
    public let weapon: WeaponKind
}

/// The 6 tower kinds of the original (values from TowerType.java), each with its levels.
public enum TowerKind: Int, CaseIterable, Codable, Sendable {
    case basic = 1, slow, splash, rocket, speed, ultimate

    public var name: String {
        switch self {
        case .basic: "Basic"
        case .slow: "Slow"
        case .splash: "Splash"
        case .rocket: "Rocket"
        case .speed: "Speed"
        case .ultimate: "Ultimate"
        }
    }

    public var maxLevel: Int { levels.count }

    /// Stats of level 1 ... maxLevel.
    public func stats(level: Int) -> TowerStats { levels[level - 1] }

    /// Name of the original's image file: level 1 = "1", level 2 = "11", level 3 = "12" ...
    public func imageName(level: Int) -> String {
        level == 1 ? "tower\(rawValue)" : "tower\(rawValue)\(level - 1)"
    }

    /// Default target strategy (see SPEC, section 5).
    public var defaultStrategy: TargetStrategy {
        switch self {
        case .basic, .splash: .closest
        case .slow: .fastest
        case .rocket, .speed, .ultimate: .weakest
        }
    }

    private var levels: [TowerStats] {
        switch self {
        case .basic: [
            .init(price: 50, range: 35, reloadTicks: 13, damage: 25, splashRadius: 0, splashReductionPermille: 0, slowPermille: 0, slowTicks: 0, weapon: .laser),
            .init(price: 100, range: 40, reloadTicks: 13, damage: 50, splashRadius: 0, splashReductionPermille: 0, slowPermille: 0, slowTicks: 0, weapon: .laser),
            .init(price: 750, range: 45, reloadTicks: 13, damage: 200, splashRadius: 0, splashReductionPermille: 0, slowPermille: 0, slowTicks: 0, weapon: .laser),
            .init(price: 2_000, range: 50, reloadTicks: 13, damage: 750, splashRadius: 0, splashReductionPermille: 0, slowPermille: 0, slowTicks: 0, weapon: .laser),
        ]
        case .slow: [
            .init(price: 100, range: 35, reloadTicks: 15, damage: 25, splashRadius: 0, splashReductionPermille: 0, slowPermille: 300, slowTicks: 40, weapon: .slower),
            .init(price: 200, range: 45, reloadTicks: 16, damage: 50, splashRadius: 0, splashReductionPermille: 0, slowPermille: 350, slowTicks: 40, weapon: .slower),
            .init(price: 400, range: 50, reloadTicks: 17, damage: 75, splashRadius: 0, splashReductionPermille: 0, slowPermille: 450, slowTicks: 50, weapon: .slower),
            .init(price: 3_000, range: 55, reloadTicks: 18, damage: 100, splashRadius: 25, splashReductionPermille: 700, slowPermille: 500, slowTicks: 50, weapon: .slowerSplash),
        ]
        case .splash: [
            .init(price: 250, range: 40, reloadTicks: 15, damage: 50, splashRadius: 35, splashReductionPermille: 700, slowPermille: 0, slowTicks: 0, weapon: .splashLaser),
            .init(price: 750, range: 45, reloadTicks: 12, damage: 200, splashRadius: 35, splashReductionPermille: 700, slowPermille: 0, slowTicks: 0, weapon: .splashLaser),
            .init(price: 3_000, range: 55, reloadTicks: 10, damage: 400, splashRadius: 35, splashReductionPermille: 600, slowPermille: 0, slowTicks: 0, weapon: .splashLaser),
            .init(price: 7_500, range: 60, reloadTicks: 10, damage: 1_100, splashRadius: 35, splashReductionPermille: 500, slowPermille: 0, slowTicks: 0, weapon: .splashLaser),
        ]
        case .rocket: [
            .init(price: 1_000, range: 50, reloadTicks: 75, damage: 1_000, splashRadius: 25, splashReductionPermille: 800, slowPermille: 0, slowTicks: 0, weapon: .rocket),
            .init(price: 3_000, range: 60, reloadTicks: 75, damage: 2_500, splashRadius: 25, splashReductionPermille: 800, slowPermille: 0, slowTicks: 0, weapon: .rocket),
            .init(price: 7_500, range: 70, reloadTicks: 65, damage: 7_500, splashRadius: 30, splashReductionPermille: 700, slowPermille: 0, slowTicks: 0, weapon: .rocket),
            .init(price: 15_000, range: 80, reloadTicks: 60, damage: 15_000, splashRadius: 35, splashReductionPermille: 600, slowPermille: 0, slowTicks: 0, weapon: .rocket),
        ]
        case .speed: [
            .init(price: 1_000, range: 50, reloadTicks: 9, damage: 225, splashRadius: 0, splashReductionPermille: 0, slowPermille: 0, slowTicks: 0, weapon: .laser),
            .init(price: 3_000, range: 55, reloadTicks: 7, damage: 450, splashRadius: 0, splashReductionPermille: 0, slowPermille: 0, slowTicks: 0, weapon: .laser),
            .init(price: 7_500, range: 60, reloadTicks: 5, damage: 1_100, splashRadius: 0, splashReductionPermille: 0, slowPermille: 0, slowTicks: 0, weapon: .laser),
            .init(price: 15_000, range: 65, reloadTicks: 3, damage: 1_800, splashRadius: 0, splashReductionPermille: 0, slowPermille: 0, slowTicks: 0, weapon: .laser),
        ]
        case .ultimate: [
            .init(price: 20_000, range: 100, reloadTicks: 100, damage: 25_000, splashRadius: 0, splashReductionPermille: 0, slowPermille: 0, slowTicks: 0, weapon: .laser),
            .init(price: 50_000, range: 150, reloadTicks: 50, damage: 40_000, splashRadius: 0, splashReductionPermille: 0, slowPermille: 0, slowTicks: 0, weapon: .laser),
        ]
        }
    }
}

/// Target strategies of a tower.
public enum TargetStrategy: String, CaseIterable, Codable, Sendable {
    case closest, farthest, fastest, strongest, weakest
}
