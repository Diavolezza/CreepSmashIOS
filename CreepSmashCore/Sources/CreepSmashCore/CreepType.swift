public struct CreepStats: Sendable {
    public let price: Int
    public let income: Int
    public let health: Int
    /// Steps per tick (1000 steps = 1 path segment).
    public let speed: Int
    public let bounty: Int
    public let slowImmune: Bool
    /// Health points regenerated per tick.
    public let regeneration: Int
    public let name: String
    public let special: String
}

/// The 16 creep types of the original (values from CreepType.java).
public enum CreepType: Int, CaseIterable, Codable, Sendable {
    case mercury = 1, mako, fastNova, largeManta
    case demeter, ray, speedyRaider, bigToucan
    case vulture, shark, racingMamba, hugeTitan
    case zeus, phoenix, expressRaptor, fatColossus

    public var stats: CreepStats { Self.table[rawValue - 1] }

    /// Name of the original's image file (without extension). In the original, creep 9 referred to a missing file.
    public var imageName: String { "creep\(rawValue)" }

    private static let table: [CreepStats] = [
        .init(price: 50, income: 5, health: 300, speed: 70, bounty: 5, slowImmune: false, regeneration: 0, name: "Mercury", special: ""),
        .init(price: 100, income: 10, health: 700, speed: 65, bounty: 10, slowImmune: false, regeneration: 0, name: "Mako", special: ""),
        .init(price: 250, income: 25, health: 1_400, speed: 80, bounty: 25, slowImmune: false, regeneration: 0, name: "Fast Nova", special: ""),
        .init(price: 500, income: 50, health: 3_500, speed: 50, bounty: 50, slowImmune: false, regeneration: 0, name: "Large Manta", special: ""),
        .init(price: 1_000, income: 90, health: 7_000, speed: 60, bounty: 90, slowImmune: false, regeneration: 0, name: "Demeter", special: ""),
        .init(price: 2_000, income: 180, health: 14_000, speed: 65, bounty: 180, slowImmune: true, regeneration: 0, name: "Ray", special: "Slow immunity"),
        .init(price: 4_000, income: 360, health: 30_000, speed: 90, bounty: 360, slowImmune: false, regeneration: 0, name: "Speedy Raider", special: "fast"),
        .init(price: 8_000, income: 720, health: 80_000, speed: 60, bounty: 720, slowImmune: false, regeneration: 0, name: "Big Toucan", special: ""),
        .init(price: 15_000, income: 1_200, health: 140_000, speed: 70, bounty: 1_200, slowImmune: false, regeneration: 0, name: "Vulture", special: ""),
        .init(price: 25_000, income: 2_000, health: 250_000, speed: 75, bounty: 2_000, slowImmune: true, regeneration: 0, name: "Shark", special: "Slow immunity"),
        .init(price: 40_000, income: 3_200, health: 500_000, speed: 100, bounty: 3_200, slowImmune: false, regeneration: 0, name: "Racing Mamba", special: "fast"),
        .init(price: 60_000, income: 4_800, health: 1_200_000, speed: 65, bounty: 4_800, slowImmune: false, regeneration: 0, name: "Huge Titan", special: ""),
        .init(price: 100_000, income: 7_000, health: 1_500_000, speed: 65, bounty: 7_000, slowImmune: false, regeneration: 500, name: "Zeus", special: "Regenerates"),
        .init(price: 200_000, income: 14_000, health: 2_500_000, speed: 80, bounty: 14_000, slowImmune: true, regeneration: 0, name: "Phoenix", special: "Slow immunity"),
        .init(price: 400_000, income: 28_000, health: 6_000_000, speed: 140, bounty: 28_000, slowImmune: false, regeneration: 0, name: "Express Raptor", special: "Super fast"),
        .init(price: 1_000_000, income: 56_000, health: 15_000_000, speed: 70, bounty: 56_000, slowImmune: false, regeneration: 0, name: "Fat Colossus", special: ""),
    ]
}
