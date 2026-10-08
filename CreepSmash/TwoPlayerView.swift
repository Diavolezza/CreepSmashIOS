import SwiftUI
import CreepSmashCore

/// Two-player game: quick game, host a game with a code, join with a code.
/// Which network the other player is found on is not visible here.
struct TwoPlayerView: View {
    let matchmaker: Matchmaker
    @Binding var mapID: String
    @Binding var playerName: String
    let onCancel: () -> Void
    @State private var code = ""
    @FocusState private var codeFocused: Bool

    /// Without a name an empty one is sent; the other device then shows "Opponent".
    private var name: String { playerName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: Theme.s(12)) {
                HStack {
                    Button(L("Back"), action: onCancel)
                        .font(Theme.mono(14, .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text(L("Two-player game"))
                        .font(Theme.pixel(13))
                        .foregroundStyle(Theme.green)
                    Spacer()
                    HStack(spacing: Theme.s(8)) {
                        Text(L("Name")).font(Theme.mono(13)).foregroundStyle(.gray)
                        TextField(L("Your name"), text: $playerName)
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.mono(14))
                            .frame(width: Theme.s(150))
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                    }
                }
                // Landscape: the three ways side by side; portrait (iPad): one below the other.
                GeometryReader { geo in
                    if geo.size.height > geo.size.width {
                        ScrollView {
                            VStack(spacing: Theme.s(12)) { panels }
                        }
                    } else {
                        HStack(alignment: .top, spacing: Theme.s(12)) { panels }
                    }
                }
            }
            .padding(.horizontal, Theme.s(24))
            .padding(.vertical, Theme.s(10))

            if matchmaker.state != .idle {
                statusOverlay
            }
        }
        .onAppear {
            if GameMap.named(mapID) == nil { mapID = GameMap.all[0].id }
        }
    }

    @ViewBuilder private var panels: some View {
        panel(L("Quick game"), L("Against someone who is searching right now. The map is drawn at random.")) {
            Spacer(minLength: 0)
            Button(L("Find opponent")) { matchmaker.quick(name: name) }
                .buttonStyle(MenuButtonStyle(minWidth: 0, fill: true))
        }
        panel(L("Host a game"), L("You choose the map and get a code for the other player.")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.s(8)) {
                    ForEach(GameMap.all, id: \.id) { map in
                        MapCard(map: map, selected: map.id == mapID, size: Theme.s(64))
                            .onTapGesture { mapID = map.id }
                    }
                }
            }
            Spacer(minLength: 0)
            Button(L("Host")) { matchmaker.host(mapID: mapID, name: name) }
                .buttonStyle(MenuButtonStyle(minWidth: 0, fill: true))
        }
        panel(L("Join"), L("Enter the code the other player sees.")) {
            TextField("CODE", text: $code)
                .font(Theme.pixel(22))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($codeFocused)
                .submitLabel(.join)
                .onSubmit(join)
                .padding(.vertical, Theme.s(6))
                .background(RoundedRectangle(cornerRadius: Theme.s(6)).stroke(Theme.dimGreen, lineWidth: Theme.s(1)))
                .onChange(of: code) { _, new in
                    let normalized = Matchmaker.normalize(new)
                    if normalized != new { code = normalized }
                }
            Spacer(minLength: 0)
            Button(L("Join"), action: join)
                .buttonStyle(MenuButtonStyle(minWidth: 0, fill: true))
                .disabled(code.count != Matchmaker.codeLength)
                .opacity(code.count == Matchmaker.codeLength ? 1 : 0.4)
        }
    }

    private func join() {
        guard code.count == Matchmaker.codeLength else { return }
        codeFocused = false
        matchmaker.join(code: code, name: name)
    }

    private func panel<Content: View>(_ title: String, _ text: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.s(10)) {
            Text(title).font(Theme.pixel(12)).foregroundStyle(Theme.green)
            Text(text).font(Theme.mono(14)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
        .padding(Theme.s(14))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.s(10)).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Theme.s(10)).stroke(Theme.dimGreen.opacity(0.6), lineWidth: Theme.s(1)))
    }

    @ViewBuilder private var statusOverlay: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: Theme.s(14)) {
                switch matchmaker.state {
                case .idle:
                    EmptyView()
                case .searchingQuick:
                    ProgressView().tint(Theme.green)
                    Text(L("Looking for an opponent …")).font(Theme.pixel(15)).foregroundStyle(Theme.green)
                case let .hosting(code):
                    Text(L("Your code")).font(Theme.mono(15)).foregroundStyle(Theme.text)
                    Text(code).font(Theme.pixel(40)).foregroundStyle(Theme.green).kerning(6)
                        .textSelection(.enabled)
                    HStack(spacing: Theme.s(8)) {
                        ProgressView().tint(Theme.green)
                        Text(L("Waiting for the other player …")).font(Theme.mono(14)).foregroundStyle(Theme.text)
                    }
                case let .joining(code):
                    ProgressView().tint(Theme.green)
                    Text(L("Looking for game \(code) …")).font(Theme.pixel(15)).foregroundStyle(Theme.green)
                case .connecting:
                    ProgressView().tint(Theme.green)
                    Text(L("Connecting …")).font(Theme.pixel(15)).foregroundStyle(Theme.green)
                case let .failed(message):
                    Text(L("That didn't work")).font(Theme.pixel(15)).foregroundStyle(Theme.warning)
                    Text(message).font(Theme.mono(14)).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center).frame(maxWidth: Theme.s(440))
                }
                if !matchmaker.detail.isEmpty {
                    Text(matchmaker.detail).font(Theme.mono(11)).foregroundStyle(.gray)
                        .multilineTextAlignment(.center).frame(maxWidth: Theme.s(440))
                }
                Button(isFailed ? "OK" : L("Cancel")) { matchmaker.cancel() }
                    .buttonStyle(MenuButtonStyle(color: Theme.text, minWidth: 160))
                    .padding(.top, Theme.s(6))
            }
            .padding(Theme.s(28))
            .background(RoundedRectangle(cornerRadius: Theme.s(12)).fill(Color.black.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: Theme.s(12)).stroke(Theme.dimGreen, lineWidth: Theme.s(1)))
        }
    }

    private var isFailed: Bool {
        if case .failed = matchmaker.state { return true }
        return false
    }
}
