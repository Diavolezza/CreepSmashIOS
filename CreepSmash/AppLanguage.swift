import SwiftUI

/// Language of the app: English or German, switched with the flag on the start screen.
/// The texts live in `Localizable.xcstrings` (source language English, translation German).
enum AppLanguage: String, CaseIterable {
    case en, de

    static let storageKey = "language"

    /// The chosen language; without a choice the device language decides (German or else English).
    static var current: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: storageKey), let language = AppLanguage(rawValue: raw) {
            return language
        }
        return Locale.preferredLanguages.first?.hasPrefix("de") == true ? .de : .en
    }

    var other: AppLanguage { self == .de ? .en : .de }

    var flag: String { self == .de ? "🇩🇪" : "🇬🇧" }

    var locale: Locale { Locale(identifier: self == .de ? "de_DE" : "en_US") }

    /// Bundle with the texts of this language.
    var bundle: Bundle {
        if let cached = Self.bundles[self] { return cached }
        let bundle = Bundle.main.path(forResource: rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        Self.bundles[self] = bundle
        return bundle
    }

    nonisolated(unsafe) private static var bundles: [AppLanguage: Bundle] = [:]
}

/// Text in the current app language. Interpolations become format placeholders (%@, %lld).
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: AppLanguage.current.bundle, locale: AppLanguage.current.locale)
}

/// Text in the current app language for a key that is only known at runtime (e.g. map names).
func L(key: String) -> String {
    AppLanguage.current.bundle.localizedString(forKey: key, value: key, table: nil)
}
