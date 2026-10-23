import SwiftUI
import CreepSmashCore

/// "Records": leaderboard against the computer, statistics and achievements.
struct HallOfFameView: View {
    @Environment(\.dismiss) private var dismiss
    // Launch argument "-recordsTab statistics|achievements" opens another tab (screenshots).
    @State private var tab: Tab
    @State private var level: Bot.Level
    /// Leaderboard for games against this many computers.
    @State private var opponents: Int
    @State private var showLastGame = false
    /// Signed in to Game Center: worldwide or among friends, and what was loaded (nil: not yet or failed).
    @State private var scope: GameCenter.BoardScope = .worldwide
    @State private var page: GameCenter.BoardPage?
    @State private var loading = false
    private var record: PlayerRecord { ProgressStore.shared.record }

    enum Tab: String, CaseIterable { case leaderboard, statistics, achievements }

    init(tab: Tab? = nil) {
        _tab = State(initialValue: tab ?? Tab(rawValue: UserDefaults.standard.string(forKey: "recordsTab") ?? "") ?? .leaderboard)
        // The leaderboard opens where the last game against the computer belongs.
        switch ProgressStore.shared.record.lastGame?.mode {
        case let .computer(level)?: (_level, _opponents) = (State(initialValue: level), State(initialValue: 1))
        case let .computerGroup(level, opponents)?: (_level, _opponents) = (State(initialValue: level), State(initialValue: opponents))
        default: (_level, _opponents) = (State(initialValue: .normal), State(initialValue: 1))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(L("Records"), onBack: { withoutSliding { dismiss() } }) {
                // Game Center's own leaderboards and achievements, when signed in.
                if GameCenter.shared.isAuthenticated {
                    Button(L("Game Center")) { GameCenter.shared.showDashboard() }
                        .font(Theme.mono(14)).foregroundStyle(Theme.green)
                }
            }
                .padding(.horizontal, Theme.s(20))
                .padding(.vertical, Theme.s(10))
            VStack(spacing: Theme.s(12)) {
                Picker("", selection: $tab) {
                    Text(L("Best times")).tag(Tab.leaderboard)
                    Text(L("Statistics")).tag(Tab.statistics)
                    Text(L("Achievements")).tag(Tab.achievements)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: Theme.s(520))
                ScrollView {
                    switch tab {
                    case .leaderboard: leaderboard
                    case .statistics: statistics
                    case .achievements: achievements
                    }
                }
                .scrollIndicators(.visible)
                // Full screen on a wide Mac window: the tiles do not stretch over the whole width.
                .frame(maxWidth: Theme.s(900))
            }
            .padding(.horizontal, Theme.s(20))
            .padding(.top, Theme.s(8))
            .background(Theme.background)
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .pageSizedSheet()
    }

    // MARK: - Leaderboard

    private var leaderboard: some View {
        VStack(spacing: Theme.s(12)) {
            Picker(L("Difficulty"), selection: $level) {
                ForEach(Bot.Level.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: Theme.s(360))
            Picker(L("Opponents"), selection: $opponents) {
                ForEach(1...3, id: \.self) { n in Text(n == 1 ? L("1 opponent") : L("\(n) opponents")).tag(n) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: Theme.s(360))
            // Signed in to Game Center: its leaderboard (all the player's devices, everyone or friends);
            // otherwise, or when Game Center cannot be reached, the best times of this device.
            if GameCenter.shared.isAuthenticated {
                Picker("", selection: $scope) {
                    Text(L("Worldwide")).tag(GameCenter.BoardScope.worldwide)
                    Text(L("Friends")).tag(GameCenter.BoardScope.friends)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: Theme.s(360))
                if loading && page == nil {
                    ProgressView().tint(Theme.green).padding(.top, Theme.s(30))
                } else if let page {
                    gameCenterBoard(page)
                } else {
                    Text(L("Game Center cannot be reached right now. Your best times on this device:"))
                        .font(Theme.mono(14)).foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                    localBoard
                }
            } else {
                localBoard
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: BoardKey(level: level, opponents: opponents, scope: scope, signedIn: GameCenter.shared.isAuthenticated)) {
            guard GameCenter.shared.isAuthenticated else { page = nil; return }
            loading = true
            page = await GameCenter.shared.loadBoard(level: level, opponents: opponents, scope: scope)
            loading = false
        }
    }

    private struct BoardKey: Equatable {
        let level: Bot.Level, opponents: Int, scope: GameCenter.BoardScope, signedIn: Bool
    }

    private var noWinsText: String {
        opponents == 1 ? L("No wins against \(level.label) yet. The fastest wins appear here.")
            : L("No wins against \(level.label) with \(opponents) opponents yet. The fastest wins appear here.")
    }

    /// The best times of this device (without Game Center).
    @ViewBuilder private var localBoard: some View {
        let entries = record.leaderboard[PlayerRecord.leaderboardKey(level, opponents: opponents)] ?? []
        if entries.isEmpty {
            Text(noWinsText)
                .font(Theme.mono(14)).foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.top, Theme.s(30))
        } else {
            LazyVGrid(columns: cardColumns, spacing: Theme.s(12)) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    LeaderboardCard(place: index + 1, entry: entry)
                }
            }
        }
    }

    /// Game Center's best ten and, below them unless among them, the player's own place.
    @ViewBuilder private func gameCenterBoard(_ page: GameCenter.BoardPage) -> some View {
        if page.rows.isEmpty {
            Text(scope == .friends ? L("No times from your friends in Game Center yet.") : noWinsText)
                .font(Theme.mono(14)).foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.top, Theme.s(30))
        } else {
            if let mine = page.mine {
                Text(L("Your place: \(mine.rank) of \(page.total)"))
                    .font(Theme.mono(14)).foregroundStyle(Theme.gold)
            }
            LazyVGrid(columns: cardColumns, spacing: Theme.s(12)) {
                ForEach(page.rows) { row in
                    LeaderboardCard(place: row.rank, entry: row.entry, isMe: row.isMe)
                }
                if let mine = page.mine, !page.rows.contains(where: { $0.isMe }) {
                    LeaderboardCard(place: mine.rank, entry: mine.entry, isMe: true)
                }
            }
        }
    }

