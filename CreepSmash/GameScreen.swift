import SwiftUI
import CreepSmashCore

struct GameScreen: View {
    @Bindable var controller: GameController
    let onRestart: () -> Void
    let onExit: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOptions = false
    @State private var showReport = false

    var body: some View {
        GeometryReader { geo in
            // The arrangement depends on the shape of the window: iPhone landscape – controls left and right
            // of the boards; iPad landscape – controls below the boards; a window taller than wide (possible
            // with iPad window resizing) – the boards on top of each other, the controls to their right.
            let ratio = geo.size.height / geo.size.width
            if ratio < 0.6 {
                wideLayout(geo.size)
            } else if ratio < 1.05 {
                if controller.isGroup { groupTallLayout(geo.size) } else { tallLayout(geo.size) }
            } else {
                if controller.isGroup { groupStackedLayout(geo.size) } else { stackedLayout(geo.size) }
            }
        }
        .padding(.horizontal, Theme.s(4))
        .background(Theme.background.ignoresSafeArea())
        // Tooltip of the tower or creep button under the pointer, above everything else.
        .overlayPreferenceValue(HoverTipKey.self) { tip in
            if let tip { HoverTipBubble(tip: tip) }
        }
        .overlay { if controller.isPaused, !isFinished, controller.connectionProblem == nil { pauseOverlay } }
        .overlay { if case let .finished(rank) = controller.hud.phase { finishedOverlay(rank: rank) } }
        .overlay { if let problem = controller.connectionProblem { problemOverlay(problem) } }
        .sheet(isPresented: $showOptions) { OptionsView() }
        .sheet(isPresented: $showReport) {
            if let summary = controller.summary {
                GameReportView(summary: summary, myName: controller.hud.myName)
            }
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, !isFinished { controller.setPaused(true) }
        }
    }

    private var spacing: CGFloat { Theme.s(6) }
    private var headerHeight: CGFloat { Theme.s(32) }
    private var pauseWidth: CGFloat { Theme.s(40) }

    /// Header row: the player's header, in the middle the income timer (it ticks for both players) and the
    /// pause button – centered above the gap between the boards – then the opponent's header.
    private func headerRow(leftWidth: CGFloat, rightWidth: CGFloat) -> some View {
        HStack(spacing: spacing) {
            PlayerHeader(controller: controller, isMe: true)
                .frame(width: leftWidth, height: headerHeight)
            IncomeTimer(seconds: controller.hud.secondsToIncome, fraction: controller.hud.incomeFraction,
                        running: !isFinished && !controller.isPaused)
                .frame(width: headerHeight, height: headerHeight)
                .zIndex(1)
            pauseButton
                .frame(width: pauseWidth, height: headerHeight)
            if controller.isGroup {
                // More than two players (iPhone): one chip per opponent instead of the opponent's header.
                OpponentChips(controller: controller)
                    .frame(width: rightWidth, height: headerHeight)
            } else {
                PlayerHeader(controller: controller, isMe: false)
                    .frame(width: rightWidth, height: headerHeight)
            }
        }
    }

    private var ownBoard: some View {
        BoardView(controller: controller, player: controller.me)
            .overlay { boardOverlay }
            .overlay(alignment: detailAlignment) { towerDetail }
    }

