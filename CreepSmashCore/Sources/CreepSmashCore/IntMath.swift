/// Integer square root (rounded down). The Double square root is correctly rounded per IEEE 754 and therefore
/// identical on all devices; the correction loops additionally make the result exact.
@inlinable
public func isqrt(_ n: Int) -> Int {
    precondition(n >= 0, "isqrt of negative number")
    if n < 2 { return n }
    var x = Int(Double(n).squareRoot())
    while x * x > n { x -= 1 }
    while (x + 1) * (x + 1) <= n { x += 1 }
    return x
}

@inlinable
func distanceSquared(_ ax: Int, _ ay: Int, _ bx: Int, _ by: Int) -> Int {
    let dx = bx - ax, dy = by - ay
    return dx * dx + dy * dy
}

/// FNV-1a 64-bit – small, deterministic checksum.
public struct Checksum {
    public private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

    public init() {}

    public mutating func add(_ v: Int) {
        var bits = UInt64(bitPattern: Int64(v))
        for _ in 0..<8 {
            value ^= bits & 0xff
            value = value &* 0x100_0000_01b3
            bits >>= 8
        }
    }

    public mutating func add(_ b: Bool) { add(b ? 1 : 0) }
}
