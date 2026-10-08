/// Game rules that are not tied to a creep or tower type.
/// All times in ticks (1 tick = 50 ms).
public struct Rules: Codable, Equatable, Sendable {
    public var tickMilliseconds = 50
    public var startLives = 20
    public var startCredits = 500
    public var startIncome = 200
    /// Interval between income payments (original: 300 ticks = 15 s).
    public var incomeIntervalTicks = 300
    /// The game runs from this tick on; before that there is a countdown. The first income payment happens at the start.
    public var startTick = 100
    /// Delay between input and execution (lockstep).
    public var inputDelayTicks = 4
    /// Duration of building, upgrade, sale and strategy change.
    public var actionTicks = 40
    public var waveSize = 20
    public var waveSpacingTicks = 3
    public var sellRefundPercent = 75

    public init() {}

    public static let standard = Rules()

    public var ticksPerSecond: Int { 1000 / tickMilliseconds }
}

/// Geometry of the board. Positions are computed in milli-pixels (1 px = 1000).
public enum Board {
    public static let cells = 16
    public static let cellSize = 20
    public static let pixelSize = cells * cellSize
    public static let milli = 1000
    /// Steps per path segment (original: 1000), here in milli-steps.
    public static let segmentSteps = 1000 * milli

    /// Center of a cell in milli-pixels.
    public static func center(of cell: GridPoint) -> (x: Int, y: Int) {
        ((cell.x * cellSize + cellSize / 2) * milli, (cell.y * cellSize + cellSize / 2) * milli)
    }
}