    /// iPhone: towers on the left, then the own board, the opponent's board, creeps on the right. The
    /// player's header spans the tower column and the own board, the opponent's header the opponent's
    /// board and the creep column.
    private func wideLayout(_ size: CGSize) -> some View {
        let centerWidth = headerHeight + spacing + pauseWidth
        let towerWidth = max(50, size.width * 0.065)
        let creepWidth = max(86, size.width * 0.11)
        let side = min(size.height - headerHeight - spacing,
                       (size.width - towerWidth - creepWidth - 3 * spacing) / 2)
        return VStack(spacing: spacing) {
            Spacer(minLength: 0)
            headerRow(leftWidth: towerWidth + side + spacing / 2 - centerWidth / 2,
                      rightWidth: side + creepWidth + spacing / 2 - centerWidth / 2)
                .zIndex(1)
            HStack(alignment: .top, spacing: spacing) {
                TowerColumn(controller: controller, height: side)
                    .frame(width: towerWidth, height: side)
                ownBoard
                    .frame(width: side, height: side)
                opponentBoard
                    .frame(width: side, height: side)
                if controller.isGroup {
                    VStack(spacing: spacing) {
                        SendModePicker(controller: controller, compact: true)
                            .frame(height: headerHeight)
                        CreepColumn(controller: controller, height: side - headerHeight - spacing)
                    }
                    .frame(width: creepWidth, height: side)
                } else {
                    CreepColumn(controller: controller, height: side)
                        .frame(width: creepWidth, height: side)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height)
    }

    /// iPad: both boards as large as the width allows, below the own board the six towers in a row,
    /// below the opponent's board the creeps in two rows – they are sent there.
    private func tallLayout(_ size: CGSize) -> some View {
        let controlsShare: CGFloat = 0.2
        let side = min((size.width - spacing) / 2,
                       (size.height - headerHeight - 2 * spacing) / (1 + controlsShare))
        let controlsHeight = side * controlsShare
        let headerWidth = side - (headerHeight + pauseWidth) / 2 - spacing
        return VStack(spacing: spacing) {
            Spacer(minLength: 0)
            headerRow(leftWidth: headerWidth, rightWidth: headerWidth)
                .zIndex(1)
            HStack(alignment: .top, spacing: spacing) {
                ownBoard
                    .frame(width: side, height: side)
                opponentBoard
                    .frame(width: side, height: side)
            }
            HStack(alignment: .top, spacing: spacing) {
                TowerColumn(controller: controller, height: controlsHeight, horizontal: true)
                    .frame(width: side, height: controlsHeight)
                CreepColumn(controller: controller, height: controlsHeight, horizontal: true)
                    .frame(width: side, height: controlsHeight)
            }
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height)
    }

    /// Portrait: the opponent's board on top with the creeps next to it (that is where they are sent),
    /// below it the player's own board with the towers next to it – closest to the player's hands.
    private func stackedLayout(_ size: CGSize) -> some View {
        let minColumn = max(86, size.width * 0.11)
        let side = min(size.width - minColumn - spacing,
                       (size.height - 2 * headerHeight - 3 * spacing) / 2)
        // Space left over at the side goes to the controls, so towers and creeps get bigger buttons.
        let columnWidth = max(minColumn, min(size.width - side - spacing, side * 0.45))
        let rowWidth = side + spacing + columnWidth
        return VStack(spacing: spacing) {
            Spacer(minLength: 0)
            HStack(spacing: spacing) {
                PlayerHeader(controller: controller, isMe: false)
                    .frame(width: rowWidth - headerHeight - pauseWidth - 2 * spacing, height: headerHeight)
                IncomeTimer(seconds: controller.hud.secondsToIncome, fraction: controller.hud.incomeFraction,
                        running: !isFinished && !controller.isPaused)
                    .frame(width: headerHeight, height: headerHeight)
                pauseButton
                    .frame(width: pauseWidth, height: headerHeight)
            }
            HStack(alignment: .top, spacing: spacing) {
                opponentBoard
                    .frame(width: side, height: side)
                CreepColumn(controller: controller, height: side)
                    .frame(width: columnWidth, height: side)
            }
            PlayerHeader(controller: controller, isMe: true)
                .frame(width: rowWidth, height: headerHeight)
            HStack(alignment: .top, spacing: spacing) {
                ownBoard
                    .frame(width: side, height: side)
                TowerColumn(controller: controller, height: side)
                    .frame(width: columnWidth, height: side)
            }
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder private var opponentBoard: some View {
        if let opponent = controller.shownOpponent {
            BoardView(controller: controller, player: opponent, interactive: false)
                .overlay {
                    // More than two players: the board that receives the own creeps is framed in gold.
                    if controller.isGroup, controller.hud.opponents.first(where: { $0.id == opponent })?.isTarget == true {
                        Rectangle().stroke(Theme.gold, lineWidth: Theme.s(2)).allowsHitTesting(false)
                    }
                }
        } else {
            Color.clear
        }
    }

    // MARK: - More than two players

    private var smallLabelHeight: CGFloat { Theme.s(18) }

    /// iPad landscape, more than two players: the own board large on the left with the towers below it;
    /// on the right the opponents' boards small, one below the other, and next to them the creeps.
    private func groupTallLayout(_ size: CGSize) -> some View {
        let towersShare: CGFloat = 0.2
        let side = min(size.height - headerHeight - 3 * spacing - Theme.s(8), size.width * 0.52) / (1 + towersShare)
        let towersHeight = side * towersShare
        let rightWidth = size.width - side - 2 * spacing
        let columnHeight = headerHeight + side + towersHeight + 2 * spacing
        let count = CGFloat(max(1, controller.hud.opponents.count))
        let small = min((columnHeight - (count - 1) * spacing) / count - smallLabelHeight, rightWidth * 0.42)
        let creepWidth = rightWidth - small - spacing
        return HStack(alignment: .top, spacing: spacing) {
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    PlayerHeader(controller: controller, isMe: true)
                    IncomeTimer(seconds: controller.hud.secondsToIncome, fraction: controller.hud.incomeFraction,
                                running: !isFinished && !controller.isPaused)
                        .frame(width: headerHeight, height: headerHeight)
                        .zIndex(1)
                    pauseButton
                        .frame(width: pauseWidth, height: headerHeight)
                }
                .frame(width: side, height: headerHeight)
                .zIndex(1)
                ownBoard
                    .frame(width: side, height: side)
                TowerColumn(controller: controller, height: towersHeight, horizontal: true)
                    .frame(width: side, height: towersHeight)
            }
            VStack(spacing: spacing) {
                ForEach(controller.hud.opponents) { info in
                    SmallBoard(controller: controller, info: info, side: small, labelHeight: smallLabelHeight)
                }
            }
            .frame(width: small)
            VStack(spacing: spacing) {
                SendModePicker(controller: controller, compact: false)
                    .frame(height: headerHeight)
                CreepGrid(controller: controller, columns: 4)
                    .frame(height: columnHeight - headerHeight - spacing)
            }
            .frame(width: creepWidth)
        }
        .frame(height: columnHeight)
        .frame(width: size.width, height: size.height)
    }

    /// iPad portrait, more than two players: the opponents small in a row at the top, below them the
    /// creeps, then the own board large with the towers next to it – closest to the player's hands.
    private func groupStackedLayout(_ size: CGSize) -> some View {
        let count = CGFloat(max(1, controller.hud.opponents.count))
        let small = min((size.width - (count - 1) * spacing) / count, size.height * 0.22)
        let creepsHeight = min(size.width / 8 * 1.1, size.height * 0.13)
        let fixed = smallLabelHeight + small + headerHeight + creepsHeight + headerHeight + 5 * spacing
        let towerWidth = max(Theme.s(70), size.width * 0.13)
        let side = min(size.width - towerWidth - spacing, size.height - fixed)
        let rowWidth = side + spacing + towerWidth
        return VStack(spacing: spacing) {
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: spacing) {
                ForEach(controller.hud.opponents) { info in
                    SmallBoard(controller: controller, info: info, side: small, labelHeight: smallLabelHeight)
                }
            }
            SendModePicker(controller: controller, compact: false)
                .frame(height: headerHeight)
            CreepGrid(controller: controller, columns: 8)
                .frame(height: creepsHeight)
            HStack(spacing: spacing) {
                PlayerHeader(controller: controller, isMe: true)
                IncomeTimer(seconds: controller.hud.secondsToIncome, fraction: controller.hud.incomeFraction,
                            running: !isFinished && !controller.isPaused)
                    .frame(width: headerHeight, height: headerHeight)
                    .zIndex(1)
                pauseButton
                    .frame(width: pauseWidth, height: headerHeight)
            }
            .frame(width: rowWidth, height: headerHeight)
            // The clock is drawn a little larger than its row; keep it above the board below.
            .zIndex(1)
            HStack(alignment: .top, spacing: spacing) {
                ownBoard
                    .frame(width: side, height: side)
                TowerColumn(controller: controller, height: side)
                    .frame(width: towerWidth, height: side)
            }
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height)
    }

    private var pauseButton: some View {
        Button {
            controller.setPaused(true)
        } label: {
            Image(systemName: "pause.fill")
                .font(.system(size: Theme.s(14), weight: .bold))
                .foregroundStyle(Theme.green)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.s(6)).fill(Color.black))
                .overlay(RoundedRectangle(cornerRadius: Theme.s(6)).stroke(Theme.dimGreen, lineWidth: Theme.s(1)))
        }
        .accessibilityLabel(L("Pause"))
    }

    /// Detail panel of the selected tower: at the bottom if the tower is in the upper half, otherwise at the top.
    @ViewBuilder private var towerDetail: some View {
        let _ = controller.hud.tick
        if let tower = controller.selectedTower {
            TowerDetail(controller: controller, tower: tower)
        }
    }

    private var detailAlignment: Alignment {
        guard let tower = controller.selectedTower else { return .bottom }
        return tower.cell.y < Board.cells / 2 ? .bottom : .top
    }

    private var isFinished: Bool {
        if case .finished = controller.hud.phase { return true }
        return false
    }

    @ViewBuilder private var boardOverlay: some View {
        ZStack {
            if case let .countdown(seconds) = controller.hud.phase {
                VStack(spacing: Theme.s(8)) {
                    Text(L("Game starts in")).font(Theme.pixel(14))
                    Text("\(seconds)").font(Theme.pixel(72))
                }
                .foregroundStyle(Theme.warning)
                .shadow(color: .black, radius: 4)
                .allowsHitTesting(false)
            }
            if controller.isWaitingForOpponent, controller.connectionProblem == nil {
                VStack {
                    Text(L("Waiting for \(controller.hud.opponentName) …"))
                        .font(Theme.mono(13, .semibold))
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, Theme.s(12)).padding(.vertical, Theme.s(6))
                        .background(Capsule().fill(Color.black.opacity(0.8)))
                        .padding(.top, Theme.s(10))
                    Spacer()
                }
                .allowsHitTesting(false)
            }
            if let toast = controller.toast {
                VStack {
                    Spacer()
                    Text(toast.text)
                        .font(Theme.mono(13, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.s(12)).padding(.vertical, Theme.s(6))
                        .background(Capsule().fill(Color.black.opacity(0.8)))
                        .overlay(Capsule().stroke(Theme.warning, lineWidth: Theme.s(1)))
                        .padding(.bottom, Theme.s(10))
                }
                .transition(.opacity)
                .allowsHitTesting(false)
                .id(toast.id)
            }
        }
        .animation(.easeOut(duration: 0.2), value: controller.toast)
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: Theme.s(14)) {
                Text(L("Pause")).font(Theme.pixel(28)).foregroundStyle(Theme.green)
                if controller.pausedByOpponent {
                    Text(L("\(controller.hud.opponentName) has paused the game."))
                        .font(Theme.mono(14)).foregroundStyle(Theme.text)
                }
                // Buttons below each other share one width.
                VStack(spacing: Theme.s(14)) {
                    Button(L("Resume")) { controller.setPaused(false) }
                        .buttonStyle(MenuButtonStyle(fill: true))
                    Button(L("Options")) { showOptions = true }
                        .buttonStyle(MenuButtonStyle(color: Theme.text, fill: true))
                    Button(L("Give up")) { leave() }
                        .buttonStyle(MenuButtonStyle(color: Theme.warning, fill: true))
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    /// Final result as a panel over the frozen game – both boards remain visible behind it.
    private func finishedOverlay(rank: Int?) -> some View {
        let won = rank == 1
        let title = won ? L("You won!") : (controller.game.isFinished && controller.game.winner == nil ? L("Draw") : "Game Over")
        return ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            HStack(alignment: .center, spacing: Theme.s(28)) {
                VStack(alignment: .leading, spacing: Theme.s(6)) {
                    Text(title)
                        .font(Theme.pixel(24))
                        .foregroundStyle(won ? Theme.green : Theme.warning)
                    if !won {
                        Text("sad but true").font(Theme.mono(13)).foregroundStyle(Theme.text)
                    }
                    if controller.isGroup, let rank {
                        Text(L("Place \(rank) of \(controller.game.players.count)"))
                            .font(Theme.pixel(12)).foregroundStyle(won ? Theme.green : Theme.text)
                    }
                    // One column per player: you first, then the others in ring order.
                    let columns = [controller.me] + controller.game.opponents(of: controller.me)
                        + controller.game.players.indices.filter { $0 != controller.me && controller.game.players[$0].isDead }
                    let boards = columns.map { controller.game.players[$0] }
                    Grid(alignment: .leading, horizontalSpacing: Theme.s(14), verticalSpacing: Theme.s(3)) {
                        GridRow {
                            Text("")
                            ForEach(columns, id: \.self) { i in
                                Text(i == controller.me ? L("You") : controller.displayName(i))
                                    .foregroundStyle(i == controller.me ? Theme.green : Theme.dimGreen)
                                    .lineLimit(1)
                            }
                        }
                        GridRow {
                            Text(L("Lives"))
                            ForEach(boards, id: \.index) { Text("\(max(0, $0.lives))") }
                        }
                        GridRow {
                            Text(L("Income"))
                            ForEach(boards, id: \.index) { Text(Format.table($0.income)) }
                        }
                        GridRow {
                            Text(L("Towers"))
                            ForEach(boards, id: \.index) { Text("\($0.towers.count)") }
                        }
                    }
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.text)
                    Text(L("Game time \(Self.duration(ticks: controller.game.tick, rules: controller.game.rules))"))
                        .font(Theme.mono(12)).foregroundStyle(.gray)
                    if let outcome = controller.outcome { outcomeView(outcome) }
                }
                // Buttons below each other share one width.
                VStack(spacing: Theme.s(12)) {
                    if !controller.isOnline {
                        Button(L("Play again")) { onRestart() }.buttonStyle(MenuButtonStyle(fill: true))
                    }
                    if controller.summary != nil {
                        Button(L("Evaluation")) { showReport = true }
                            .buttonStyle(MenuButtonStyle(color: Theme.gold, fill: true))
                    }
                    Button(L("Back to menu")) { leave() }.buttonStyle(MenuButtonStyle(color: Theme.text, fill: true))
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(Theme.s(22))
            .background(RoundedRectangle(cornerRadius: Theme.s(12)).fill(Color.black.opacity(0.82)))
            .overlay(RoundedRectangle(cornerRadius: Theme.s(12)).stroke(won ? Theme.green : Theme.warning, lineWidth: Theme.s(1.5)))
        }
    }

    /// New achievements and leaderboard place at the end of the game.
    @ViewBuilder private func outcomeView(_ outcome: PlayerRecord.Outcome) -> some View {
        if let place = outcome.leaderboardPlace, case let .computer(level) = controller.mode {
            Label(L("Place \(place) on the leaderboard (\(level.label))"), systemImage: "list.number")
                .font(Theme.mono(13)).foregroundStyle(Theme.gold)
                .padding(.top, Theme.s(4))
        }
        if !outcome.unlocked.isEmpty {
            Text(L("New achievements")).font(Theme.pixel(10)).foregroundStyle(Theme.green)
                .padding(.top, Theme.s(6))
            ForEach(outcome.unlocked.prefix(4), id: \.id) { item in
                if let achievement = Achievement.all.first(where: { $0.id == item.id }) {
                    HStack(spacing: Theme.s(8)) {
                        Image(systemName: achievement.symbol)
                            .foregroundStyle(achievement.color(tier: item.tier))
                            .frame(width: Theme.s(20))
                        Text(achievement.title).foregroundStyle(Theme.text)
                        Text(achievement.requirement(achievement.tiers[item.tier - 1]))
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                    .font(Theme.mono(12))
                }
            }
            if outcome.unlocked.count > 4 {
                Text(L("and \(outcome.unlocked.count - 4) more")).font(Theme.mono(12)).foregroundStyle(.gray)
            }
        }
    }

    private func leave() {
        controller.quit()
        onExit()
    }

    private func problemOverlay(_ text: String) -> some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: Theme.s(14)) {
                Text(L("Connection problem")).font(Theme.pixel(20)).foregroundStyle(Theme.warning)
                Text(text).font(Theme.mono(14)).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center).frame(maxWidth: Theme.s(460))
                Button(L("Back to menu")) { leave() }.buttonStyle(MenuButtonStyle(color: Theme.text))
            }
        }
    }

    static func duration(ticks: Int, rules: Rules) -> String {
        let seconds = ticks * rules.tickMilliseconds / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Header above a board, built the same way for both players: one line, one font. The name on the left
/// (always the same size, shortened if needed), on the right lives, credits (own board only – the
/// opponent's credits stay hidden as in the original) and income.
struct PlayerHeader: View {
    let controller: GameController
    let isMe: Bool

    var body: some View {
        let hud = controller.hud
        let name = isMe ? hud.myName : hud.opponentName
        let lives = isMe ? hud.lives : hud.opponentLives
        let income = isMe ? hud.income : hud.opponentIncome
        // Full numbers if everything fits; otherwise shorter numbers (1,4k); only then is the name cut.
        ViewThatFits(in: .horizontal) {
            row(name: name, lives: lives, income: income, format: Format.credits, cutName: false)
            row(name: name, lives: lives, income: income, format: Format.compact, cutName: false)
            row(name: name, lives: lives, income: income, format: Format.compact, cutName: true)
        }
        .font(Theme.mono(15, .semibold))
        .padding(.horizontal, Theme.s(12))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.s(6)).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: Theme.s(6)).stroke(isMe ? Theme.dimGreen : Color.gray.opacity(0.35), lineWidth: Theme.s(1)))
    }

    private func row(name: String, lives: Int, income: Int, format: (Int) -> String, cutName: Bool) -> some View {
        HStack(spacing: Theme.s(12)) {
            Text(name)
                .foregroundStyle(isMe ? Theme.green : Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: !cutName, vertical: false)
            Spacer(minLength: 4)
            HStack(spacing: Theme.s(12)) {
                stat("heart.fill", "\(lives)", lives <= 5 ? Theme.warning : Theme.text)
                if isMe {
                    stat("dollarsign.circle.fill", format(controller.hud.available), Theme.gold)
                }
                stat("arrow.up.right", "+" + format(income), Theme.text)
            }
            .lineLimit(1)
            .fixedSize()
        }
    }

    private func stat(_ symbol: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: Theme.s(4)) {
            Image(systemName: symbol).imageScale(.small)
            Text(value).monospacedDigit()
        }
        .foregroundStyle(color)
    }
}

