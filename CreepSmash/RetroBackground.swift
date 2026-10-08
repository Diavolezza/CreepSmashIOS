import SwiftUI

/// Animated background of the start screen in 80s arcade style: twinkling stars above a glowing horizon
/// and a green perspective grid that scrolls towards the viewer.
struct RetroBackground: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                draw(&ctx, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let w = size.width, h = size.height
        let horizon = h * 0.6
        let green = Theme.green

        // Sky
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon)),
                 with: .linearGradient(Gradient(colors: [.black, Color(red: 0.0, green: 0.12, blue: 0.05)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))

        // Stars: fixed positions (simple pseudo random sequence), twinkling at different speeds
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        for _ in 0..<110 {
            let x = next() * w, y = next() * horizon * 0.92
            let speed = 0.5 + next() * 2, phase = next() * 6.28
            let r = next() < 0.85 ? 1.0 : 1.6
            let a = 0.25 + 0.75 * abs(sin(time * speed + phase))
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                     with: .color(.white.opacity(a * 0.8)))
        }

        // Floor
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.0, green: 0.10, blue: 0.04), .black]),
                                       startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))

        // Grid: lines towards the vanishing point in the middle of the horizon …
        let cx = w / 2
        var lines = Path()
        for i in -24...24 {
            lines.move(to: CGPoint(x: cx + CGFloat(i) * w * 0.012, y: horizon))
            lines.addLine(to: CGPoint(x: cx + CGFloat(i) * w * 0.11, y: h))
        }
        ctx.stroke(lines, with: .color(green.opacity(0.35)), lineWidth: 1)
        // … and cross lines that come closer (perspective: distance ~ 1 / depth)
        let phase = (time * 0.5).truncatingRemainder(dividingBy: 1)
        for n in 0..<22 {
            let z = Double(n) + 1 - phase
            let y = horizon + (h - horizon) * 0.9 / z
            guard y <= h else { continue }
            let fade = min(1, (y - horizon) / (h - horizon) * 2.2)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: w, y: y))
            ctx.stroke(line, with: .color(green.opacity(0.55 * fade)), lineWidth: 1)
        }

        // Glow on the horizon
        ctx.fill(Path(CGRect(x: 0, y: horizon - 40, width: w, height: 80)),
                 with: .linearGradient(Gradient(stops: [.init(color: green.opacity(0), location: 0),
                                                        .init(color: green.opacity(0.28), location: 0.5),
                                                        .init(color: green.opacity(0), location: 1)]),
                                       startPoint: CGPoint(x: 0, y: horizon - 40), endPoint: CGPoint(x: 0, y: horizon + 40)))
        var horizonLine = Path()
        horizonLine.move(to: CGPoint(x: 0, y: horizon))
        horizonLine.addLine(to: CGPoint(x: w, y: horizon))
        ctx.stroke(horizonLine, with: .color(green.opacity(0.8)), lineWidth: 1.5)
    }
}
