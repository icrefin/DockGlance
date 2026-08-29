import AppKit
import Foundation
import Observation
import SwiftUI

/// Display unit for temperatures across cards and pop-ups.
enum TemperatureUnit: String, CaseIterable, Identifiable, Codable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    /// Picker label ("°C" / "°F").
    var symbol: String {
        self == .celsius ? "°C" : "°F"
    }
}

/// User-facing appearance settings: card height, card background opacity and
/// the foreground text color. Persisted in `UserDefaults`.
@MainActor
@Observable
final class AppSettings {
    private static let heightKey = "cardHeight"
    private static let opacityKey = "backgroundOpacity"
    private static let textColorKey = "textColorRGB"
    private static let bgColorKey = "backgroundColorRGB"
    private static let bottomGapKey = "cardBottomGap"
    private static let languageKey = "language"
    private static let temperatureUnitKey = "temperatureUnit"

    static let defaultCardHeight: Double = 46
    static let defaultOpacity: Double = 0.65
    static let defaultTextColorRGB: Int = 0xFFFFFF
    static let defaultBackgroundColorRGB: Int = 0x000000
    static let defaultBottomGap: Double = 4
    static let maxBottomGap: Double = 100

    /// The card height in points. Width, icons and text scale to keep the
    /// card's aspect ratio.
    var cardHeight: Double { didSet { persistHeight() } }
    /// Distance in points between the bottom of the cards and the bottom of
    /// the screen.
    var bottomGap: Double { didSet { persistBottomGap() } }
    /// Card background opacity, 0...1.
    var backgroundOpacity: Double { didSet { persistOpacity() } }
    /// Foreground text color as 0xRRGGBB.
    var textColorRGB: Int { didSet { persistTextColor() } }
    /// Card background color as 0xRRGGBB.
    var backgroundColorRGB: Int { didSet { persistBackgroundColor() } }
    /// UI language (widget labels, pop-ups, settings).
    var language: Language { didSet { persistLanguage() } }
    /// Unit temperatures are displayed in (default Celsius).
    var temperatureUnit: TemperatureUnit { didSet { persistTemperatureUnit() } }

    /// The text color applied to card value and detail text.
    var textColor: Color {
        Color(rgbHex: textColorRGB)
    }

    /// The card background color.
    var backgroundColor: Color {
        Color(rgbHex: backgroundColorRGB)
    }

    init() {
        let defaults = UserDefaults.standard
        cardHeight = defaults.object(forKey: Self.heightKey) as? Double ?? Self.defaultCardHeight
        let loaded = defaults.object(forKey: Self.opacityKey) as? Double ?? Self.defaultOpacity
        backgroundOpacity = min(max(loaded, 0), 1)
        textColorRGB = defaults.object(forKey: Self.textColorKey) as? Int ?? Self.defaultTextColorRGB
        backgroundColorRGB = defaults.object(forKey: Self.bgColorKey) as? Int ?? Self.defaultBackgroundColorRGB
        let gap = defaults.object(forKey: Self.bottomGapKey) as? Double ?? Self.defaultBottomGap
        bottomGap = min(max(gap, 0), Self.maxBottomGap)
        let languageRaw = defaults.string(forKey: Self.languageKey) ?? ""
        language = Language(rawValue: languageRaw) ?? .english
        let unitRaw = defaults.string(forKey: Self.temperatureUnitKey) ?? ""
        temperatureUnit = TemperatureUnit(rawValue: unitRaw) ?? .celsius
    }

    /// A temperature rendered in the chosen unit, e.g. "78°" (or "78.3°"
    /// with `decimals: 1`). Fixed-precision numeric formatting only.
    func degrees(_ celsius: Double, decimals: Int = 0) -> String {
        let value = temperatureUnit == .celsius
            ? celsius
            : celsius * 9 / 5 + 32
        return String(format: "%.\(decimals)f°", value)
    }

    /// A localized UI string for the current language.
    func localized(_ key: String) -> String {
        L10n.localized(key, language)
    }

    /// Captures the current appearance for a profile.
    func snapshot() -> AppearanceState {
        AppearanceState(
            cardHeight: cardHeight,
            backgroundOpacity: backgroundOpacity,
            textColorRGB: textColorRGB,
            backgroundColorRGB: backgroundColorRGB,
            bottomGap: bottomGap,
            language: language,
            temperatureUnit: temperatureUnit
        )
    }

    /// Restores appearance values saved in a profile. Each `didSet` persists
    /// the value like any manual edit.
    func restore(_ appearance: AppearanceState) {
        cardHeight = appearance.cardHeight
        backgroundOpacity = appearance.backgroundOpacity
        textColorRGB = appearance.textColorRGB
        backgroundColorRGB = appearance.backgroundColorRGB
        bottomGap = appearance.bottomGap
        language = appearance.language
        temperatureUnit = appearance.temperatureUnit
    }

    private func persistHeight() {
        UserDefaults.standard.set(cardHeight, forKey: Self.heightKey)
    }

    private func persistBackgroundColor() {
        UserDefaults.standard.set(backgroundColorRGB, forKey: Self.bgColorKey)
    }

    private func persistOpacity() {
        UserDefaults.standard.set(backgroundOpacity, forKey: Self.opacityKey)
    }

    private func persistTextColor() {
        UserDefaults.standard.set(textColorRGB, forKey: Self.textColorKey)
    }

    private func persistBottomGap() {
        UserDefaults.standard.set(bottomGap, forKey: Self.bottomGapKey)
    }

    private func persistLanguage() {
        UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
    }

    private func persistTemperatureUnit() {
        UserDefaults.standard.set(temperatureUnit.rawValue, forKey: Self.temperatureUnitKey)
    }
}

extension Color {
    /// 0xRRGGBB from the color's sRGB components, if available.
    var rgbHex: Int? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return (r << 16) | (g << 8) | b
    }

    init(rgbHex: Int) {
        let r = Double((rgbHex >> 16) & 0xFF) / 255
        let g = Double((rgbHex >> 8) & 0xFF) / 255
        let b = Double(rgbHex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}