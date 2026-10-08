import CoreGraphics
import QuartzCore
import CreepSmashCore

/// Short-lived visual effects (laser beams, explosions, bounty labels).
/// Not part of the game state; coordinates in board pixels (0...320).
final class EffectStore {
    struct Beam {
        let player: Int
        let from: CGPoint
        let to: CGPoint
        let splash: [CGPoint]
        let expires: CFTimeInterval
    }

    struct Blast {
        let player: Int
        let center: CGPoint
        let radius: CGFloat
        let hits: [CGPoint]
        let start: CFTimeInterval
        let expires: CFTimeInterval
    }

    struct Floater {
        let player: Int
        let position: CGPoint
        let text: String
        let start: CFTimeInterval
        let expires: CFTimeInterval
    }

    struct Flash {
        let player: Int
        let start: CFTimeInterval
        let expires: CFTimeInterval
    }

    private(set) var beams: [Beam] = []
    private(set) var blasts: [Blast] = []
    private(set) var floaters: [Floater] = []
    private(set) var flashes: [Flash] = []

    /// Direction of a tower's barrel in radians (0 = up, clockwise); it turns to each new target
    /// within `turnTime`, along the shorter way round.
    struct Aim {
        let from: Double
        let to: Double
        let start: CFTimeInterval

        func angle(at now: CFTimeInterval) -> Double {
            let t = min(1, max(0, (now - start) / EffectStore.turnTime))
            var delta = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
            if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
            return from + delta * t
        }
    }

    struct TowerKey: Hashable {
        let player: Int
        let tower: Int
    }

    static let turnTime: CFTimeInterval = 0.12
    private var aims: [TowerKey: Aim] = [:]

    /// Current barrel direction of a tower; towers that have not fired yet point up.
    func aim(player: Int, tower: Int, now: CFTimeInterval) -> Double {
        aims[TowerKey(player: player, tower: tower)]?.angle(at: now) ?? 0
    }

    private func turn(player: Int, tower: Int, from center: CGPoint, to target: CGPoint, now: CFTimeInterval) {
        let key = TowerKey(player: player, tower: tower)
        let angle = atan2(Double(target.x - center.x), Double(center.y - target.y))
        aims[key] = Aim(from: aims[key]?.angle(at: now) ?? 0, to: angle, start: now)
    }

    func add(events: [GameEvent], game: Game, now: CFTimeInterval) {
        // Positions of killed creeps, so beams are also drawn to the final hit.
        var killed: [Int: CGPoint] = [:]
        for case let .creepKilled(_, id, _, x, y, _) in events {
            killed[id] = Self.point(x, y)
        }
        func position(of creepId: Int, on player: Int) -> CGPoint? {
            if let c = game.players[player].creeps.first(where: { $0.id == creepId }) {
                return Self.point(c.x, c.y)
            }
            return killed[creepId]
        }

        for event in events {
            switch event {
            case let .laserShot(player, towerId, targetId, splashIds):
                guard let tower = game.players[player].tower(id: towerId),
                      let to = position(of: targetId, on: player) else { continue }
                let c = Board.center(of: tower.cell)
                turn(player: player, tower: towerId, from: Self.point(c.x, c.y), to: to, now: now)
                beams.append(Beam(player: player, from: Self.point(c.x, c.y), to: to,
                                  splash: splashIds.compactMap { position(of: $0, on: player) },
                                  expires: now + 0.1))
            case let .rocketLaunched(player, towerId):
                guard let tower = game.players[player].tower(id: towerId),
                      let targetId = tower.projectiles.last?.targetId,
                      let to = position(of: targetId, on: player) else { continue }
                let c = Board.center(of: tower.cell)
                turn(player: player, tower: towerId, from: Self.point(c.x, c.y), to: to, now: now)
            case let .explosion(player, x, y, radius, hitIds):
                blasts.append(Blast(player: player, center: Self.point(x, y), radius: CGFloat(radius),
                                    hits: hitIds.compactMap { position(of: $0, on: player) },
                                    start: now, expires: now + 0.2))
            case let .creepKilled(player, _, _, x, y, bounty):
                floaters.append(Floater(player: player, position: Self.point(x, y), text: "+\(Format.short(bounty))",
                                        start: now, expires: now + 0.8))
            case let .creepEscaped(player, _, _, _):
                flashes.append(Flash(player: player, start: now, expires: now + 0.4))
            default:
                break
            }
        }
    }

    func prune(now: CFTimeInterval) {
        beams.removeAll { $0.expires < now }
        blasts.removeAll { $0.expires < now }
        floaters.removeAll { $0.expires < now }
        flashes.removeAll { $0.expires < now }
    }

    static func point(_ x: Int, _ y: Int) -> CGPoint {
        CGPoint(x: CGFloat(x) / CGFloat(Board.milli), y: CGFloat(y) / CGFloat(Board.milli))
    }
}
