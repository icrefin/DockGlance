import Foundation

/// Snapshot of the appearance settings (`AppSettings`).
struct AppearanceState: Codable, Equatable {
    /// Gap applied to profiles saved before `bottomGap` existed; mirrors
    /// `AppSettings.defaultBottomGap` (kept here because `AppSettings` is
    /// main-actor-isolated and this struct's Codable inits are not).
    private static let legacyDefaultBottomGap: Double = 4

    var cardHeight: Double
    var backgroundOpacity: Double
    var textColorRGB: Int
    var backgroundColorRGB: Int
    var bottomGap: Double
    var language: Language
    var temperatureUnit: TemperatureUnit

    init(
        cardHeight: Double,
        backgroundOpacity: Double,
        textColorRGB: Int,
        backgroundColorRGB: Int,
        bottomGap: Double,
        language: Language,
        temperatureUnit: TemperatureUnit
    ) {
        self.cardHeight = cardHeight
        self.backgroundOpacity = backgroundOpacity
        self.textColorRGB = textColorRGB
        self.backgroundColorRGB = backgroundColorRGB
        self.bottomGap = bottomGap
        self.language = language
        self.temperatureUnit = temperatureUnit
    }

    /// Decodes profiles saved before `bottomGap`/`language` existed (they
    /// default to the current defaults instead of failing the whole decode).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cardHeight = try container.decode(Double.self, forKey: .cardHeight)
        backgroundOpacity = try container.decode(Double.self, forKey: .backgroundOpacity)
        textColorRGB = try container.decode(Int.self, forKey: .textColorRGB)
        backgroundColorRGB = try container.decode(Int.self, forKey: .backgroundColorRGB)
        bottomGap =
            try container.decodeIfPresent(Double.self, forKey: .bottomGap)
            ?? Self.legacyDefaultBottomGap
        language =
            try container.decodeIfPresent(Language.self, forKey: .language)
            ?? .english
        temperatureUnit =
            try container.decodeIfPresent(
                TemperatureUnit.self, forKey: .temperatureUnit
            ) ?? .celsius
    }
}

/// Snapshot of the layout settings (`CardSettings`).
struct LayoutState: Codable, Equatable {
    /// Per-card visibility keyed by `CardKind.rawValue`.
    var visibility: [String: Bool]
    /// Display order as `CardKind.rawValue`s.
    var order: [String]
    /// Per-card side ("left"/"right") keyed by `CardKind.rawValue`.
    var side: [String: String]
}

/// A named snapshot of the current settings. Names are unique, so the name
/// doubles as the profile's identity.
struct Profile: Codable, Equatable, Identifiable {
    var name: String
    var appearance: AppearanceState
    var layout: LayoutState
    /// Display configuration the profile was saved on (nil for profiles
    /// saved before this field existed).
    var displayMode: DisplayMode?

    var id: String { name }

    init(
        name: String,
        appearance: AppearanceState,
        layout: LayoutState,
        displayMode: DisplayMode? = nil
    ) {
        self.name = name
        self.appearance = appearance
        self.layout = layout
        self.displayMode = displayMode
    }

    /// Decodes profiles saved before `displayMode` existed (it defaults to
    /// nil instead of failing the whole decode).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        appearance = try container.decode(AppearanceState.self, forKey: .appearance)
        layout = try container.decode(LayoutState.self, forKey: .layout)
        displayMode = try container.decodeIfPresent(DisplayMode.self, forKey: .displayMode)
    }
}