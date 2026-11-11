/// Game rules that are not tied to a creep or tower type.
/// All times in ticks (1 tick = 50 ms).
public struct Rules: Codable, Equatable, Sendable {
    public var tickMilliseconds = 50
    public var startLives = 20
    public var startCredits = 500
    public var startIncome = 200
    /// Interval between income payments: 200 ticks = 10 s (original and up to app version 1.0.10: 300 ticks =
    /// 15 s; games between equal opponents took about 19 minutes, now about 13). Saved games and online rounds
    /// carry their rules, so older ones go on with 15 s.
    public var incomeIntervalTicks = 200
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

    /// Rules from another device or a saved file are only used if every value lies in a sensible range
    /// (no division by zero, no endless waves).
    public var isPlausible: Bool {
        (1...1000).contains(tickMilliseconds) && (1...10_000).contains(startLives)
            && (0...10_000_000).contains(startCredits) && (0...10_000_000).contains(startIncome)
            && (1...100_000).contains(incomeIntervalTicks) && (0...100_000).contains(startTick)
            && (1...200).contains(inputDelayTicks) && (0...100_000).contains(actionTicks)
            && (1...100).contains(waveSize) && (0...1000).contains(waveSpacingTicks) && (0...100).contains(sellRefundPercent)
    }
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