    /// Cards side by side where there is room (iPad), otherwise below each other.
    private var cardColumns: [GridItem] {
        [GridItem(.adaptive(minimum: Theme.s(300)), spacing: Theme.s(12))]
    }

    // MARK: - Statistics

    private var statistics: some View {
        let r = record
        func rate(_ wins: Int, _ games: Int) -> Double { games > 0 ? Double(wins) / Double(games) : 0 }
        func percent(_ wins: Int, _ games: Int) -> String { "\(Int((rate(wins, games) * 100).rounded())) %" }
        func won(_ wins: Int, _ games: Int) -> String {
            L("\(wins)/\(games) won") + (games > 0 ? " · " + percent(wins, games) : "")
        }
        // Ten cards of the same build in two columns: five full rows.
        let levelCards = Bot.Level.allCases.map { level -> StatCard in
            let wins = r.winsByLevel[level.rawValue] ?? 0, games = r.gamesByLevel[level.rawValue] ?? 0
            return StatCard(symbol: "cpu", title: "CPU · " + level.label, line: won(wins, games), share: rate(wins, games))
        }
        let cards: [StatCard] = [
            StatCard(symbol: "gamecontroller.fill", title: L("Games"), line: won(r.wins, r.games),
                     share: rate(r.wins, r.games)),
            StatCard(symbol: "flame.fill", title: L("Winning streak"),
                     line: L("best \(r.bestStreak) · now \(r.currentStreak)")),
        ] + levelCards + [
            StatCard(symbol: "person.2.fill", title: L("Multiplayer"), line: won(r.onlineWins, r.onlineGames),
                     share: rate(r.onlineWins, r.onlineGames)),
            StatCard(symbol: "arrow.up.right", title: L("Creeps sent"), line: Format.credits(r.creepsSent)),
            StatCard(symbol: "scope", title: L("Shot down"), line: Format.credits(r.creepsKilled)),
            StatCard(symbol: "building.2.fill", title: L("Towers built"), line: Format.credits(r.towersBuilt)),
            StatCard(symbol: "clock.fill", title: L("Time played"), line: Self.hours(r.totalTicks / 20)),
        ]
        return VStack(spacing: Theme.s(12)) {
            Text(L("Statistics of the games on this device")).font(Theme.mono(14)).foregroundStyle(.gray)
            if r.lastGame != nil {
                Button { withoutSliding { showLastGame = true } } label: {
                    Label(L("Evaluate the last game"), systemImage: "chart.xyaxis.line")
                }
                .buttonStyle(MenuButtonStyle(color: Theme.gold, minWidth: 0, fill: true))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.s(12)), count: 2),
                      spacing: Theme.s(12)) {
                ForEach(cards, id: \.title) { $0 }
            }
        }
        .fullScreenCover(isPresented: $showLastGame) {
            if let last = r.lastGame { GameReportView(summary: last, myName: L("You")) }
        }
    }

    // MARK: - Achievements

    /// Progress of an achievement: the larger of this device's and Game Center's (all the player's devices).
    private func value(_ achievement: Achievement) -> Int {
        max(achievement.progress(in: record), GameCenter.shared.achievementValues[achievement.id] ?? 0)
    }

    private var achievements: some View {
        let done = Achievement.all.reduce(0) { $0 + $1.tier(value: value($1)) }
        let total = Achievement.all.reduce(0) { $0 + $1.tiers.count }
        return VStack(alignment: .leading, spacing: Theme.s(10)) {
            Text(L("\(done) of \(total) achieved")).font(Theme.mono(14)).foregroundStyle(.gray)
            LazyVGrid(columns: cardColumns, spacing: Theme.s(12)) {
                ForEach(Achievement.all, id: \.id) { achievement in
                    AchievementCard(achievement: achievement, value: value(achievement))
                }
            }
        }
    }

    static func minutes(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func hours(_ seconds: Int) -> String {
        String(format: "%d:%02d h", seconds / 3600, seconds / 60 % 60)
    }
}

