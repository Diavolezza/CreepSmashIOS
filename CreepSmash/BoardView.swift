import SwiftUI
import QuartzCore
import CreepSmashCore

/// A board (16 × 16 cells). The player's own board is interactive; the opponent's is only a preview.
struct BoardView: View {
    let controller: GameController
    let player: Int
    var interactive = true

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: controller.isPaused)) { timeline in
                Canvas { context, size in
                    var renderer = BoardRenderer(controller: controller, player: player,
                                                 detailed: interactive, date: timeline.date)
                    renderer.draw(&context, size: size)
                }
            }
            .contentShape(Rectangle())
            // While placing, the tower preview with its range follows the finger and is built where
            // the finger is lifted; otherwise this acts like a tap.
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard interactive, case .placing = controller.selection else { return }
                    controller.aimCell = cell(at: value.location, size: geo.size)
                }
                .onEnded { value in
                    guard interactive, let cell = cell(at: value.location, size: geo.size) else { return }
                    controller.tapCell(cell)
                })
            // With a mouse or trackpad (Mac, iPad) the preview follows the pointer.
            .onContinuousHover { phase in
                guard interactive, case .placing = controller.selection else { return }
                switch phase {
                case let .active(location): controller.aimCell = cell(at: location, size: geo.size)
                case .ended: controller.aimCell = nil
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func cell(at location: CGPoint, size: CGSize) -> GridPoint? {
        let cellSize = size.width / CGFloat(Board.cells)
        let cell = GridPoint(x: Int(floor(location.x / cellSize)), y: Int(floor(location.y / cellSize)))
        return controller.game.map.isInside(cell) ? cell : nil
    }
}

/// Draws a board like the original: background image, tower sprites, rotated creeps with
/// health bars, white/blue lasers, rockets as white dots.
@MainActor
struct BoardRenderer {
    let controller: GameController
    let player: Int
    let detailed: Bool
    let date: Date

    private var images: [String: GraphicsContext.ResolvedImage] = [:]

    init(controller: GameController, player: Int, detailed: Bool, date: Date) {
        self.controller = controller
        self.player = player
        self.detailed = detailed
        self.date = date
    }

    mutating func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let game = controller.game
        let map = game.map
        let board = game.players[player]
        let scale = size.width / CGFloat(Board.pixelSize)
        let cellSide = CGFloat(Board.cellSize) * scale
        let now = CACurrentMediaTime()
        func cellRect(_ cell: GridPoint) -> CGRect {
            CGRect(x: CGFloat(cell.x) * cellSide, y: CGFloat(cell.y) * cellSide, width: cellSide, height: cellSide)
        }
        func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale, y: p.y * scale) }

        // Background
        let mapImage = String(map.imageName.split(separator: ".").first ?? "")
        ctx.draw(image(mapImage, ctx), in: CGRect(origin: .zero, size: size))

        // Buildable cells while placing
        if detailed, case .placing = controller.selection {
            var grid = Path()
            for y in 0..<Board.cells {
                for x in 0..<Board.cells {
                    let cell = GridPoint(x: x, y: y)
                    if map.isBuildable(cell) && board.tower(at: cell) == nil {
                        grid.addRect(cellRect(cell).insetBy(dx: 0.5, dy: 0.5))
                    }
                }
            }
            ctx.stroke(grid, with: .color(Theme.green.opacity(0.25)), lineWidth: 0.5)
        }

        // Tower
        // Dark tile under each tower so it stands out against the colorful background.
        func plate(_ r: CGRect, _ c: GraphicsContext) {
            c.fill(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: r.width * 0.2),
                   with: .color(.black.opacity(0.65)))
        }
        for tower in board.towers {
            let r = cellRect(tower.cell)
            plate(r, ctx)
            // The barrel points at the last target (display only, not part of the game state).
            var turret = ctx
            turret.translateBy(x: r.midX, y: r.midY)
            turret.rotate(by: .radians(controller.effects.aim(player: player, tower: tower.id, now: now)))
            turret.draw(image(tower.kind.imageName(level: tower.level), ctx, smooth: true),
                        in: CGRect(x: -r.width / 2, y: -r.height / 2, width: r.width, height: r.height))
            let total = CGFloat(game.rules.actionTicks)
            switch tower.activity {
            case .ready:
                break
            case let .building(remaining):
                let w = r.width * CGFloat(remaining) / total
                ctx.fill(Path(CGRect(x: r.maxX - w, y: r.minY, width: w, height: r.height)), with: .color(.black.opacity(0.75)))
            case let .upgrading(remaining):
                progressBar(&ctx, r, CGFloat(remaining) / total, .blue)
            case let .selling(remaining):
                progressBar(&ctx, r, CGFloat(remaining) / total, .red)
            case let .retargeting(remaining, _, _):
                progressBar(&ctx, r, CGFloat(remaining) / total, .orange)
            }
        }

        if detailed {
            // Build orders not yet executed
            for build in controller.pendingBuilds {
                var ghost = ctx
                ghost.opacity = 0.5
                plate(cellRect(build.cell), ghost)
                ghost.draw(image(build.kind.imageName(level: 1), ctx, smooth: true), in: cellRect(build.cell))
            }
            // Tower to be built under the finger or pointer, with its range: green if it can be built
            // there, red if not.
            if case let .placing(kind) = controller.selection, let cell = controller.aimCell {
                let r = cellRect(cell)
                let stats = kind.stats(level: 1)
                let free = map.isBuildable(cell) && board.tower(at: cell) == nil
                    && !controller.pendingBuilds.contains { $0.cell == cell }
                let color = free && controller.hud.available >= stats.price ? Theme.green : Theme.warning
                let radius = CGFloat(stats.range) * scale
                let circle = Path(ellipseIn: CGRect(x: r.midX - radius, y: r.midY - radius, width: 2 * radius, height: 2 * radius))
                ctx.fill(circle, with: .color(color.opacity(0.12)))
                ctx.stroke(circle, with: .color(color.opacity(0.9)), lineWidth: 1)
                var ghost = ctx
                ghost.opacity = 0.75
                plate(r, ghost)
                ghost.draw(image(kind.imageName(level: 1), ctx, smooth: true), in: r)
                ctx.stroke(Path(r), with: .color(color), lineWidth: 1)
            }
            // Selected tower with its range
            if let tower = controller.selectedTower {
                let r = cellRect(tower.cell)
                let radius = CGFloat(tower.stats.range) * scale
                let circle = Path(ellipseIn: CGRect(x: r.midX - radius, y: r.midY - radius, width: 2 * radius, height: 2 * radius))
                ctx.fill(circle, with: .color(.yellow.opacity(0.1)))
                ctx.stroke(circle, with: .color(.yellow), lineWidth: 1)
                ctx.stroke(Path(r), with: .color(.yellow), lineWidth: 1)
            }
        }

        // Creeps
        let alpha = controller.interpolation
        let creepSide = CGFloat(Board.cellSize) * scale
        for creep in board.creeps where creep.isActive(at: game.tick) {
            let current = EffectStore.point(creep.x, creep.y)
            var position = current
            if let prev = controller.previousPositions[creep.id] {
                let p = CGPoint(x: prev.x / CGFloat(Board.milli), y: prev.y / CGFloat(Board.milli))
                if abs(p.x - current.x) + abs(p.y - current.y) < 10 {
                    position = CGPoint(x: p.x + (current.x - p.x) * alpha, y: p.y + (current.y - p.y) * alpha)
                }
            }
            let center = pt(position)
            // Dark disc under each creep so it also stands out against grass, lava and light paths.
            let disc = creepSide * 0.42
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - disc, y: center.y - disc, width: 2 * disc, height: 2 * disc)),
                     with: .color(.black.opacity(0.6)))
            var c = ctx
            c.translateBy(x: center.x, y: center.y)
            c.rotate(by: .radians(angle(map: map, segment: creep.segment, step: creep.step)))
            c.draw(image(creep.type.imageName, ctx, smooth: true),
                   in: CGRect(x: -creepSide / 2, y: -creepSide / 2, width: creepSide, height: creepSide))

            // Health bar above the creep (as in the original: 2 px, color by remaining health)
            let fraction = CGFloat(creep.health) / CGFloat(creep.stats.health)
            let barY = center.y - creepSide / 2 + 2 * scale
            let x0 = center.x - creepSide / 2 + 3 * scale
            var bar = Path()
            bar.move(to: CGPoint(x: x0, y: barY))
            bar.addLine(to: CGPoint(x: x0 + 14 * scale * fraction, y: barY))
            ctx.stroke(bar, with: .color(healthColor(fraction)), lineWidth: max(1, 2 * scale * 0.8))
        }

        // Rockets
        for tower in board.towers {
            for shot in tower.projectiles {
                let p = pt(EffectStore.point(shot.x, shot.y))
                ctx.fill(Path(CGRect(x: p.x - 1.5 * scale, y: p.y - 1.5 * scale, width: 3 * scale, height: 3 * scale)), with: .color(.white))
            }
        }

        // Effects
        let effects = controller.effects
        for beam in effects.beams where beam.player == player {
            var line = Path()
            line.move(to: pt(beam.from))
            line.addLine(to: pt(beam.to))
            ctx.stroke(line, with: .color(.white), lineWidth: max(1, 3 * scale * 0.7))
            ctx.stroke(line, with: .color(.blue), lineWidth: max(0.5, 1 * scale * 0.7))
            if !beam.splash.isEmpty {
                var splash = Path()
                for target in beam.splash {
                    splash.move(to: pt(beam.to))
                    splash.addLine(to: pt(target))
                }
                ctx.stroke(splash, with: .color(.white), lineWidth: 1)
            }
        }
        for blast in effects.blasts where blast.player == player {
            let progress = CGFloat((now - blast.start) / (blast.expires - blast.start))
            let c = pt(blast.center)
            let radius = blast.radius * scale
            var path = Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius))
            for hit in blast.hits {
                path.move(to: c)
                path.addLine(to: pt(hit))
            }
            ctx.stroke(path, with: .color(.white.opacity(Double(1 - progress))), lineWidth: 1)
        }
        if detailed {
            for floater in effects.floaters where floater.player == player {
                let progress = (now - floater.start) / (floater.expires - floater.start)
                let p = pt(floater.position)
                let text = Text(floater.text).font(Theme.mono(max(9, 8 * scale), .bold, scaled: false)).foregroundColor(Theme.gold)
                var c = ctx
                c.opacity = 1 - progress
                c.draw(text, at: CGPoint(x: p.x, y: p.y - CGFloat(progress) * 14 * scale))
            }
        }
        for flash in effects.flashes where flash.player == player {
            let progress = (now - flash.start) / (flash.expires - flash.start)
            ctx.stroke(Path(CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)),
                       with: .color(.red.opacity(1 - progress)), lineWidth: detailed ? 6 : 3)
        }

        if board.isDead {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.55)))
        }
        _ = date
    }

    /// Image from the asset catalog, resolved once per draw pass. `smooth` for the tower and creep
    /// drawings, which are stored large and scaled down; the map backgrounds are drawn as they are.
    private mutating func image(_ name: String, _ ctx: GraphicsContext, smooth: Bool = false) -> GraphicsContext.ResolvedImage {
        if let cached = images[name] { return cached }
        let resolved = ctx.resolve(Image(name).interpolation(smooth ? .high : .none))
        images[name] = resolved
        return resolved
    }

    private func progressBar(_ ctx: inout GraphicsContext, _ r: CGRect, _ fraction: CGFloat, _ color: Color) {
        let h = max(2, r.height * 0.15)
        ctx.fill(Path(CGRect(x: r.minX + 1, y: r.minY + 1, width: (r.width - 2) * fraction, height: h)), with: .color(color))
    }

    private func healthColor(_ fraction: CGFloat) -> Color {
        switch fraction {
        case ...0.10: .red
        case ...0.25: .orange
        case ...0.50: .yellow
        default: .green
        }
    }

    /// Heading of a creep; near corners it blends smoothly between two segments.
    private func angle(map: GameMap, segment: Int, step: Int) -> Double {
        func direction(_ s: Int) -> Double? {
            guard s >= 0 else { return nil }
            let a = map.pathPoint(s), b = map.pathPoint(s + 1)
            guard a != b else { return nil }
            return atan2(Double(b.y - a.y), Double(b.x - a.x))
        }
        func blend(_ a: Double, _ b: Double, _ f: Double) -> Double {
            var d = b - a
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            return a + d * f
        }
        let current = direction(segment) ?? 0
        let t = Double(step) / Double(Board.segmentSteps)
        if t > 0.5, let next = direction(segment + 1) { return blend(current, next, t - 0.5) }
        if t < 0.5, let previous = direction(segment - 1) { return blend(previous, current, 0.5 + t) }
        return current
    }
}
