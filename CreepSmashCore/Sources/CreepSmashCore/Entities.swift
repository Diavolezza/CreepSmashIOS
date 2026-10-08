public struct Creep: Equatable, Sendable {
    public let id: Int
    public let type: CreepType
    /// Player who sent the creep.
    public let sender: Int
    public internal(set) var health: Int
    /// Current speed in milli-steps per tick.
    public internal(set) var speed: Int
    public internal(set) var slowTicks: Int = 0
    public internal(set) var segment: Int = 0
    /// Progress in the current segment in milli-steps (0 ..< Board.segmentSteps).
    public internal(set) var step: Int = 0
    /// Total milli-steps travelled (for the "Farthest" strategy).
    public internal(set) var totalSteps: Int = 0
    /// From this tick on, the creep walks and can be shot at.
    public let activeFromTick: Int
    /// Position (cell center) in milli-pixels.
    public internal(set) var x: Int
    public internal(set) var y: Int

    public var stats: CreepStats { type.stats }
    public var baseSpeed: Int { type.stats.speed * Board.milli }
    public func isActive(at tick: Int) -> Bool { tick >= activeFromTick }
}

public enum TowerActivity: Equatable, Sendable {
    case building(remaining: Int)
    case ready
    case upgrading(remaining: Int)
    case selling(remaining: Int)
    case retargeting(remaining: Int, strategy: TargetStrategy, locked: Bool)

    public var isReady: Bool { self == .ready }
}

public struct Projectile: Equatable, Sendable {
    public let id: Int
    public internal(set) var targetId: Int
    public internal(set) var x: Int
    public internal(set) var y: Int
    /// Step length in milli-pixels per tick.
    public internal(set) var stepLength: Int
    public internal(set) var hasArrived: Bool = false
}

public struct Tower: Equatable, Sendable {
    public let id: Int
    public let kind: TowerKind
    public internal(set) var level: Int = 1
    public let cell: GridPoint
    public internal(set) var activity: TowerActivity
    public internal(set) var cooldown: Int = 0
    public internal(set) var strategy: TargetStrategy
    public internal(set) var locked: Bool = false
    public internal(set) var lastTargetId: Int?
    /// Sum of all level prices paid.
    public internal(set) var totalPrice: Int
    public internal(set) var projectiles: [Projectile] = []

    public var stats: TowerStats { kind.stats(level: level) }
    public var isUpgradable: Bool { level < kind.maxLevel }
    public var nextLevelPrice: Int? { isUpgradable ? kind.stats(level: level + 1).price : nil }
    public func sellValue(rules: Rules) -> Int { totalPrice * rules.sellRefundPercent / 100 }
}

public struct PlayerBoard: Equatable, Sendable {
    public let index: Int
    public let name: String
    public internal(set) var credits: Int
    public internal(set) var income: Int
    public internal(set) var lives: Int
    public internal(set) var creeps: [Creep] = []
    public internal(set) var towers: [Tower] = []
    /// Place in the final ranking (1 = winner), set as soon as it is decided.
    public internal(set) var rank: Int?
    /// Lives that this player's creeps have taken from others.
    public internal(set) var livesTaken: Int = 0
    /// Where this player's creeps go.
    public internal(set) var sendMode: SendMode = .next
    /// Statistics: damage this player's towers have done, and health of all creeps this player has sent.
    public internal(set) var damageDealt: Int = 0
    public internal(set) var healthSent: Int = 0

    public var isDead: Bool { lives <= 0 }

    public func tower(at cell: GridPoint) -> Tower? { towers.first { $0.cell == cell } }
    public func tower(id: Int) -> Tower? { towers.first { $0.id == id } }
}
