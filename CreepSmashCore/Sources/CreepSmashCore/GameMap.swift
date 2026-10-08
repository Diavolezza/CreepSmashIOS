public struct GridPoint: Hashable, Codable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
    public var description: String { "(\(x),\(y))" }
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

    /// Length of the path in cells (shown in the map selection).
    public var pathLength: Int { pathCells.count }

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
