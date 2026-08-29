import SwiftUI

/// The settings form, bound live to `AppSettings` and `CardSettings` so the
/// cards update as controls change. The content scrolls inside the window so
/// the window keeps a sane size even with many cards.
@MainActor
struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(CardSettings.self) private var cards

    init(settings: AppSettings) {
        self._settings = Bindable(settings)
    }

    var body: some View {
        // Only the card list scrolls; the appearance controls above stay
        // fixed in place.
        VStack(alignment: .leading, spacing: 14) {
            appearanceRows
            Divider()
            Text(settings.localized("Cards"))
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(cards.order.indices, id: \.self) { index in
                        cardRow(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 380, height: 540)
    }

    // MARK: - Appearance

    private var appearanceRows: some View {
        VStack(spacing: 10) {
            HStack {
                Text(settings.localized("Language"))
                Spacer()
                Picker("", selection: $settings.language) {
                    ForEach(Language.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 118)
            }
            HStack {
                Text(settings.localized("Temperature unit"))
                Spacer()
                Picker("", selection: $settings.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 118)
            }
            HStack {
                Text(settings.localized("Card height"))
                Spacer()
                Slider(value: $settings.cardHeight, in: 24...96, step: 2)
                    .frame(width: 160)
                Text("\(Int(settings.cardHeight))")
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
            }
            HStack {
                Text(settings.localized("Bottom gap"))
                Spacer()
                Slider(
                    value: $settings.bottomGap,
                    in: 0...AppSettings.maxBottomGap,
                    step: 2
                )
                .frame(width: 160)
                Text("\(Int(settings.bottomGap)) px")
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
            HStack {
                Text(settings.localized("Background color"))
                Spacer()
                ColorPicker(
                    "", selection: backgroundColorBinding, supportsOpacity: false
                )
                .labelsHidden()
            }
            HStack {
                Text(settings.localized("Background opacity"))
                Spacer()
                Slider(value: $settings.backgroundOpacity, in: 0...1, step: 0.05)
                    .frame(width: 160)
                Text("\(Int((settings.backgroundOpacity * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
            HStack {
                Text(settings.localized("Text color"))
                Spacer()
                ColorPicker(
                    "", selection: textColorBinding, supportsOpacity: false
                )
                .labelsHidden()
            }
        }
    }

    // MARK: - Card rows

    private func cardRow(_ index: Int) -> some View {
        let kind = cards.order[index]
        let last = index == cards.order.count - 1
        return HStack(spacing: 8) {
            Button {
                cards.move(kind, by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)

            Button {
                cards.move(kind, by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(last)

            Toggle("", isOn: visibleBinding(kind))
                .labelsHidden()
                .help(settings.localized("Show/hide"))

            Text(settings.localized(kind.title))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Side", selection: sideBinding(kind)) {
                Text(settings.localized("Left")).tag(CardSide.left)
                Text(settings.localized("Right")).tag(CardSide.right)
            }
            .pickerStyle(.menu)
            .frame(width: 82)
        }
    }

    private func visibleBinding(_ kind: CardKind) -> Binding<Bool> {
        Binding(
            get: { cards.isVisible(kind) },
            set: { cards.setVisible($0, for: kind) }
        )
    }

    private func sideBinding(_ kind: CardKind) -> Binding<CardSide> {
        Binding(
            get: { cards.side(of: kind) },
            set: { cards.setSide($0, for: kind) }
        )
    }

    private var textColorBinding: Binding<Color> {
        Binding(
            get: { settings.textColor },
            set: { settings.textColorRGB = $0.rgbHex ?? AppSettings.defaultTextColorRGB }
        )
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { settings.backgroundColor },
            set: { settings.backgroundColorRGB = $0.rgbHex ?? AppSettings.defaultBackgroundColorRGB }
        )
    }
}