/// Frame of all cards on the records page.
private struct CardFrame: ViewModifier {
    var highlighted = true

    func body(content: Content) -> some View {
        content
            .padding(Theme.s(12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.s(8)).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: Theme.s(8))
                .stroke(highlighted ? Theme.dimGreen : Color.gray.opacity(0.3)))
    }
}

/// One entry of the leaderboard: place, name, time, lives, map and date.
private struct LeaderboardCard: View {
    let place: Int
    let entry: LeaderboardEntry
    /// The player's own entry in a Game Center list: framed in gold.
    var isMe = false

    var body: some View {
        let medal: Color = switch place {
        case 1: Theme.gold
        case 2: Color(white: 0.8)
        case 3: Color(red: 0.8, green: 0.5, blue: 0.25)
        default: Color.gray.opacity(0.5)
        }
        HStack(spacing: Theme.s(12)) {
            ZStack {
                Circle().fill(medal)
                Text("\(place)").font(Theme.pixel(11)).foregroundStyle(.black)
            }
            .frame(width: Theme.s(34), height: Theme.s(34))
            VStack(alignment: .leading, spacing: Theme.s(4)) {
                HStack {
                    Text(entry.name).font(Theme.pixel(10)).foregroundStyle(Theme.green).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(HallOfFameView.minutes(entry.seconds)).font(Theme.pixel(12)).foregroundStyle(Theme.text)
                }
                HStack(spacing: Theme.s(10)) {
                    // Game Center entries from other apps' versions may lack lives and map.
                    if entry.livesLeft >= 0 {
                        HStack(spacing: Theme.s(4)) {
                            Image(systemName: "heart.fill").foregroundStyle(Color.red.opacity(0.8))
                            Text("\(entry.livesLeft)")
                        }
                    }
                    if let map = GameMap.named(entry.mapID) {
                        Text(L(key: map.name))
                    }
                    Spacer(minLength: 0)
                    Text(entry.date.formatted(Date.FormatStyle(date: .numeric, time: .omitted)
                        .locale(AppLanguage.current.locale)))
                }
                .font(Theme.mono(14)).foregroundStyle(.gray)
            }
        }
        .modifier(CardFrame())
        .overlay(RoundedRectangle(cornerRadius: Theme.s(8)).stroke(Theme.gold, lineWidth: Theme.s(2)).opacity(isMe ? 1 : 0))
    }
}

