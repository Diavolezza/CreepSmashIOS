import SwiftUI
import UIKit
import CreepSmashCore

@main
struct CreepSmashApp: App {
    init() {
        // Retro fonts also in the system bars and controls (navigation bar of the sheets, segmented picker).
        // Sheet titles at least as large as the text below them: large on the iPad, and on an iPhone with a
        // large display that is regular in both directions (inner display of the iPhone Duo).
        let iPad = UIDevice.current.userInterfaceIdiom == .pad
        Self.styleBars(UINavigationBar.appearance(), UISegmentedControl.appearance(), large: iPad)
        if !iPad {
            let regular = UITraitCollection { traits in
                traits.horizontalSizeClass = .regular
                traits.verticalSizeClass = .regular
            }
            Self.styleBars(UINavigationBar.appearance(for: regular), UISegmentedControl.appearance(for: regular),
                           large: true)
        }
        SoundManager.shared.prepareSession()
        MapThumbnails.preload()
    }

    /// Navigation bar and segmented control in the retro fonts, in the small (iPhone) or large (iPad) size.
    private static func styleBars(_ navigation: UINavigationBar, _ segmented: UISegmentedControl, large: Bool) {
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = .black
        if let pixel = UIFont(name: "PressStart2P-Regular", size: large ? 22 : 15) {
            bar.titleTextAttributes = [.font: pixel, .foregroundColor: UIColor(Theme.green)]
        }
        if let mono = UIFont(name: "VT323-Regular", size: large ? 30 : 22) {
            let item = UIBarButtonItemAppearance()
            item.normal.titleTextAttributes = [.font: mono]
            bar.buttonAppearance = item
            bar.doneButtonAppearance = item
            segmented.setTitleTextAttributes([.font: mono], for: .normal)
        }
        navigation.standardAppearance = bar
        navigation.scrollEdgeAppearance = bar
        navigation.compactAppearance = bar
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.green)
        }
    }
}

struct RootView: View {
    @State private var controller: GameController?
    @State private var matchmaker = Matchmaker()
    @State private var showMultiplayer = false
    @State private var showRecords = false
    @State private var showReport = false
    @State private var handledLaunchArguments = false
    /// Continuing a saved game: share of it replayed so far (nil = not loading).
    @State private var resumeProgress: Double?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("botLevel") private var level: Bot.Level = .normal
    @AppStorage("map") private var mapID = GameMap.blue.id
    @AppStorage("playerName") private var playerName = ""
    /// Number of computer opponents (1–3); also launch argument "-opponents 3".
    @AppStorage("opponents") private var opponents = 1
    /// Chosen language (empty = device language). Changing it rebuilds all views in the new language.
    @AppStorage(AppLanguage.storageKey) private var languageRaw = ""

