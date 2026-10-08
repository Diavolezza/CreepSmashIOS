import SwiftUI
import CreepSmashCore

/// The six towers to build: a column left of the board (iPhone) or a row below it (iPad, `horizontal`).
struct TowerColumn: View {
    let controller: GameController
    let height: CGFloat
    var horizontal = false

    var body: some View {
        let available = controller.hud.available
        let rowHeight = horizontal ? height : (height - 5 * 4) / 6
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: Theme.s(6))) : AnyLayout(VStackLayout(spacing: Theme.s(4)))
        layout {
            ForEach(TowerKind.allCases, id: \.self) { kind in
                let price = kind.stats(level: 1).price
                let affordable = available >= price
                let selected = controller.selection == .placing(kind)
                Button {
                    controller.togglePlacing(kind)
                } label: {
                    ControlTile(image: "towerButton\(kind.rawValue)", price: price, priceColor: Theme.text,
                                affordable: affordable, selected: selected, name: kind.name)
                }
                .buttonStyle(.plain)
                .hoverTip(kind.tooltip)
                .frame(maxWidth: horizontal ? .infinity : nil)
                .frame(height: rowHeight)
                .accessibilityLabel(L("\(kind.name), \(price) credits"))
            }
        }
    }
}

/// The 16 creeps to send: two columns right of the boards (iPhone) or two rows of eight below the
/// opponent's board (iPad, `horizontal`). Tap = one, long press = wave.
struct CreepColumn: View {
    let controller: GameController
    let height: CGFloat
    var horizontal = false

    var body: some View {
        let available = controller.hud.available
        let gap = horizontal ? Theme.s(6) : 3
        let rowHeight = horizontal ? (height - gap) / 2 : (height - 7 * gap) / 8
        let columns = Array(repeating: GridItem(.flexible(), spacing: gap), count: horizontal ? 8 : 2)
        LazyVGrid(columns: columns, spacing: gap) {
            ForEach(CreepType.allCases, id: \.self) { type in
                CreepTile(controller: controller, type: type, available: available)
                    .frame(height: rowHeight)
            }
        }
    }
}

/// The 16 creeps in a grid with the given number of columns, filling the available space
/// (4 × 4 next to the small boards on the iPad, 8 × 2 in portrait).
struct CreepGrid: View {
    let controller: GameController
    let columns: Int

    var body: some View {
        GeometryReader { geo in
            let gap = Theme.s(6)
            let rows = (CreepType.allCases.count + columns - 1) / columns
            let rowHeight = (geo.size.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: columns), spacing: gap) {
                ForEach(CreepType.allCases, id: \.self) { type in
                    CreepTile(controller: controller, type: type, available: controller.hud.available)
                        .frame(height: rowHeight)
                }
            }
        }
    }
}

/// One creep: tap = one, long press = wave. With the send mode "all" the price counts per recipient.
struct CreepTile: View {
    let controller: GameController
    let type: CreepType
    let available: Int
    @State private var holding: Task<Void, Never>?
    @State private var streaming = false

    var body: some View {
        let s = type.stats
        let price = s.price * controller.recipients
        ControlTile(image: "creepIcon\(type.rawValue)", price: price, priceColor: Theme.gold,
                    affordable: available >= price)
            .contentShape(Rectangle())
            // Tap: one creep. Hold: after a short moment one creep after the other – the credits count
            // down with each one – until the button is released or the credits run out.
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard holding == nil else { return }
                    holding = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        streaming = true
                        while !Task.isCancelled, controller.canAfford(type) {
                            controller.send(type)
                            try? await Task.sleep(for: .milliseconds(120))
                        }
                    }
                }
                .onEnded { _ in
                    holding?.cancel()
                    holding = nil
                    if !streaming { controller.send(type) }
                    streaming = false
                })
            .hoverTip(type.tooltip)
            .accessibilityLabel(L("\(s.name), \(price) credits, income plus \(s.income * controller.recipients)"))
    }
}

/// One button of the tower or creep controls: symbol and price on a dark tile. What the player cannot
/// afford yet is shown entirely in gray (symbol, price and frame).
struct ControlTile: View {
    let image: String
    let price: Int
    let priceColor: Color
    let affordable: Bool
    var selected = false
    /// Shown between symbol and price where the tile is high enough (tower buttons).
    var name: String?