/// One statistic: symbol, title, a big value, a line of detail and optionally a bar (e.g. share of wins).
/// One statistics card: title and one line of values, all in the same font; win rates also as a bar.
/// Every card keeps room for the bar, so all have the same height.
private struct StatCard: View {
    let symbol: String
    let title: String
    let line: String
    var share: Double? = nil

    var body: some View {
        HStack(alignment: .center, spacing: Theme.s(12)) {
            Image(systemName: symbol)
                .font(.system(size: Theme.s(20)))
                .foregroundStyle(Theme.green)
                .frame(width: Theme.s(34), height: Theme.s(34))
            VStack(alignment: .leading, spacing: Theme.s(4)) {
                Text(title).foregroundStyle(Theme.green).bold()
                Text(line).foregroundStyle(Theme.text)
                ProgressView(value: share ?? 0)
                    .tint(Theme.green)
                    .opacity(share == nil ? 0 : 1)
            }
            .font(Theme.mono(14))
            .lineLimit(1)
        }
        .modifier(CardFrame())
    }
}

/// One achievement: symbol, title, a medal per tier and the progress towards the next tier.
private struct AchievementCard: View {
    let achievement: Achievement
    let value: Int

    var body: some View {
        let tier = achievement.tier(value: value)
        let next = achievement.nextThreshold(value: value)
        HStack(alignment: .top, spacing: Theme.s(12)) {
            Image(systemName: achievement.symbol)
                .font(.system(size: Theme.s(22)))
                .foregroundStyle(achievement.color(tier: tier))
                .frame(width: Theme.s(34), height: Theme.s(34))
            VStack(alignment: .leading, spacing: Theme.s(4)) {
                HStack {
                    Text(achievement.title).font(Theme.pixel(10))
                        .foregroundStyle(tier > 0 ? Theme.green : Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    HStack(spacing: Theme.s(3)) {
                        ForEach(1...achievement.tiers.count, id: \.self) { t in
                            Circle().fill(achievement.color(tier: t <= tier ? t : 0))
                                .frame(width: Theme.s(9), height: Theme.s(9))
                        }
                    }
                }
                // Always two lines of text, a bar and a line below it, so all cards have the same height.
                Text(achievement.requirement(next ?? achievement.tiers.last!))
                    .font(Theme.mono(14)).foregroundStyle(.gray)
                    .lineLimit(2, reservesSpace: true)
                if let next {
                    ProgressView(value: Double(min(value, next)), total: Double(next))
                        .tint(Theme.green)
                    Text("\(Format.credits(min(value, next))) / \(Format.credits(next))")
                        .font(Theme.mono(14)).foregroundStyle(.gray)
                } else {
                    ProgressView(value: 1).tint(Theme.gold)
                    Text(L("Completed")).font(Theme.mono(14)).foregroundStyle(Theme.gold)
                }
            }
        }
        .modifier(CardFrame(highlighted: tier > 0))
    }
}
