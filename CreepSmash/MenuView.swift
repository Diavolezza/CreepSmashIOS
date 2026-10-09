import SwiftUI
import CreepSmashCore

struct MenuView: View {
    @Binding var level: Bot.Level
    @Binding var mapID: String
    @Binding var playerName: String
    @Binding var showTwoPlayer: Bool
    let matchmaker: Matchmaker
    let onStart: () -> Void
    let onResume: () -> Void
    /// An interrupted game against the computer that can be continued.
    @State private var savedGame = SavedGameStore.load()
    @State private var showRules = false
    @State private var showSetup = false
    @State private var showOptions = false
    @State private var showRecords = false
    @State private var showCredits = false
    @AppStorage(AppLanguage.storageKey) private var languageRaw = ""
    @State private var logoPulse = false

    var body: some View {
        ZStack {
            RetroBackground()
            VStack(spacing: Theme.s(0)) {
                Spacer(minLength: 8)
                Image("logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: Theme.s(720))
                    .scaleEffect(logoPulse ? 1.025 : 1)
                    .shadow(color: Theme.green.opacity(logoPulse ? 0.45 : 0.15), radius: 18)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: logoPulse)
                    .onAppear { logoPulse = true }
                    .accessibilityLabel(L("CreepSmash – multiplayer tower defense"))
                Spacer()
                // Both buttons share one width and never shrink their text, so the font size is the same.
                // Side by side where they fit, otherwise one above the other.
                ViewThatFits(in: .horizontal) {
                    VStack(spacing: Theme.s(16)) {
                        continueButton
                        HStack(spacing: Theme.s(24)) { mainButtons }
                    }
                    .frame(maxWidth: Theme.s(580))
                    VStack(spacing: Theme.s(16)) {
                        continueButton
                        mainButtons
                    }
                    .frame(maxWidth: Theme.s(340))
                }
                .padding(.bottom, Theme.s(28))
            }
            .padding(.horizontal, Theme.s(24))
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: Theme.s(10)) {
                cornerButton(L("Records"), action: { showRecords = true }) {
                    Image(systemName: "trophy.fill").foregroundStyle(Theme.gold)
                }
                cornerButton(L("How to play"), action: { showRules = true }) {
                    Image(systemName: "questionmark").foregroundStyle(Theme.text)
                }
                cornerButton(L("Credits"), action: { showCredits = true }) {
                    Image(systemName: "info").foregroundStyle(Theme.text)
                }
            }
            .padding(.top, Theme.s(12))
            .padding(.leading, Theme.s(20))
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: Theme.s(10)) {
                cornerButton(L("Options"), action: { showOptions = true }) {
                    Image(systemName: "gearshape.fill").foregroundStyle(Theme.text)
                }
                languageButton
            }
            .padding(.top, Theme.s(12))
            .padding(.trailing, Theme.s(20))
        }
        .sheet(isPresented: $showRecords) { HallOfFameView() }
        .sheet(isPresented: $showRules) { RulesView() }
        .sheet(isPresented: $showCredits) { CreditsView() }
        // Launch arguments "-credits" and "-setup" open those pages (screenshots).
        .onAppear {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-credits") { showCredits = true }
            if arguments.contains("-setup") { showSetup = true }
        }
        .overlay(alignment: .bottomTrailing) {
            Text("v" + AppVersion.text)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.dimGreen)
                .padding(.trailing, Theme.s(16))
                .padding(.bottom, Theme.s(6))
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showOptions) { OptionsView() }
        .fullScreenCover(isPresented: $showTwoPlayer, onDismiss: { matchmaker.cancel() }) {
            TwoPlayerView(matchmaker: matchmaker, mapID: $mapID, playerName: $playerName,
                          onCancel: { showTwoPlayer = false })
        }
        .fullScreenCover(isPresented: $showSetup) {
            SetupView(level: $level, mapID: $mapID, playerName: $playerName,
                      onStart: { showSetup = false; onStart() },
                      onCancel: { showSetup = false })
        }
    }
}

