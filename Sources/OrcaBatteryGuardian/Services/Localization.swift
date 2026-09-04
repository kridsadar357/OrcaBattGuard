import CoreText
import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case thai = "th"

    public var id: String { rawValue }

    public var selectionTitle: String {
        switch self {
        case .english: "English"
        case .thai: "ไทย"
        }
    }

    public var locale: Locale { Locale(identifier: rawValue) }

    public static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("th") == true ? .thai : .english
    }
}

public enum L10n {
    public static func string(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        string(key, language: language, arguments: arguments)
    }

    public static func string(_ key: String, language: AppLanguage, arguments: [CVarArg]) -> String {
        let value = localizationBundle(for: language).localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return value }
        return String(format: value, locale: language.locale, arguments: arguments)
    }

    private static func localizationBundle(for language: AppLanguage) -> Bundle {
        guard let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .module }
        return bundle
    }
}

public extension ChargeControlResult {
    func localized(language: AppLanguage) -> ChargeControlResult {
        guard language != .english else { return self }
        var value = self
        value.backendName = L10n.string(backendName, language: language)
        if isHardwareControlAvailable, verifiedAt != nil {
            if isLimitEnabled == true, let lowerLimit, let upperLimit {
                value.message = L10n.string(
                    "Verified charge limits: %d-%d%%. Hardware charging may take time to reflect the policy.",
                    language: language,
                    lowerLimit,
                    upperLimit
                )
            } else if isLimitEnabled == false {
                value.message = L10n.string("Verified: the charge limit is disabled. macOS manages charging.", language: language)
            }
        } else if message.hasPrefix("The charge controller could not complete ") {
            value.message = L10n.string(
                "The charge controller could not complete the command. Check that batt is running and accessible.",
                language: language
            )
        } else {
            value.message = L10n.string(message, language: language)
        }
        return value
    }
}

public enum BundledFontRegistrar {
    public static func registerSarabun() {
        for name in ["Sarabun-Regular", "Sarabun-Medium", "Sarabun-SemiBold", "Sarabun-Bold"] {
            let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.module.url(forResource: name, withExtension: "ttf")
            if let url { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }
}
