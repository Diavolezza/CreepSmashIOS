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
            PageHeader(L("Evaluation")) { withoutSliding { dismiss() } }
                .padding(.horizontal, Theme.s(20))
                .padding(.vertical, Theme.s(10))
            ScrollViewReader { proxy in
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
                        // The own defense: installed capacity, attack and what was stopped, per income round.
                        if let me = summary.me, summary.samples.last?.players?.indices.contains(me) == true,
                           summary.samples.last?.players?[me].capacity != nil {
                            CapacityChart(summary: summary, player: me)
                                .id("capacity")
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
            .onAppear {
                // Screenshots: "-reportBottom" shows the end of the evaluation.
                if ProcessInfo.processInfo.arguments.contains("-reportBottom") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("capacity", anchor: .bottom) }
                }
            }
            }
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

    /// A number tile: title, value, optionally a line below (comparison with the opponents).
    private struct Tile {
        let symbol: String, title: String, value: String
        var detail: String? = nil
    }

    private var numbers: some View {
        var items = [
            Tile(symbol: "arrow.up.right", title: L("Creeps sent"), value: Format.credits(summary.creepsSent)),
            Tile(symbol: "scope", title: L("Creeps shot down"), value: Format.credits(summary.creepsKilled)),
            // What the towers standing at the end cost (older records: how many were built).
            summary.towerValue.map { Tile(symbol: "building.2.fill", title: L("Tower value"), value: Format.credits($0)) }
                ?? Tile(symbol: "building.2.fill", title: L("Towers built"), value: Format.credits(summary.towersBuilt)),
            Tile(symbol: "heart.slash.fill", title: L("Lives lost"), value: "\(summary.livesLost)"),
        ]
        if let health = summary.healthSent {
            items.append(Tile(symbol: "arrow.up.forward.circle.fill", title: L("Attack strength"), value: Format.short(health)))
        }
        if let defense = summary.myDefense {
            // Effectiveness, efficiency per unit of work, idle capacity – each with the opponents' value.
            items.append(Tile(symbol: "shield.lefthalf.filled", title: L("Defense rate"),
                              value: Self.percent(defense.stoppedPermille),
                              detail: comparison(Self.percent(summary.opponentMean(\.stoppedPermille)))))
            items.append(Tile(symbol: "leaf.fill", title: L("Cost per 1,000 stopped"),
                              value: Self.tenths(defense.creditsPerThousandTenths),
                              detail: comparison(Self.tenths(summary.opponentMean(\.creditsPerThousandTenths)))))
            items.append(Tile(symbol: "moon.zzz.fill", title: L("Zombie towers"), value: "\(defense.zombieTowers)",
                              detail: comparison(summary.opponentMean(\.zombieTowers).map(String.init) ?? "–")))
        } else if let damage = summary.damageDealt {
            items.append(Tile(symbol: "scope", title: L("Damage by towers"), value: Format.short(damage)))
        }
        // All tiles equally high: if some have a comparison line, the others get an empty one.
        if items.contains(where: { $0.detail != nil }) {
            items = items.map { var t = $0; t.detail = t.detail ?? " "; return t }
        }
        // Eight tiles (six or four in older records): all in one row, in two rows or in two columns –
        // never a single tile left over.
        return ViewThatFits(in: .horizontal) {
            tiles(items, columns: items.count)
            tiles(items, columns: items.count / 2)
            tiles(items, columns: 2)
        }
    }

    /// "Opponent 81 %" with one opponent, "Ø opponents 81 %" with several.
    private func comparison(_ value: String) -> String {
        (summary.opponentDefense.count > 1 ? L("Ø opponents") : L("Opponent")) + " " + value
    }

    static func percent(_ permille: Int?) -> String {
        permille.map { "\(($0 + 5) / 10) %" } ?? "–"
    }

    static func tenths(_ tenths: Int?) -> String {
        tenths.map { (Double($0) / 10).formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.current.locale)) } ?? "–"
    }

    private func tiles(_ items: [Tile], columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: Theme.s(140)), spacing: Theme.s(10)),
                                 count: min(columns, items.count)),
                  spacing: Theme.s(10)) {
            ForEach(items, id: \.title) { tile($0) }
        }
    }

    private func tile(_ item: Tile) -> some View {
        VStack(alignment: .leading, spacing: Theme.s(4)) {
            Label(item.title, systemImage: item.symbol)
                .font(Theme.mono(14)).foregroundStyle(.gray)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(item.value).font(Theme.pixel(15)).foregroundStyle(Theme.text).lineLimit(1)
            if let detail = item.detail {
                Text(detail).font(Theme.mono(14)).foregroundStyle(.gray).lineLimit(1)
            }
        }
        .padding(Theme.s(10))
        // Same height for all tiles, whether the title takes one line or two.
        .frame(maxWidth: .infinity, minHeight: Theme.s(item.detail == nil ? 84 : 104), alignment: .topLeading)
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

/// The own defense over the game time, per income round: what the towers could have shot away if creeps
/// had passed them all the time (installed capacity) and what arrived (attack). The gap between them is
/// defense that stood idle – overprovisioning, as in a data center. Red dots mark the rounds in which lives
/// were lost: there the capacity was too small for the peak.
private struct CapacityChart: View {
    let summary: GameSummary
    let player: Int
    @State private var selectedMinute: Double?

    private struct Round {
        let minute: Double
        let capacity: Int
        let attack: Int
        let livesLost: Int
        /// Attack in relation to capacity, in percent.
        var utilization: Int? { capacity > 0 ? attack * 100 / capacity : nil }
    }

    private struct Point: Identifiable {
        let id = UUID()
        let minute: Double
        let value: Int
        let line: String
    }

    private var names: [String] { [L("Capacity"), L("Incoming")] }
    private var colors: [Color] { [Theme.dimGreen, GameReportView.colors[2]] }
    private let dashes: [[CGFloat]] = [[7, 4], []]

    private func minute(_ sample: GameSample) -> Double {
        Double(max(0, sample.tick - Rules.standard.startTick)) * Double(Rules.standard.tickMilliseconds) / 60_000
    }

    private var rounds: [Round] {
        let samples = summary.samples.filter { ($0.players?.count ?? 0) > player }
        guard samples.count >= 2 else { return [] }
        return (1..<samples.count).compactMap { i in
            guard let now = samples[i].players?[player], let before = samples[i - 1].players?[player] else { return nil }
            // The last round can be shorter than a full one: capacity only for the time it lasted.
            let ticks = samples[i].tick - samples[i - 1].tick
            return Round(minute: minute(samples[i]),
                         capacity: (before.capacity ?? 0) * ticks / Rules.standard.incomeIntervalTicks,
                         attack: max(0, (now.arrived ?? 0) - (before.arrived ?? 0)),
                         livesLost: max(0, before.lives - now.lives))
        }
    }

    private var points: [Point] {
        rounds.flatMap { r in
            [Point(minute: r.minute, value: r.capacity, line: names[0]), Point(minute: r.minute, value: r.attack, line: names[1])]
        }
    }

    private var selected: Round? {
        guard let selectedMinute else { return nil }
        return rounds.min { abs($0.minute - selectedMinute) < abs($1.minute - selectedMinute) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s(8)) {
            Label(L("Defense: capacity and attack"), systemImage: "shield.lefthalf.filled")
                .font(Theme.pixel(11)).foregroundStyle(Theme.green)
            HStack(spacing: Theme.s(12)) {
                ForEach(names.indices, id: \.self) { legend($0) }
                HStack(spacing: Theme.s(4)) {
                    Circle().fill(Theme.warning).frame(width: Theme.s(9), height: Theme.s(9))
                    Text(L("Lives lost")).font(Theme.mono(14)).foregroundStyle(Theme.text).lineLimit(1)
                }
            }
            Chart {
                ForEach(points) { p in
                    LineMark(x: .value(L("Minute"), p.minute), y: .value(L("Health"), p.value))
                        .foregroundStyle(by: .value("Line", p.line))
                        .lineStyle(by: .value("Line", p.line))
                        .interpolationMethod(.stepEnd)
                }
                // Rounds with lives lost: a red dot on the attack, the larger the more lives.
                ForEach(rounds.filter { $0.livesLost > 0 }, id: \.minute) { r in
                    PointMark(x: .value(L("Minute"), r.minute), y: .value(L("Health"), r.attack))
                        .symbolSize(CGFloat(min(8, r.livesLost)) * 30 + 30)
                        .foregroundStyle(Theme.warning)
                }
                if let r = selected {
                    RuleMark(x: .value(L("Minute"), r.minute))
                        .foregroundStyle(Color.gray.opacity(0.6))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(HallOfFameView.minutes(Int(r.minute * 60))).foregroundStyle(.gray)
                                Text("\(names[0]): \(Format.short(r.capacity))")
                                Text("\(names[1]): \(Format.short(r.attack))")
                                if let utilization = r.utilization {
                                    Text(L("Utilization \(utilization) %"))
                                }
                                if r.livesLost > 0 {
                                    Text("\(L("Lives lost")): \(r.livesLost)").foregroundStyle(Theme.warning)
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
            .chartForegroundStyleScale(domain: names, range: colors)
            .chartLineStyleScale(domain: names, range: dashes.map { StrokeStyle(lineWidth: 2, dash: $0) })
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
            .frame(height: Theme.s(190))
            Text(caption).font(Theme.mono(14)).foregroundStyle(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.s(12))
        .background(RoundedRectangle(cornerRadius: Theme.s(8)).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Theme.s(8)).stroke(Theme.dimGreen.opacity(0.6)))
    }

    private var caption: String {
        var text = L("Per income round (15 s). Capacity: what your towers could shoot away if creeps passed them all the time. The gap to the attack is defense standing idle; red dots show where it was not enough.")
        if let defense = summary.myDefense, defense.zombieTowers > 0 {
            text += " " + L("Zombie towers at the end: \(defense.zombieTowers), together \(Format.credits(defense.zombieValue)) credits.")
        }
        return text
    }

    private func legend(_ i: Int) -> some View {
        HStack(spacing: Theme.s(4)) {
            Path { p in p.move(to: CGPoint(x: 0, y: 1.5)); p.addLine(to: CGPoint(x: Theme.s(18), y: 1.5)) }
                .stroke(colors[i], style: StrokeStyle(lineWidth: 3, dash: dashes[i]))
                .frame(width: Theme.s(18), height: 3)
            Text(names[i]).font(Theme.mono(14)).foregroundStyle(Theme.text).lineLimit(1)
        }
    }
}