extension MenuView {
    /// Continue the interrupted game (only if there is one), with map, difficulty and game time below.
    @ViewBuilder private var continueButton: some View {
        if let savedGame {
            VStack(spacing: Theme.s(6)) {
                Button(L("Continue game"), action: onResume)
                    .buttonStyle(MenuButtonStyle(color: Theme.gold, minWidth: 0, fill: true, shrinks: false))
                Text(verbatim: savedGame.caption)
                    .font(Theme.mono(13))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    /// The two large buttons of the start screen.
    @ViewBuilder private var mainButtons: some View {
        Button(L("Vs. computer")) { showSetup = true }
            .buttonStyle(MenuButtonStyle(minWidth: 0, fill: true, shrinks: false))
        Button(L("Two players")) { showTwoPlayer = true }
            .buttonStyle(MenuButtonStyle(minWidth: 0, fill: true, shrinks: false))
    }

    /// Small square button in a corner of the start screen: records, how to play, options, language.
    private func cornerButton(_ label: String, action: @escaping () -> Void,
                              @ViewBuilder icon: () -> some View) -> some View {
        Button(action: action) {
            icon()
                .font(.system(size: Theme.s(20), weight: .bold))
                .frame(width: Theme.s(28), height: Theme.s(28))
                .padding(Theme.s(6))
                .background(RoundedRectangle(cornerRadius: Theme.s(6)).fill(Color.black))
                .overlay(RoundedRectangle(cornerRadius: Theme.s(6)).stroke(Theme.dimGreen, lineWidth: Theme.s(2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Flag: shows the current language, a tap switches to the other one.
    private var languageButton: some View {
        let language = AppLanguage.current
        return cornerButton(language == .de ? "Sprache: Deutsch – auf Englisch umschalten"
                                            : "Language: English – switch to German",
                            action: { languageRaw = language.other.rawValue }) {
            Text(language.flag).font(.system(size: Theme.s(24)))
        }
    }
}

struct SetupView: View {
    @Binding var level: Bot.Level
    @Binding var mapID: String
    @Binding var playerName: String
    /// Number of computer opponents (1–3).
    @AppStorage("opponents") private var opponents = 1
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        GeometryReader { geometry in
            content(landscape: geometry.size.width > geometry.size.height)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            if GameMap.named(mapID) == nil { mapID = GameMap.all[0].id }
        }
    }

    private func content(landscape: Bool) -> some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: Theme.s(14)) {
                HStack {
                    Button(L("Back"), action: onCancel)
                        .font(Theme.mono(14, .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text(L("New game vs. computer"))
                        .font(Theme.pixel(13))
                        .foregroundStyle(Theme.green)
                    Spacer()
                    Text(L("Back")).font(Theme.mono(14)).hidden()
                }
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.s(14)) {
                            ForEach(GameMap.all, id: \.id) { map in
                                MapCard(map: map, selected: map.id == mapID, size: Theme.s(170))
                                    .id(map.id)
                                    .onTapGesture { mapID = map.id }
                            }
                        }
                        .padding(.horizontal, Theme.s(4))
                    }
                    .onAppear { proxy.scrollTo(mapID, anchor: .center) }
                }
                // Name, opponents and difficulty one below the other; the start button beside them
                // in landscape, below them in portrait (iPad), so nothing gets cut off.
                let layout = landscape ? AnyLayout(HStackLayout(spacing: Theme.s(60))) : AnyLayout(VStackLayout(spacing: Theme.s(16)))
                layout {
                    choices
                    startButton
                }
            }
            .padding(.horizontal, Theme.s(24))
            .padding(.vertical, Theme.s(10))
        }
    }

    /// Name, opponents and difficulty: labels in one column, the fields equally wide.
    private var choices: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.s(10), verticalSpacing: Theme.s(8)) {
            GridRow {
                Text(L("Name")).font(Theme.mono(13)).foregroundStyle(.gray).fixedSize()
                TextField(L("Your name"), text: $playerName)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono(14))
                    .frame(width: Theme.s(220))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
            GridRow {
                Text(L("Opponents")).font(Theme.mono(13)).foregroundStyle(.gray).fixedSize()
                Picker(L("Opponents"), selection: $opponents) {
                    ForEach(1...3, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: Theme.s(220))
            }
            GridRow {
                Text(L("Difficulty")).font(Theme.mono(13)).foregroundStyle(.gray).fixedSize()
                Picker(L("Difficulty"), selection: $level) {
                    ForEach(Bot.Level.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: Theme.s(220))
            }
        }
    }

    private var startButton: some View {
        Button(L("Start game"), action: onStart)
            .buttonStyle(MenuButtonStyle(minWidth: Theme.s(170), shrinks: false))
    }
}

struct MapCard: View {
    let map: GameMap
    let selected: Bool
    var size: CGFloat = 170

    var body: some View {
        VStack(spacing: Theme.s(4)) {
            Image(String(map.imageName.split(separator: ".").first ?? ""))
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: Theme.s(6)))
                .overlay(RoundedRectangle(cornerRadius: Theme.s(6))
                    .stroke(selected ? Theme.green : Color.gray.opacity(0.4), lineWidth: selected ? 3 : 1))
            Text(L(key: map.name))
                .font(Theme.mono(13, .bold))
                .foregroundStyle(selected ? Theme.green : Theme.text)
            if size >= 120 {
                // Two lines in every card (the second may be empty), so all cards are equally high.
                Text(lengthLabel)
                    .font(Theme.mono(10))
                    .foregroundStyle(.gray)
                Text(verbatim: map.features.isEmpty ? " " : map.features.map(\.label).joined(separator: " · "))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.gold)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var lengthLabel: String {
        switch map.walkLength {
        case ..<45: L("short path")
        case ..<75: L("medium path")
        default: L("long path")
        }
    }
}

extension MapFeature {
    var label: String {
        switch self {
        case .fastLanes: L("fast lanes")
        case .jumps: L("jumps")
        case .loops: L("loops")
        case .uTurns: L("U-turns")
        case .diagonals: L("diagonals")
        }
    }
}

struct RulesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s(14)) {
                    section(L("Goal"), L("Each player has 20 lives. The last player with lives left wins."))
                    section(L("Money"), L("You start with 500 credits. Every 15 seconds your income is added to your credits (200 at the start)."))
                    section(L("Attack"), L("Send creeps to your opponent's board. Every creep you send raises your income for good. If a creep reaches the end of the path, your opponent loses a life – and the creep starts again from the beginning."))
                    section(L("Defend"), L("Build towers next to the path. Creeps you shoot down pay a bounty. Towers can be upgraded and sold for 75 % of their price. Building and upgrading take 2 seconds."))
                    section(L("Maps"), L("Some maps have special sections. On fast lanes (yellow arrows, one per multiple of the speed) creeps run two to four times as fast. Through portals they jump across the board. Where a path runs laps, crosses itself or turns back at a dead end, towers there get the creeps more than once."))
                    section(L("Controls"), L("Your board is on the left, your opponent's on the right. Pick a tower on the left and tap a free cell. Tap a built tower to upgrade it, sell it or change its target. Tap a creep on the right to send one; hold it to keep sending until you let go or your credits run out."))
                    Divider().overlay(Theme.dimGreen)
                    Text(L("Towers")).font(Theme.pixel(14)).foregroundStyle(Theme.green)
                    LexiconTowers()
                    Divider().overlay(Theme.dimGreen)
                    Text("Creeps").font(Theme.pixel(14)).foregroundStyle(Theme.green)
                    LexiconCreeps()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .background(Theme.background)
            .navigationTitle(L("How to play"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .pageSizedSheet()
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.s(4)) {
            Text(title).font(Theme.pixel(12)).foregroundStyle(Theme.green)
            Text(text).font(Theme.mono(15)).foregroundStyle(Theme.text)
        }
    }
}
