import SwiftUI
import CreepSmashCore

// Views for games with more than two players.

/// Where the own creeps go: the next player in the ring, all opponents, or one at random.
struct SendModePicker: View {
    let controller: GameController
    /// iPhone: one button with a menu instead of three segments.
    let compact: Bool

    var body: some View {
        let current = controller.hud.sendMode
        if compact {
            Menu {
                ForEach(SendMode.allCases, id: \.self) { mode in
                    Button { controller.setSendMode(mode) } label: {
                        Label(mode.label, systemImage: mode.symbol)
                    }
                }
            } label: {
                HStack(spacing: Theme.s(4)) {
                    Image(systemName: current.symbol)
                    Text(current.label).lineLimit(1).minimumScaleFactor(0.6)
                }
                .font(Theme.mono(12, .semibold))
                .foregroundStyle(Theme.gold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.s(6)).fill(Color.black))
                .overlay(RoundedRectangle(cornerRadius: Theme.s(6)).stroke(Theme.gold.opacity(0.6), lineWidth: 1))
            }
            .accessibilityLabel(L("Send creeps to: \(current.label)"))
        } else {
            HStack(spacing: Theme.s(3)) {
                ForEach(SendMode.allCases, id: \.self) { mode in
                    Button { controller.setSendMode(mode) } label: {
                        HStack(spacing: Theme.s(4)) {
                            Image(systemName: mode.symbol)
                            Text(mode.label).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .font(Theme.mono(12, .semibold))
                        .foregroundStyle(mode == current ? Color.black : Theme.text)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: Theme.s(5)).fill(mode == current ? Theme.gold : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.s(3))
            .background(RoundedRectangle(cornerRadius: Theme.s(7)).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: Theme.s(7)).stroke(Color.gray.opacity(0.35), lineWidth: 1))
        }
    }
}

extension SendMode {
    var label: String {
        switch self {
        case .next: L("Next")
        case .all: L("All")
        case .random: L("Random")
        }
    }

    var symbol: String {
        switch self {
        case .next: "arrow.right"
        case .all: "arrow.triangle.branch"
        case .random: "shuffle"
        }
    }
}

/// An opponent's board, small, with name, lives and income above it. The board that receives the
/// own creeps is framed in gold; a player who is out is darkened.
struct SmallBoard: View {
    let controller: GameController
    let info: GameController.OpponentInfo
    let side: CGFloat
    let labelHeight: CGFloat

    var body: some View {
        VStack(spacing: Theme.s(2)) {
            // Full numbers if they fit, otherwise shorter ones (1,4k); the name is cut last.
            ViewThatFits(in: .horizontal) {
                label(format: Format.credits, cutName: false)
                label(format: Format.compact, cutName: false)
                label(format: Format.compact, cutName: true)
            }
            .labelStyle(CompactLabelStyle())
            .font(Theme.mono(11, .semibold))
            .frame(width: side, height: labelHeight)
            BoardView(controller: controller, player: info.id, interactive: false)
                .frame(width: side, height: side)
                .overlay {
                    if info.isDead {
                        ZStack {
                            Color.black.opacity(0.6)
                            Text(L("Out")).font(Theme.pixel(12)).foregroundStyle(Theme.warning)
                        }
                    } else if info.isTarget {
                        Rectangle().stroke(Theme.gold, lineWidth: Theme.s(2))
                    }
                }
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(info.name), \(info.lives) lives") + (info.isTarget ? ", " + L("receives your creeps") : ""))
    }

    private func label(format: (Int) -> String, cutName: Bool) -> some View {
        HStack(spacing: Theme.s(6)) {
            Text(info.name)
                .foregroundStyle(info.isTarget ? Theme.gold : Theme.text)
                .lineLimit(1)
                .fixedSize(horizontal: !cutName, vertical: false)
            Spacer(minLength: 2)
            Label("\(info.lives)", systemImage: "heart.fill")
                .foregroundStyle(info.lives <= 5 ? Theme.warning : .gray)
                .fixedSize()
            Label("+" + format(info.income), systemImage: "arrow.up.right")
                .foregroundStyle(.gray)
                .fixedSize()
        }
    }
}

/// iPhone with more than two players: one chip per opponent above the large opponent board. A tap shows
/// that opponent's board; the gold arrow marks who receives the own creeps.
struct OpponentChips: View {
    let controller: GameController

    var body: some View {
        HStack(spacing: Theme.s(4)) {
            ForEach(controller.hud.opponents) { info in
                let shown = controller.shownOpponent == info.id
                Button { controller.view(opponent: info.id) } label: {
                    HStack(spacing: Theme.s(3)) {
                        if info.isTarget { Image(systemName: "arrowtriangle.right.fill").imageScale(.small) }
                        Text(info.name).lineLimit(1).minimumScaleFactor(0.6)
                        Text(info.isDead ? L("Out") : "♥\(info.lives)").foregroundStyle(info.lives <= 5 ? Theme.warning : .gray)
                    }
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(info.isTarget ? Theme.gold : Theme.text)
                    .padding(.horizontal, Theme.s(4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: Theme.s(6)).fill(shown ? Color(white: 0.16) : Color.black))
                    .overlay(RoundedRectangle(cornerRadius: Theme.s(6))
                        .stroke(shown ? Theme.gold : Color.gray.opacity(0.35), lineWidth: shown ? Theme.s(1.5) : 1))
                    .opacity(info.isDead ? 0.5 : 1)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.s(2)) {
            configuration.icon.imageScale(.small)
            configuration.title.monospacedDigit()
        }
    }
}