    var body: some View {
        // With the name if there is room – first with the large symbol, then with a smaller one.
        ViewThatFits(in: .vertical) {
            if let name {
                content(symbol: Theme.s(40), name: name)
                content(symbol: Theme.s(22), name: name)
            }
            content(symbol: Theme.s(40), name: nil)
        }
        .padding(Theme.s(3))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.s(5)).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: Theme.s(5))
            .stroke(selected ? Theme.green : (affordable ? Theme.dimGreen.opacity(0.7) : Color.gray.opacity(0.25)),
                    lineWidth: selected ? Theme.s(2) : 1))
    }

    private func content(symbol: CGFloat, name: String?) -> some View {
        VStack(spacing: Theme.s(2)) {
            Image(affordable ? image : image + "disable")
                .interpolation(.high)
                .resizable()
                // Tower symbols are square, creep symbols wider than tall.
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: symbol, maxHeight: symbol)
            if let name {
                Text(name)
                    .font(Theme.mono(10))
                    .foregroundStyle(affordable ? Theme.text : Color.gray.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(Format.short(price))
                .font(Theme.mono(10, .semibold))
                .foregroundStyle(affordable ? priceColor : Color.gray.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Tooltips

/// Tooltip of a button under the pointer (Mac, iPad with mouse or trackpad). It appears after a
/// short pause and is drawn by the game screen above everything else (see `HoverTipBubble`).
struct HoverTip {
    let text: String
    let anchor: Anchor<CGRect>
}

struct HoverTipKey: PreferenceKey {
    static let defaultValue: HoverTip? = nil
    static func reduce(value: inout HoverTip?, nextValue: () -> HoverTip?) { value = value ?? nextValue() }
}

private struct HoverTipModifier: ViewModifier {
    let text: String
    @State private var hovering = false
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hovering = inside
                guard inside else { shown = false; return }
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    if hovering { shown = true }
                }
            }
            .anchorPreference(key: HoverTipKey.self, value: .bounds) { shown ? HoverTip(text: text, anchor: $0) : nil }
            .onAppear {
                // Launch argument "-tip <start of the text>" shows that tooltip (screenshots).
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-tip"), i + 1 < args.count, text.hasPrefix(args[i + 1]) { shown = true }
            }
    }
}

extension View {
    func hoverTip(_ text: String) -> some View { modifier(HoverTipModifier(text: text)) }
}

/// The tooltip box below its button (above it near the bottom edge), aligned to the side of the button
/// that faces the screen edge – so it covers the buttons after this one, not the cheaper ones before it.
struct HoverTipBubble: View {
    let tip: HoverTip

    var body: some View {
        GeometryReader { geo in
            let r = geo[tip.anchor]
            let gap = Theme.s(6)
            let width = Theme.s(200)
            let x = min(max(0, r.midX < geo.size.width / 2 ? r.minX : r.maxX - width), geo.size.width - width)
            ZStack(alignment: .topLeading) {
                if r.maxY > geo.size.height * 0.82 {
                    // Near the bottom edge: above the button.
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        bubble
                    }
                    .frame(width: width, height: max(0, r.minY - gap))
                    .offset(x: x)
                } else {
                    bubble.offset(x: x, y: r.maxY + gap)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }

    private var bubble: some View {
        Text(tip.text)
            .font(Theme.mono(10))
            .foregroundStyle(Theme.text)
            .frame(width: Theme.s(190), alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Theme.s(5))
            .frame(width: Theme.s(200))
            .background(RoundedRectangle(cornerRadius: Theme.s(6)).fill(Color.black.opacity(0.94)))
            .overlay(RoundedRectangle(cornerRadius: Theme.s(6)).stroke(Theme.dimGreen, lineWidth: Theme.s(1)))
    }
}

/// Editing the selected tower – overlays the player's own board, at the top or bottom
/// depending on where the tower is.
struct TowerDetail: View {
    let controller: GameController
    let tower: Tower

    var body: some View {
        let s = tower.stats
        let rules = controller.game.rules
        let busy = !tower.activity.isReady || controller.hasPendingAction(towerId: tower.id)
        VStack(alignment: .leading, spacing: Theme.s(5)) {
            HStack(spacing: Theme.s(8)) {
                Image(tower.kind.imageName(level: tower.level))
                    .interpolation(.high)
                    .resizable()
                    .frame(width: Theme.s(26), height: Theme.s(26))
                VStack(alignment: .leading, spacing: Theme.s(1)) {
                    Text(L("\(tower.kind.name) · level \(tower.level)/\(tower.kind.maxLevel) · \(status)"))
                        .font(Theme.mono(11, .bold)).foregroundStyle(Theme.green)
                    // Current values, with an arrow to what the next level brings.
                    if tower.level < tower.kind.maxLevel {
                        let n = tower.kind.stats(level: tower.level + 1)
                        Text(L("Damage \(Format.short(s.damage)) → \(Format.short(n.damage)) · range \(s.range) → \(n.range) · every \(InfoFormat.seconds(ticks: s.reloadTicks, rules: rules)) → \(InfoFormat.seconds(ticks: n.reloadTicks, rules: rules))"))
                            .font(Theme.mono(10)).foregroundStyle(Theme.text)
                    } else {
                        Text(L("Damage \(Format.short(s.damage)) · range \(s.range) · every \(InfoFormat.seconds(ticks: s.reloadTicks, rules: rules))"))
                            .font(Theme.mono(10)).foregroundStyle(Theme.text)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    controller.selection = .none
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: Theme.s(20))).foregroundStyle(.gray)
                }
            }
            // Target strategy: one option out of five, like radio buttons; the lock holds the target
            // until it leaves the range.
            let chosen = controller.chosenStrategy(of: tower)
            HStack(spacing: Theme.s(3)) {
                ForEach(TargetStrategy.allCases, id: \.self) { strategy in
                    Button(strategy.shortLabel) { controller.setStrategy(strategy, locked: chosen.locked) }
                        .buttonStyle(ChipStyle(on: chosen.strategy == strategy))
                        .accessibilityLabel(L("Target: \(strategy.label)"))
                }
                Button {
                    controller.setStrategy(chosen.strategy, locked: !chosen.locked)
                } label: {
                    Image(systemName: chosen.locked ? "lock.fill" : "lock.open")
                }
                .buttonStyle(ChipStyle(on: chosen.locked, width: Theme.s(26)))
                .accessibilityLabel(chosen.locked ? L("Stop holding target") : L("Hold target"))
            }
            .disabled(busy)
            HStack(spacing: Theme.s(6)) {
                if let price = tower.nextLevelPrice {
                    Button {
                        controller.upgradeSelected()
                    } label: {
                        Text("Upgrade ¢" + Format.short(price)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PanelButtonStyle(color: controller.hud.available >= price ? Theme.green : .gray))
                    .disabled(busy)
                } else {
                    Text("Max.").font(Theme.mono(11)).foregroundStyle(.gray).frame(maxWidth: .infinity)
                }
                Button {
                    controller.sellSelected()
                } label: {
                    Text(L("Sell +\(Format.short(tower.sellValue(rules: rules)))")).frame(maxWidth: .infinity)
                }
                .buttonStyle(PanelButtonStyle(color: Theme.warning))
                .disabled(busy)
            }
        }
        .padding(Theme.s(8))
        .background(RoundedRectangle(cornerRadius: Theme.s(8)).fill(Color.black.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: Theme.s(8)).stroke(Theme.dimGreen, lineWidth: Theme.s(1)))
        .padding(Theme.s(6))
    }

    private var status: String {
        switch tower.activity {
        case .ready: controller.hasPendingAction(towerId: tower.id) ? L("order pending") : L("ready")
        case .building: L("under construction")
        case .upgrading: L("upgrading")
        case .selling: L("being sold")
        case .retargeting: L("new target")
        }
    }
}

/// One option of a choice in the tower panel: green and filled when chosen.
struct ChipStyle: ButtonStyle {
    var on: Bool
    /// Fixed width instead of an equal share of the row (the lock).
    var width: CGFloat?
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(10, .bold))
            .foregroundStyle(on ? Color.black : (enabled ? Theme.text : .gray))
            .lineLimit(1)
            .padding(.vertical, Theme.s(6))
            .padding(.horizontal, Theme.s(2))
            .frame(maxWidth: width ?? .infinity)
            .frame(width: width)
            .background(RoundedRectangle(cornerRadius: Theme.s(5)).fill(on ? (enabled ? Theme.green : Theme.dimGreen) : Color.black))
            .overlay(RoundedRectangle(cornerRadius: Theme.s(5)).stroke(on ? Color.clear : Color.gray.opacity(0.5), lineWidth: Theme.s(1)))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct PanelButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(11, .bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.vertical, Theme.s(8))
            .padding(.horizontal, Theme.s(4))
            .background(RoundedRectangle(cornerRadius: Theme.s(5)).fill(Color.black))
            .overlay(RoundedRectangle(cornerRadius: Theme.s(5)).stroke(color, lineWidth: Theme.s(1)))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
