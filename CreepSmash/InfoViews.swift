import SwiftUI
import CreepSmashCore

extension TowerKind {
    var summary: String {
        switch self {
        case .basic: L("Cheap laser, hits one target.")
        case .slow: L("Slows the target (not Ray, Shark, Phoenix); level 4 slows several.")
        case .splash: L("Laser that also hits creeps near the target.")
        case .rocket: L("Rocket with large area damage, launches slowly.")
        case .speed: L("Laser that fires very fast.")
        case .ultimate: L("Huge range and damage, fires rarely.")
        }
    }
}

extension CreepType {
    var speedLabel: String {
        switch stats.speed {
        case 101...: L("ultra fast")
        case 81...: L("very fast")
        case 71...: L("fast")
        case 66...: L("medium")
        case 61...: L("slow")
        case 56...: L("very slow")
        default: L("extremely slow")
        }
    }

    var specialLabel: String {
        if stats.slowImmune { return L("can't be slowed") }
        if stats.regeneration > 0 { return L("heals \(stats.regeneration * 20) health/s") }
        return ""
    }
}

extension TowerKind {
    /// Tooltip on the build button (pointer on Mac and iPad).
    var tooltip: String {
        let s = stats(level: 1), top = stats(level: maxLevel)
        return name + " – " + summary + "\n"
            + L("Damage \(Format.short(s.damage)) · range \(s.range) · every \(InfoFormat.seconds(ticks: s.reloadTicks))") + "\n"
            + L("Level \(maxLevel): damage \(Format.short(top.damage)) · range \(top.range)")
    }
}

extension CreepType {
    /// Tooltip on the send button (pointer on Mac and iPad).
    var tooltip: String {
        let s = stats
        let line = L("\(Format.short(s.health)) health · \(speedLabel) · +\(Format.short(s.income)) income")
        return s.name + (specialLabel.isEmpty ? "" : " – " + specialLabel) + "\n" + line
    }
}

enum InfoFormat {
    /// Duration of `ticks` in seconds with two decimals, e.g. "0,65 s" (German) or "0.65 s" (English).
    static func seconds(ticks: Int, rules: Rules = .standard) -> String {
        let value = Double(ticks * rules.tickMilliseconds) / 1000
        return value.formatted(.number.precision(.fractionLength(2)).locale(AppLanguage.current.locale)) + " s"
    }
}

/// All towers with their levels and stats (for the instructions).
struct LexiconTowers: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(TowerKind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind.name + " – " + kind.summary)
                        .font(Theme.mono(13, .bold)).foregroundStyle(Theme.green)
                    Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 4) {
                        GridRow {
                            Text("")
                            Text(L("Level")).gridColumnAlignment(.leading)
                            Text(L("Price")); Text(L("Damage")); Text(L("Range")); Text(L("Fires every"))
                            Text("Splash"); Text(L("Slows"))
                        }
                        .foregroundStyle(.gray)
                        ForEach(1...kind.maxLevel, id: \.self) { level in
                            let s = kind.stats(level: level)
                            GridRow {
                                Image(kind.imageName(level: level))
                                    .interpolation(.high).resizable().frame(width: 22, height: 22)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.black))
                                Text("\(level)").gridColumnAlignment(.leading)
                                Text(Format.credits(s.price))
                                Text(Format.credits(s.damage))
                                Text("\(s.range)")
                                Text(InfoFormat.seconds(ticks: s.reloadTicks))
                                Text(s.splashRadius > 0 ? "\(s.splashRadius)" : "–")
                                Text(s.slowPermille > 0 ? "\(s.slowPermille / 10) %" : "–")
                            }
                        }
                    }
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.text)
                }
            }
            Text(L("Selling returns 75 % of the prices paid. Building and upgrading take 2 seconds."))
                .font(Theme.mono(11)).foregroundStyle(.gray)
        }
    }

}

/// All creeps with their stats (for the instructions).
struct LexiconCreeps: View {
    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("")
                Text(L("Name")).gridColumnAlignment(.leading)
                Text(L("Price")); Text(L("Income")); Text(L("Health")); Text(L("Speed")); Text(L("Bounty"))
                Text(L("Special")).gridColumnAlignment(.leading)
            }
            .foregroundStyle(.gray)
            ForEach(CreepType.allCases, id: \.self) { type in
                let s = type.stats
                GridRow {
                    Image(type.imageName).interpolation(.high).resizable().frame(width: 22, height: 22)
                    Text(s.name).foregroundStyle(Theme.green)
                    Text(Format.credits(s.price)).foregroundStyle(Theme.gold)
                    Text("+" + Format.credits(s.income))
                    Text(Format.credits(s.health))
                    Text(type.speedLabel)
                    Text(Format.credits(s.bounty))
                    Text(type.specialLabel)
                }
            }
        }
        .font(Theme.mono(11))
        .foregroundStyle(Theme.text)
    }
}
