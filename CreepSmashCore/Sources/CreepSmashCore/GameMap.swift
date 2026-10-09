public struct GridPoint: Hashable, Codable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
    public var description: String { "(\(x),\(y))" }
}

/// Special sections of a path, as in several maps of the original.
public enum MapFeature: String, CaseIterable, Sendable {
    /// Path points several cells apart on a straight line: creeps are that many times faster there.
    case fastLanes
    /// Path points far apart off a straight line: creeps fly across the board in the time of one cell.
    case jumps
    /// The path crosses itself or runs laps: towers there hit the creeps more than once.
    case loops
    /// The path runs into a dead end and back.
    case uTurns
    /// Diagonal steps.
    case diagonals
}

public enum MapError: Error, Equatable {
    case invalidLine(Int, String)
    case pathTooShort
}

/// A map in the original's format.
///
/// File layout: lines starting with `#` are comments; a line ending in `.jpg`/`.png`/`.bmp` names the background image;
/// `x,y` is a path point (in walking direction); `x;y` is a blocked cell; everything else is ignored.
public struct GameMap: Sendable {
    /// Identifier (the original's file name without "map_", e.g. "blue").
    public let id: String
    public let name: String
    public let imageName: String
    public let path: [GridPoint]
    public let blocked: Set<GridPoint>
    public let pathCells: Set<GridPoint>

    public init(id: String, name: String, imageName: String, path: [GridPoint], blocked: Set<GridPoint>) throws {
        guard path.count >= 2 else { throw MapError.pathTooShort }
        self.id = id
        self.name = name
        self.imageName = imageName
        self.path = path
        self.blocked = blocked
        // Some maps skip cells on straight sections (creeps are faster there).
        // The skipped cells still belong to the path and cannot be built on.
        var cells = Set(path)
        for (a, b) in zip(path, path.dropFirst()) where a.x == b.x || a.y == b.y {
            let dx = (b.x - a.x).signum(), dy = (b.y - a.y).signum()
            var c = a
            while c != b {
                c = GridPoint(x: c.x + dx, y: c.y + dy)
                cells.insert(c)
            }
        }
        self.pathCells = cells
    }

    /// Length of the path in cells.
    public var pathLength: Int { pathCells.count }

    /// How long a creep walks, in cells at normal speed (one path segment each): the measure for short/medium/long.
    public var walkLength: Int { path.count - 1 }

    /// The special sections of the path, in the order they are named in the map selection.
    public var features: [MapFeature] {
        var found: Set<MapFeature> = []
        for (i, (a, b)) in zip(path, path.dropFirst()).enumerated() {
            let dx = abs(b.x - a.x), dy = abs(b.y - a.y)
            if dx == 0 || dy == 0 {
                if dx + dy > 1 { found.insert(.fastLanes) }
            } else if dx == 1 && dy == 1 {
                found.insert(.diagonals)
            } else {
                found.insert(.jumps)
            }
            if i > 0 {   // turning back: this step goes exactly the opposite way of the last one
                let p = path[i - 1]
                if (b.x - a.x).signum() == -(a.x - p.x).signum(), (b.y - a.y).signum() == -(a.y - p.y).signum() {
                    found.insert(.uTurns)
                }
            }
        }
        if !found.contains(.uTurns), Set(path).count < path.count { found.insert(.loops) }
        return MapFeature.allCases.filter(found.contains)
    }

    public static func parse(id: String = "", name: String, text: String) throws -> GameMap {
        var image = ""
        var path: [GridPoint] = []
        var blocked: Set<GridPoint> = []
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmed(" \t\r")
            if line.isEmpty || line.hasPrefix("#") { continue }
            let lower = line.lowercased()
            if lower.hasSuffix(".jpg") || lower.hasSuffix(".png") || lower.hasSuffix(".bmp") {
                image = line
            } else if line.contains(",") {
                path.append(try point(line, separator: ",", lineNumber: index + 1))
            } else if line.contains(";") {
                blocked.insert(try point(line, separator: ";", lineNumber: index + 1))
            }
        }
        return try GameMap(id: id.isEmpty ? name : id, name: name, imageName: image, path: path, blocked: blocked)
    }

    private static func point(_ line: String, separator: Character, lineNumber: Int) throws -> GridPoint {
        let parts = line.split(separator: separator).map { $0.trimmed(" \t") }
        guard parts.count == 2, let x = Int(parts[0]), let y = Int(parts[1]) else {
            throw MapError.invalidLine(lineNumber, line)
        }
        return GridPoint(x: x, y: y)
    }

    public func isInside(_ cell: GridPoint) -> Bool {
        (0..<Board.cells).contains(cell.x) && (0..<Board.cells).contains(cell.y)
    }

    /// The cell lies on the board and is neither path nor blocked (whether a tower stands there is checked by the game).
    public func isBuildable(_ cell: GridPoint) -> Bool {
        isInside(cell) && !pathCells.contains(cell) && !blocked.contains(cell)
    }

    /// Path point at an index; beyond the end, the last point (as in the original).
    public func pathPoint(_ index: Int) -> GridPoint {
        path[min(index, path.count - 1)]
    }

    /// Position of a creep (cell center, milli-pixels) on segment `segment` after `step` milli-steps.
    public func position(segment: Int, step: Int) -> (x: Int, y: Int) {
        let a = pathPoint(segment)
        let b = pathPoint(segment + 1)
        let start = Board.center(of: a)
        // (b - a) * cellSize * 1000 milli-pixels spread over segmentSteps milli-steps.
        let x = start.x + (b.x - a.x) * Board.cellSize * step / Board.milli
        let y = start.y + (b.y - a.y) * Board.cellSize * step / Board.milli
        return (x, y)
    }
}

extension StringProtocol {
    func trimmed(_ set: String) -> String {
        var s = Substring(self)
        while let f = s.first, set.contains(f) { s = s.dropFirst() }
        while let l = s.last, set.contains(l) { s = s.dropLast() }
        return String(s)
    }
}
