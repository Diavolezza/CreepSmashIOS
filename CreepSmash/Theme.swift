import SwiftUI
import CreepSmashCore

/// Colors and fonts in the style of the original: black, green, monospace.
enum Theme {
    static let background = Color.black
    static let panel = Color(white: 0.08)
    static let green = Color(red: 0.2, green: 1.0, blue: 0.2)
    static let dimGreen = Color(red: 0.1, green: 0.55, blue: 0.1)
    static let text = Color(white: 0.92)
    static let warning = Color(red: 1.0, green: 0.3, blue: 0.25)
    static let gold = Color(red: 1.0, green: 0.85, blue: 0.2)

    /// Retro terminal font (VT323) for all running text and numbers. `size` is given on the scale of the
    /// system font; VT323 is narrower and smaller, so it is drawn larger. The weight is ignored (one weight only).
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular, scaled: Bool = true) -> Font {
        .custom("VT323-Regular", fixedSize: (size * 1.4 * (scaled ? scale : 1)).rounded())
    }

    /// Arcade pixel font (Press Start 2P, as in the logo subtitle) for titles and buttons.
    static func pixel(_ size: CGFloat) -> Font {
        .custom("PressStart2P-Regular", fixedSize: (size * scale).rounded())
    }

    /// Size factor for text and controls: 1 on the iPhone, larger on the iPad so that the much bigger
    /// screen is used and everything stays easy to read. Set by `RootView` from the window size.
    nonisolated(unsafe) static var scale: CGFloat = 1

    /// Factor for a window of this size: from the shorter side, 1 up to about 520 pt, at most 1.7.
    static func scale(for size: CGSize) -> CGFloat {
        let factor = min(size.width, size.height) / 520
        return (min(1.7, max(1, factor)) * 10).rounded() / 10
    }

    /// A length scaled like the text (paddings, spacings, fixed control sizes).
    static func s(_ value: CGFloat) -> CGFloat { value * scale }
}

enum Format {
    /// 1234567 -> "1.234.567" (German) or "1,234,567" (English)
    static func credits(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic).locale(AppLanguage.current.locale))
    }

    /// Shortest form for tight places: 980, 1,4k, 40,8k, 153k, 1,2M.
    static func compact(_ value: Int) -> String {
        switch abs(value) {
        case 1_000_000...: return trim(Double(value) / 1_000_000) + "M"
        case 100_000...: return "\(value / 1_000)k"
        case 1_000...: return trim(Double(value) / 1_000) + "k"
        default: return "\(value)"
        }
    }

    /// Full number up to 99.999, above that the compact form (tables with several players).
    static func table(_ value: Int) -> String {
        abs(value) < 100_000 ? credits(value) : compact(value)
    }

    /// 15000 -> "15k", 2500000 -> "2,5M" (German) or "2.5M" (English)
    static func short(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return trim(Double(value) / 1_000_000) + "M"
        case 10_000...: return trim(Double(value) / 1_000) + "k"
        default: return "\(value)"
        }
    }

    private static func trim(_ d: Double) -> String {
        d.formatted(.number.precision(.fractionLength(0...1)).locale(AppLanguage.current.locale))
    }
}

extension TargetStrategy {
    /// For the option buttons in the tower panel.
    var shortLabel: String {
        switch self {
        case .closest: L("Near")
        case .farthest: L("Far")
        case .fastest: L("Fast")
        case .strongest: L("Strong")
        case .weakest: L("Weak")
        }
    }

    var label: String {
        switch self {
        case .closest: L("Closest")
        case .farthest: L("Farthest")
        case .fastest: L("Fastest")
        case .strongest: L("Strongest")
        case .weakest: L("Weakest")
        }
    }
}

extension WeaponKind {
    var label: String {
        switch self {
        case .laser: "Laser"
        case .slower: L("Slow laser")
        case .splashLaser: L("Splash laser")
        case .slowerSplash: L("Slow splash")
        case .rocket: L("Rocket")
        }
    }
}

extension Bot.Level {
    var label: String {
        switch self {
        case .easy: L("Easy")
        case .normal: L("Normal")
        case .hard: L("Hard")
        }
    }
}

extension RejectReason {
    var message: String {
        switch self {
        case .notStarted: L("The game has not started yet")
        case .playerDead: L("You are out")
        case .notEnoughCredits: L("Not enough credits")
        case .cellNotBuildable: L("You can't build here")
        case .cellOccupied: L("There is already a tower here")
        case .unknownTower: L("Tower not found")
        case .towerBusy: L("The tower is busy")
        case .maxLevel: L("Highest level reached")
        case .noTarget: L("No opponent left")
        case .gameFinished: L("The game is over")
        }
    }
}

extension Handshake.Failure {
    var message: String {
        switch self {
        case .connectionLost: L("Connection lost")
        case .otherVersion: L("Your opponent has a different app version")
        case .unknownMap: L("Unknown map – please update the app")
        }
    }
}

extension View {
    /// On the iPad a sheet uses the larger page size (iOS 18 and later), so cards and texts have room.
    @ViewBuilder func pageSizedSheet() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.page)
        } else {
            self
        }
    }
}

/// Head of every page and window: "‹ Back" on the left, the title in the middle, optional content on the
/// right – the same on all pages. Esc closes the page (Mac, iPad with keyboard).
struct PageHeader<Trailing: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, onBack: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(Theme.pixel(13))
                .foregroundStyle(Theme.green)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, Theme.s(100))
            HStack {
                Button(action: onBack) {
                    HStack(spacing: Theme.s(4)) {
                        Image(systemName: "chevron.left").font(.system(size: Theme.s(13), weight: .bold))
                        Text(L("Back")).font(Theme.mono(14, .semibold))
                    }
                    .foregroundStyle(Theme.text)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                trailing()
            }
        }
        .frame(minHeight: Theme.s(30))
    }
}

extension PageHeader where Trailing == EmptyView {
    init(_ title: String, onBack: @escaping () -> Void) {
        self.init(title, onBack: onBack) { EmptyView() }
    }
}
