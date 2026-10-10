import SwiftUI
import Charts
import CreepSmashCore

/// Evaluation of a finished game: key numbers and the course of income and lives of both players.
struct GameReportView: View {
    let summary: GameSummary
    let myName: String
    @Environment(\.dismiss) private var dismiss

    /// Series colors, checked for contrast on the dark panel: you in green, the opponents in violet, orange
    /// and blue. With more than two players the opponents' lines are also dashed differently, so they stay
    /// apart for color-blind players too.
    static let colors: [Color] = [
        Color(red: 0x26 / 255, green: 0xa6 / 255, blue: 0x26 / 255),
        Color(red: 0xa8 / 255, green: 0x5c / 255, blue: 0xe0 / 255),
        Color(red: 0xd9 / 255, green: 0x59 / 255, blue: 0x26 / 255),
        Color(red: 0x39 / 255, green: 0x87 / 255, blue: 0xe5 / 255),
    ]
    static let dashes: [[CGFloat]] = [[], [7, 4], [2, 3], [9, 3, 2, 3]]

    /// Opponent(s) for the title line.
    private var opponentName: String {
        series.count > 2 ? series.dropFirst().map(\.name).joined(separator: ", ") : (series.last?.name ?? L("Opponent"))
    }

    /// One line per player: you first, then the opponents in ring order. Older records only know
    /// "you" and "the opponent".
    private var series: [Series] {
        guard let names = summary.playerNames, let me = summary.me, summary.samples.last?.players != nil else {
            var other = summary.opponentName ?? L("Opponent")
            if other == myName { other += " (2)" }
            return [Series(id: 0, name: myName, index: nil, mine: true), Series(id: 1, name: other, index: nil, mine: false)]
        }
        let order = [me] + (1..<names.count).map { (me + $0) % names.count }
        var used = Set<String>()
        return order.enumerated().map { position, index in
            var name = index == me ? myName : (names[index].isEmpty ? L("Opponent") : names[index])
            // The chart tells the players apart by name, so all names must differ.
            while used.contains(name) { name += " (\(index + 1))" }
            used.insert(name)
            return Series(id: position, name: name, index: index, mine: index == me)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(L("Evaluation")) { dismiss() }
                .padding(.horizontal, Theme.s(20))
                .padding(.vertical, Theme.s(10))
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s(14)) {
                    header
                    numbers
                    if summary.samples.count >= 2 {
                        // Side by side where there is room (landscape), otherwise below each other.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.s(320)), spacing: Theme.s(12))],
                                  spacing: Theme.s(12)) {
                            CourseChart(title: L("Income"), symbol: "arrow.up.right", summary: summary, series: series,
                                        value: { $0.income }, legacy: { s, mine in mine ? s.myIncome : s.opponentIncome })
                            CourseChart(title: L("Lives"), symbol: "heart.fill", summary: summary, series: series,
                                        value: { $0.lives }, legacy: { s, mine in mine ? s.myLives : s.opponentLives })
                            // Totals so far (recorded since this version): attack and defense.
                            if summary.samples.last?.myHealthSent != nil {
                                CourseChart(title: L("Attack strength"), symbol: "arrow.up.forward.circle.fill",
                                            summary: summary, series: series, value: { $0.healthSent },
                                            legacy: { s, mine in mine ? s.myHealthSent : s.opponentHealthSent })
                                CourseChart(title: L("Damage by towers"), symbol: "scope",
                                            summary: summary, series: series, value: { $0.damage },
                                            legacy: { s, mine in mine ? s.myDamage : s.opponentDamage })
                            }
                        }
                    } else {
                        Text(L("The game was too short for a course."))
                            .font(Theme.mono(14)).foregroundStyle(.gray)
                    }
                }
                .padding(.horizontal, Theme.s(20))
                .padding(.vertical, Theme.s(12))
            }
            .background(Theme.background)
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .pageSizedSheet()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.s(12)) {
            Text(summary.won ? L("Won") : L("Lost"))
                .font(Theme.pixel(16))
                .foregroundStyle(summary.won ? Theme.green : Theme.warning)
            Text("\(myName) – \(opponentName)").font(Theme.mono(14)).foregroundStyle(Theme.text)
            Spacer(minLength: 0)
            Text(L(key: GameMap.named(summary.mapID)?.name ?? summary.mapID) + " · "
                 + HallOfFameView.minutes(summary.seconds))
                .font(Theme.mono(14)).foregroundStyle(.gray)
        }
    }

    private var numbers: some View {
        let items: [(String, String, String)] = [
            ("arrow.up.right", L("Creeps sent"), Format.credits(summary.creepsSent)),
            ("scope", L("Creeps shot down"), Format.credits(summary.creepsKilled)),
            ("building.2.fill", L("Towers built"), Format.credits(summary.towersBuilt)),
            ("heart.slash.fill", L("Lives lost"), "\(summary.livesLost)"),
        ] + (summary.healthSent.map { [("arrow.up.forward.circle.fill", L("Attack strength"), Format.short($0))] } ?? [])
          + (summary.damageDealt.map { [("scope", L("Damage by towers"), Format.short($0))] } ?? [])
        // Six tiles (four in older records): all in one row, in two rows or in two columns –
        // never a single tile left over.
        return ViewThatFits(in: .horizontal) {
            tiles(items, columns: items.count)
            tiles(items, columns: items.count / 2)
            tiles(items, columns: 2)
        }
    }

    private func tiles(_ items: [(String, String, String)], columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: Theme.s(140)), spacing: Theme.s(10)),
                                 count: min(columns, items.count)),
                  spacing: Theme.s(10)) {
            ForEach(items, id: \.1) { symbol, title, value in tile(symbol, title, value) }
        }
    }

    private func tile(_ symbol: String, _ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.s(4)) {
            Label(title, systemImage: symbol)
                .font(Theme.mono(14)).foregroundStyle(.gray)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(value).font(Theme.pixel(15)).foregroundStyle(Theme.text).lineLimit(1)
        }
        .padding(Theme.s(10))
        // Same height for all tiles, whether the title takes one line or two.
        .frame(maxWidth: .infinity, minHeight: Theme.s(84), alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.s(8)).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Theme.s(8)).stroke(Theme.dimGreen.opacity(0.6)))
    }
}

