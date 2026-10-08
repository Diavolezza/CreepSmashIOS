/// A player action. It is assigned an execution tick and executed identically on all devices.
public enum Command: Codable, Equatable, Sendable {
    case buildTower(kind: TowerKind, cell: GridPoint)
    case upgradeTower(id: Int)
    case sellTower(id: Int)
    case setStrategy(towerId: Int, strategy: TargetStrategy, locked: Bool)
    /// Sends `count` creeps (1 = single creep, more = wave).
    case sendCreeps(type: CreepType, count: Int)
    /// Surrender or leave the game: the player is eliminated immediately.
    case surrender
    /// Where this player's creeps go from now on (only matters with more than two players).
    case setSendMode(SendMode)
}

/// Who receives the creeps a player sends (modes of the original with more than two players).
public enum SendMode: String, Codable, CaseIterable, Sendable {
    /// The next living player in the ring.
    case next
    /// One creep to every other living player; costs and income count per recipient.
    case all
    /// A living opponent drawn at random (the same on every device).
    case random
}

public struct ScheduledCommand: Codable, Equatable, Sendable {
    public let tick: Int
    public let player: Int
    /// Running number per player; determines the order within a tick.
    public let sequence: Int
    public let command: Command

    public init(tick: Int, player: Int, sequence: Int, command: Command) {
        self.tick = tick
        self.player = player
        self.sequence = sequence
        self.command = command
    }
}

public enum RejectReason: String, Codable, Sendable {
    case notStarted, playerDead, notEnoughCredits, cellNotBuildable, cellOccupied
    case unknownTower, towerBusy, maxLevel, noTarget, gameFinished
}

/// What happened in a tick – for rendering and sound, not part of the game state.
public enum GameEvent: Equatable, Sendable {
    case laserShot(player: Int, towerId: Int, targetId: Int, splashTargetIds: [Int])
    case rocketLaunched(player: Int, towerId: Int)
    case explosion(player: Int, x: Int, y: Int, radius: Int, hitIds: [Int])
    case creepKilled(player: Int, creepId: Int, type: CreepType, x: Int, y: Int, bounty: Int)
    case creepEscaped(player: Int, creepId: Int, type: CreepType, sender: Int)
    case creepsSent(from: Int, to: Int, type: CreepType, count: Int)
    case towerBuilt(player: Int, towerId: Int)
    case towerUpgraded(player: Int, towerId: Int, level: Int)
    case towerSold(player: Int, towerId: Int, refund: Int)
    case incomePaid(player: Int, amount: Int)
    case playerDied(player: Int, rank: Int)
    case gameFinished(winner: Int?)
    case commandRejected(player: Int, command: Command, reason: RejectReason)
}