    var body: some View {
        GeometryReader { geo in
            // Text and control sizes follow the window (larger on the iPad); a change rebuilds the views.
            let scale = Theme.scale(for: geo.size)
            let _ = { Theme.scale = scale }()
            content
                .id("\(languageRaw)-\(scale)")
        }
        .background(Theme.background.ignoresSafeArea())
        // Background music only while the app is in front.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { MusicPlayer.shared.update() } else if phase == .background { MusicPlayer.shared.stop() }
        }
    }

    @ViewBuilder private var content: some View {
        Group {
            if let controller {
                GameScreen(controller: controller,
                           onRestart: { startGame() },
                           onExit: { self.controller = nil })
                    .id(ObjectIdentifier(controller))
            } else {
                MenuView(level: $level, mapID: $mapID, playerName: $playerName, showMultiplayer: $showMultiplayer,
                         matchmaker: matchmaker, onStart: { startGame() }, onResume: { resumeGame() })
                    .overlay { if let resumeProgress { loadingOverlay(resumeProgress) } }
            }
        }
        .environment(\.locale, AppLanguage.current.locale)
        .fullScreenCover(isPresented: $showRecords) { HallOfFameView() }
        .fullScreenCover(isPresented: $showReport) {
            if let last = ProgressStore.shared.record.lastGame { GameReportView(summary: last, myName: displayName) }
        }
        .onAppear {
            matchmaker.onMatch = { match, session in startOnline(match, gameCenter: session) }
            // A round found through Game Center: its lobby runs like one nearby.
            GameCenter.shared.onMatch = { match in
                withoutSliding { showMultiplayer = true }
                matchmaker.gameCenter(GameCenterSession(match: match), name: networkName)
            }
            // onAppear fires again after a language switch; launch arguments count only once.
            guard !handledLaunchArguments else { return }
            handledLaunchArguments = true
            GameCenter.shared.authenticate()
            handleLaunchArguments()
        }
    }

    private var displayName: String {
        let name = PlayerName.current(typed: playerName)
        return name.isEmpty ? L("You") : name
    }

    /// Name sent to the other device (the Game Center name when signed in); empty without a name, it then
    /// shows "Opponent".
    private var networkName: String { PlayerName.current(typed: playerName) }

    /// Continues the saved game: replays it in the background (a few seconds for a long game), then shows it paused.
    private func resumeGame() {
        guard resumeProgress == nil, let saved = SavedGameStore.load() else { return }
        let mode = saved.mode
        resumeProgress = 0
        Task.detached(priority: .userInitiated) {
            var stats = GameStats(me: 0, mode: mode)
            var reported = 0
            let match = LocalMatch(restoring: saved) { game in
                stats.observe(game)
                if game.tick - reported >= 400 {
                    reported = game.tick
                    let fraction = Double(game.tick) / Double(max(1, saved.tick))
                    Task { @MainActor in if resumeProgress != nil { resumeProgress = fraction } }
                }
            }
            let collected = stats
            await MainActor.run {
                resumeProgress = nil
                guard let match else { SavedGameStore.clear(); return }
                let controller = GameController(match: match, mode: mode, stats: collected)
                controller.isPaused = true
                self.controller = controller
            }
        }
    }

    private func loadingOverlay(_ progress: Double) -> some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: Theme.s(12)) {
                Text(L("Loading game …")).font(Theme.pixel(14)).foregroundStyle(Theme.green)
                ProgressView(value: progress)
                    .tint(Theme.green)
                    .frame(width: Theme.s(260))
            }
        }
    }

    private func startGame(demo: Bool = false) {
        controller?.stop()
        // A new game against the computer replaces an interrupted one.
        if !demo { SavedGameStore.clear() }
        let map = GameMap.named(mapID) ?? .blue
        let count = min(3, max(1, opponents))
        let names = count == 1 ? ["Computer · " + level.label] : (1...count).map { "CPU\($0)" }
        let match = LocalMatch(map: map, playerName: displayName, opponents: Array(repeating: level, count: count),
                               opponentNames: names,
                               seed: UInt64.random(in: 1...UInt64.max))
        // Demo games (autopilot) do not count for statistics and achievements.
        let mode: GameMode = count == 1 ? .computer(level) : .computerGroup(level, opponents: count)
        let controller = GameController(match: match, mode: demo ? nil : mode)
        if demo {
            controller.autopilot = Bot(player: match.localPlayer, level: .normal, map: map)
            controller.fastForward(ticks: 3_600)
            // "-placing": show the build preview of the slow tower over a cell (screenshots).
            if ProcessInfo.processInfo.arguments.contains("-placing") {
                controller.selection = .placing(.slow)
                controller.aimCell = GridPoint(x: 9, y: 11)
            }
            // "-selectTower": open the panel of the first tower (screenshots).
            if ProcessInfo.processInfo.arguments.contains("-selectTower"),
               let tower = controller.game.players[match.localPlayer].towers.first {
                controller.selection = .tower(id: tower.id)
            }
        }
        self.controller = controller
    }

    private func startOnline(_ match: NetworkMatch, gameCenter: GameCenterSession? = nil) {
        withoutSliding { showMultiplayer = false }
        controller?.stop()
        let autopilot = ProcessInfo.processInfo.arguments.contains("-autopilot")
        let controller = GameController(match: match, mode: autopilot ? nil : .online)
        controller.gameCenter = gameCenter
        if autopilot {
            controller.autopilot = Bot(player: match.localPlayer, level: .normal, map: match.game.map)
        }
        self.controller = controller
        // Tests of the pause in the Simulator: "-pauseAfter 15" pauses after 15 s, "-resumeAfter 10" goes on 10 s later.
        let args = ProcessInfo.processInfo.arguments
        func seconds(_ flag: String) -> Double? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return Double(args[i + 1])
        }
        // Handover tests: "-quitAfter 30" leaves the game after 30 s, as with "Give up".
        if let quitAfter = seconds("-quitAfter") {
            DispatchQueue.main.asyncAfter(deadline: .now() + quitAfter) { [weak controller] in
                guard let controller, self.controller === controller else { return }
                controller.quit()
                self.controller = nil
            }
        }
        if let pauseAfter = seconds("-pauseAfter") {
            let resumeAfter = seconds("-resumeAfter")
            DispatchQueue.main.asyncAfter(deadline: .now() + pauseAfter) { [weak controller] in
                controller?.setPaused(true)
                if let resumeAfter {
                    DispatchQueue.main.asyncAfter(deadline: .now() + resumeAfter) { controller?.setPaused(false) }
                }
            }
        }
    }

    /// Launch arguments for screenshots and tests in the Simulator:
    /// -demo (game against the computer, fast-forwarded), -host CODE / -join CODE / -quick (network game), -multiplayer (multiplayer page), -autopilot,
    /// -startWhen N (the host starts its round as soon as N people are in it), -cpu LEVEL (the host's free seats get computers),
    /// -records (records page), -sampleProgress (adds made-up games to the records),
    /// -landscape (turns an iPad simulator to landscape), -report (evaluation of the last game), -map ID (map of the game),
    /// -play (normal game against the computer), -resume (continue the saved game).
    private func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-landscape") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
        }
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if args.contains("-sampleProgress") {
            // Screenshots of the records page: a few made-up games (simulator only).
            // The course of the last made-up game: income grows, lives drop towards the end.
            let course = (0...36).map { k in
                GameSample(tick: 100 + k * 300, myIncome: 200 + k * k * 9 + k * 40, opponentIncome: 200 + k * k * 8 + k * 25,
                           myLives: max(14, 20 - max(0, k - 26) / 2), opponentLives: max(0, 20 - max(0, k - 22) * 2),
                           myDamage: k * k * k * 40, opponentDamage: k * k * k * 33,
                           myHealthSent: k * k * k * 38, opponentHealthSent: k * k * k * 36,
                           players: [
                               PlayerSample(income: 200 + k * k * 9 + k * 40, lives: max(14, 20 - max(0, k - 26) / 2),
                                            damage: k * k * k * 40, healthSent: k * k * k * 38,
                                            arrived: k * k * k * 42, capacity: 5_000 + k * k * 450),
                               PlayerSample(income: 200 + k * k * 8 + k * 25, lives: max(0, 20 - max(0, k - 22) * 2),
                                            damage: k * k * k * 33, healthSent: k * k * k * 36,
                                            arrived: k * k * k * 40, capacity: 4_000 + k * k * 380),
                           ])
            }
            for i in 0..<14 {
                let level = Bot.Level.allCases[i % 3]
                let summary = GameSummary(mode: .computer(level), mapID: GameMap.all[i % GameMap.all.count].id,
                                          won: i % 4 != 3, durationTicks: (420 + i * 37) * 20, livesLeft: 20 - i % 7,
                                          livesLost: i % 7, maxIncome: 1_500 + i * 900, creepsSent: 60 + i * 9,
                                          creepsKilled: 80 + i * 13, towersBuilt: 9 + i, builtUltimate: i > 10,
                                          sentColossus: false, samples: i == 13 ? course : [],
                                          date: Date().addingTimeInterval(Double(-i) * 86_400),
                                          opponentName: "Computer · " + level.label,
                                          damageDealt: i == 13 ? 36 * 36 * 36 * 40 : nil,
                                          healthSent: i == 13 ? 36 * 36 * 36 * 38 : nil,
                                          playerNames: i == 13 ? [displayName, "Computer · " + level.label] : nil,
                                          me: i == 13 ? 0 : nil,
                                          towerValue: i == 13 ? 38_500 : nil,
                                          defense: i == 13 ? [
                                              DefenseRecord(healthArrived: 2_050_000, healthStopped: 1_930_000, towerSpent: 41_200,
                                                            earned: 410_000, zombieTowers: 0, zombieValue: 0, capacity: 5_400_000),
                                              DefenseRecord(healthArrived: 1_980_000, healthStopped: 1_610_000, towerSpent: 47_900,
                                                            earned: 380_000, zombieTowers: 0, zombieValue: 0, capacity: 2_900_000),
                                          ] : nil)
                _ = ProgressStore.shared.add(summary, playerName: displayName)
            }
        }
        if let id = value(after: "-map"), GameMap.named(id) != nil { mapID = id }
        if args.contains("-records") { showRecords = true }
        if args.contains("-report") { showReport = true }
        if args.contains("-demo") {
            startGame(demo: true)
        } else if args.contains("-play") {
            startGame()
        } else if args.contains("-resume") {
            resumeGame()
        } else if let code = value(after: "-host") {
            matchmaker.autoStartPeople = value(after: "-startWhen").flatMap(Int.init)
            matchmaker.autoStartComputers = value(after: "-cpu").flatMap(Bot.Level.init(rawValue:))
            matchmaker.host(mapID: mapID, name: networkName, code: Matchmaker.normalize(code))
        } else if let code = value(after: "-join") {
            matchmaker.join(code: code, name: networkName)
        } else if args.contains("-quick") {
            matchmaker.quick(name: networkName)
        }
        // Also together with -quick / -join / -host, to see the search or the lobby (screenshots).
        if args.contains("-multiplayer") { showMultiplayer = true }
        // Opens the page a few seconds after the start, like a tap on the button (animation tests).
        if let delay = value(after: "-multiplayerAfter").flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { withoutSliding { showMultiplayer = true } }
        }
    }
}