/// One line of a course chart: a player.
struct Series: Identifiable {
    let id: Int
    let name: String
    /// Index of the player in the game; nil for older records (you / opponent only).
    let index: Int?
    let mine: Bool

    var color: Color { GameReportView.colors[id % GameReportView.colors.count] }
    var dash: [CGFloat] { GameReportView.dashes[id % GameReportView.dashes.count] }
}

/// One measure of all players over the game time. Touching the chart shows the values at that moment.
private struct CourseChart: View {
    let title: String
    let symbol: String
    let summary: GameSummary
    let series: [Series]
    /// The measure for one player.
    let value: (PlayerSample) -> Int
    /// The same measure in older records (you or the opponent).
    let legacy: (GameSample, Bool) -> Int?
    @State private var selectedMinute: Double?

    private struct Point: Identifiable {
        let id = UUID()
        let minute: Double
        let value: Int
        let player: String
    }

    /// Game time in minutes (counted from the start, after the countdown).
    private func minute(_ sample: GameSample) -> Double {
        Double(max(0, sample.tick - Rules.standard.startTick)) * Double(Rules.standard.tickMilliseconds) / 60_000
    }

    private func value(_ sample: GameSample, _ line: Series) -> Int? {
        if let index = line.index, let players = sample.players, players.indices.contains(index) {
            return value(players[index])
        }
        return legacy(sample, line.mine)
    }

    private var points: [Point] {
        summary.samples.flatMap { s in
            series.compactMap { line in value(s, line).map { Point(minute: minute(s), value: $0, player: line.name) } }
        }
    }

    /// The sample closest to the touched moment.
    private var selected: GameSample? {
        guard let selectedMinute else { return nil }
        return summary.samples.min { abs(minute($0) - selectedMinute) < abs(minute($1) - selectedMinute) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s(8)) {
            Label(title, systemImage: symbol).font(Theme.pixel(11)).foregroundStyle(Theme.green)
            // Legend: one entry per player, with the line's color and dash.
            HStack(spacing: Theme.s(12)) {
                ForEach(series) { legend($0) }
            }
            Chart {
                ForEach(points) { p in
                    LineMark(x: .value(L("Minute"), p.minute), y: .value(title, p.value))
                        .foregroundStyle(by: .value(L("Player"), p.player))
                        .lineStyle(by: .value(L("Player"), p.player))
                        .interpolationMethod(.stepEnd)
                }
                if let s = selected {
                    RuleMark(x: .value(L("Minute"), minute(s)))
                        .foregroundStyle(Color.gray.opacity(0.6))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(HallOfFameView.minutes(Int(minute(s) * 60)))
                                    .foregroundStyle(.gray)
                                ForEach(series) { line in
                                    Text("\(line.name): \(value(s, line).map(Format.credits) ?? "–")")
                                }
                            }
                            .font(Theme.mono(14))
                            .foregroundStyle(Theme.text)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.9)))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5)))
                        }
                }
            }
            .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
            .chartLineStyleScale(domain: series.map(\.name),
                                 range: series.map { StrokeStyle(lineWidth: 2, dash: $0.dash) })
            .chartLegend(.hidden)
            .chartXSelection(value: $selectedMinute)
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.2))
                    AxisValueLabel {
                        if let m = value.as(Double.self) { Text("\(Int(m)) min").font(Theme.mono(14)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.2))
                    AxisValueLabel {
                        if let v = value.as(Int.self) { Text(Format.short(v)).font(Theme.mono(14)) }
                    }
                }
            }
            .frame(height: Theme.s(170))
        }
        .padding(Theme.s(12))
        .background(RoundedRectangle(cornerRadius: Theme.s(8)).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Theme.s(8)).stroke(Theme.dimGreen.opacity(0.6)))
    }

    private func legend(_ line: Series) -> some View {
        HStack(spacing: Theme.s(4)) {
            Path { p in p.move(to: CGPoint(x: 0, y: 1.5)); p.addLine(to: CGPoint(x: Theme.s(18), y: 1.5)) }
                .stroke(line.color, style: StrokeStyle(lineWidth: 3, dash: line.dash))
                .frame(width: Theme.s(18), height: 3)
            Text(line.name).font(Theme.mono(14)).foregroundStyle(Theme.text).lineLimit(1)
        }
    }
}