/// Countdown to the next income payment (for both players at the same time): a ring that runs down,
/// the seconds in the middle. The last three seconds light up.
struct IncomeTimer: View {
    let seconds: Int
    /// Remaining share of the interval, 1 = just paid, 0 = payment now.
    let fraction: Double
    /// False when the game is over or paused: the clock stands still and does not blink.
    var running = true

    var body: some View {
        let soon = running && seconds <= 3
        // The last three seconds blink: gold disc with a dark number, alternating four times a second.
        TimelineView(.animation(minimumInterval: 0.05, paused: !soon)) { timeline in
            let on = !soon || Int(timeline.date.timeIntervalSinceReferenceDate * 4) % 2 == 0
            ZStack {
                Circle().fill(soon && on ? Theme.gold : Color.black)
                Circle().stroke(Color.gray.opacity(0.4), lineWidth: Theme.s(4))
                Circle()
                    .trim(from: 0, to: max(0, min(1, fraction)))
                    .stroke(soon ? Theme.warning : Theme.gold, style: StrokeStyle(lineWidth: Theme.s(4), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(seconds)")
                    .font(Theme.pixel(13))
                    .foregroundStyle(soon ? (on ? Color.black : Theme.gold) : Theme.gold)
            }
            .shadow(color: Theme.gold.opacity(soon && on ? 0.9 : 0), radius: Theme.s(8))
            // Slightly larger than the header row, so it stands out; bigger still while blinking.
            .scaleEffect(soon && on ? 1.3 : 1.15)
        }
        .accessibilityElement()
        .accessibilityLabel(L("Income in \(seconds) seconds"))
    }
}

struct MenuButtonStyle: ButtonStyle {
    var color: Color = Theme.green
    var minWidth: CGFloat = 220
    /// Use the full available width.
    var fill = false
    /// Let long labels shrink to fit; off where all buttons should show the same font size.
    var shrinks = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.pixel(13))
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(shrinks ? 0.7 : 1)
            .fixedSize(horizontal: !shrinks, vertical: false)
            .padding(.horizontal, Theme.s(14))
            .frame(minWidth: minWidth, maxWidth: fill ? .infinity : nil)
            .padding(.vertical, Theme.s(12))
            .background(RoundedRectangle(cornerRadius: Theme.s(6)).fill(Color.black))
            .overlay(RoundedRectangle(cornerRadius: Theme.s(6)).stroke(color, lineWidth: Theme.s(2)))
            // Arcade look: hard shadow offset to the bottom right, pressed = shifted into it.
            .background(RoundedRectangle(cornerRadius: Theme.s(6)).fill(color.opacity(0.35)).offset(x: Theme.s(4), y: Theme.s(4)))
            .offset(x: configuration.isPressed ? Theme.s(3) : 0, y: configuration.isPressed ? Theme.s(3) : 0)
    }
}
