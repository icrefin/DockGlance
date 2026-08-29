import AppKit
import DockGlanceCore
import SwiftUI

/// A widget tile that scales with the user-set card height and keeps its
/// aspect ratio. Icon cards split into an icon region (top, matching the old
/// visual proportions) and a text region (bottom, auto-scaled). No-icon cards
/// show centered text filling the full card. The card's bottom is anchored to
/// the screen by the panel placement.
struct MetricTile: View {
    /// Geometry at scale 1 (the reference = the current build's default
    /// 54 pt dock band). Feeding in `scale` > 1 enlarges, < 1 shrinks.
    static let referenceTileWidth: CGFloat = 130
    static let referenceThickness: CGFloat = 54
    static let referenceCornerRadius: CGFloat = 10

    let icon: String
    let title: String
    let value: String
    let detail: String?
    let color: Color
    var scale: CGFloat = 1
    var opacity: Double = 0.6
    var backgroundColor: Color = .white
    var textColor: Color = .white
    /// Render the detail (second) line at the same size as the value.
    var detailValueSized = false
    /// Omit the leading icon.
    var hideIcon = false
    /// Degrees to rotate the icon (e.g. 90 for a horizontal thermometer).
    var iconRotation: CGFloat = 0
    /// Center the text lines horizontally within the card.
    var centered = false

    @State private var isHovered = false

    private var tileWidth: CGFloat { Self.referenceTileWidth * scale }
    private var tileHeight: CGFloat { Self.referenceThickness * scale }
    private var contentWidth: CGFloat { tileWidth - 2 * 8 * scale }

    var body: some View {
        let valueSize = fittedValueSize
        ZStack {
            RoundedRectangle(cornerRadius: Self.referenceCornerRadius * scale)
                .fill(backgroundColor.opacity(opacity))

            if hideIcon {
                // No-icon card: text centered vertically in the full card.
                textContent(valueSize: valueSize)
                    .frame(width: contentWidth, height: tileHeight, alignment: .center)
            } else {
                // Icon card: icon region (old visual proportion) + text region.
                // The icon region height matches the old layout so the
                // visual proportions stay identical while the structural
                // separation guarantees no shifting.
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Image(systemName: icon)
                            .font(.system(size: iconSize, weight: .semibold))
                            .foregroundStyle(color)
                            .rotationEffect(.degrees(iconRotation))
                        Spacer()
                    }
                    .frame(height: iconRegionHeight)

                    textContent(valueSize: valueSize)
                        .frame(width: contentWidth, height: tileHeight - iconRegionHeight, alignment: .center)
                }
                .frame(width: tileWidth, height: tileHeight)
            }

            // Tooltip overlay on hover.
            if isHovered {
                RoundedRectangle(cornerRadius: Self.referenceCornerRadius * scale)
                    .fill(Color.black.opacity(0.85))
                Text(title)
                    .foregroundColor(.white)
                    .font(.system(size: max(16 * scale, 11), weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(6 * scale)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    /// The text block (value + optional detail). Sits at the top of its
    /// allocated region with minimal vertical spacing.
    private func textContent(valueSize: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 1 * scale) {
            Text(value)
                .foregroundColor(textColor)
                .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let detail {
                Text(detail)
                    .font(
                        .system(
                            size: detailValueSized ? valueSize : detailSize(for: valueSize),
                            weight: detailValueSized ? .semibold : .medium,
                            design: detailValueSized ? .rounded : nil
                        )
                    )
                    .monospacedDigit()
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    // MARK: - Auto-fit

    /// Icon size matching the old layout proportions so visual appearance
    /// stays identical. Derived only from `scale` so it never reacts to text.
    private var iconSize: CGFloat {
        guard !hideIcon else { return 0 }
        return min(tileHeight * 0.4, contentWidth)
    }

    /// Height of the icon region, matching the old layout (icon + spacing).
    private var iconRegionHeight: CGFloat {
        guard !hideIcon else { return 0 }
        return iconSize * 1.2 + 2 * scale
    }

    private func detailSize(for valueSize: CGFloat) -> CGFloat {
        max(9 * scale, valueSize * 0.6)
    }

    /// The largest value font size for which the value (and detail line, when
    /// present) fits the card's width and remaining height.
    private var fittedValueSize: CGFloat {
        var low = 8 * scale
        var high = 30 * scale
        for _ in 0..<12 {
            let mid = (low + high) / 2
            if fits(mid) { low = mid } else { high = mid }
        }
        return low * fitFraction
    }

    /// Fraction of the largest fitting size to use. Defaults to 0.8.
    private var fitFraction: CGFloat {
        0.8
    }

    private func fits(_ size: CGFloat) -> Bool {
        if measuredWidth(value, at: size) > contentWidth { return false }
        if let detail {
            let dSize = detailValueSized ? size : detailSize(for: size)
            if measuredWidth(detail, at: dSize) > contentWidth { return false }
        }
        // Text budget matches the old layout: remainder after icon region.
        let textLimit = hideIcon ? tileHeight : tileHeight - iconRegionHeight
        let valueHeight = size * 1.2
        let detailHeight = detail != nil
            ? 2 * scale + (detailValueSized ? size : detailSize(for: size)) * 1.2
            : 0
        return valueHeight + detailHeight <= textLimit
    }

    private func measuredWidth(_ text: String, at size: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
}

/// One row of tiles, filtered by the user's card visibility settings.
/// Cards: CPU, memory, temperature, disk, download, upload, battery,
/// connection, public IP, time, date, weather.
@MainActor
struct DashboardView: View {
    /// The dock band thickness that maps to `scale == 1`.
    static let referenceThickness = MetricTile.referenceThickness

    /// The tiles to show; when nil, every visible card in canonical order.
    private let kinds: [CardKind]?

    /// Dock-derived zoom applied to every tile and metric.
    let scale: CGFloat

    @Environment(SystemStore.self) private var store
    @Environment(CardSettings.self) private var settings
    @Environment(AppSettings.self) private var appearance

    init(kinds: [CardKind]? = nil, scale: CGFloat = 1) {
        self.kinds = kinds
        self.scale = scale
    }

    var body: some View {
        HStack(spacing: 2 * scale) {
            ForEach(visibleTiles, id: \.kind.rawValue) { tile in
                MetricTile(
                    icon: tile.spec.icon,
                    title: tile.spec.title,
                    value: tile.spec.value,
                    detail: tile.spec.detail,
                    color: tile.spec.color,
                    scale: scale,
                    opacity: appearance.backgroundOpacity,
                    backgroundColor: appearance.backgroundColor,
                    textColor: appearance.textColor,
                    detailValueSized: tile.spec.detailValueSized,
                    hideIcon: tile.spec.hideIcon,
                    iconRotation: tile.spec.iconRotation,
                    centered: tile.spec.centered
                )
            }
        }
        .padding(.horizontal, 8 * scale)
    }

    /// Tiles in canonical order, computed once per render.
    private var visibleTiles: [(kind: CardKind, spec: TileSpec)] {
        let kinds = kinds ?? CardKind.allCases.filter(settings.isVisible)
        return kinds.map { kind in
            var spec = spec(for: kind)
            spec.title = appearance.localized(spec.title)
            return (kind, spec)
        }
    }

    // MARK: - Tile specs

    private struct TileSpec {
        let icon: String
        var title: String
        let value: String
        let progress: Double?
        let color: Color
        var detail: String?
        var detailValueSized = false
        var hideIcon = false
        var centered = false
        var iconRotation: CGFloat = 0
    }

    private func spec(for kind: CardKind) -> TileSpec {
        let sample = store.sample
        switch kind {
        case .cpu:
            return TileSpec(
                icon: "cpu", title: "CPU",
                value: percent(sample.cpuPercent),
                progress: sample.cpuPercent, color: .blue
            )
        case .memory:
            return TileSpec(
                icon: "memorychip", title: "Memory",
                value: percent(sample.memoryPercent),
                progress: sample.memoryPercent, color: .green
            )
        case .temperature:
            return TileSpec(
                icon: temperatureIcon, title: "CPU Temperature",
                value: temperatureValue, progress: temperatureProgress,
                color: temperatureColor,
                iconRotation: 90
            )
        case .disk:
            return TileSpec(
                icon: "internaldrive", title: "Disk",
                value: percent(sample.diskPercent),
                progress: sample.diskPercent, color: .purple
            )
        case .download:
            return TileSpec(
                icon: "arrowtriangle.down.fill", title: "Download",
                value: ByteFormat.rate(sample.rxBytesPerSec),
                progress: 0, color: .teal
            )
        case .upload:
            return TileSpec(
                icon: "arrowtriangle.up.fill", title: "Upload",
                value: ByteFormat.rate(sample.txBytesPerSec),
                progress: 0, color: .pink
            )
        case .battery:
            return TileSpec(
                icon: batteryIcon, title: "Battery",
                value: batteryValue, progress: batteryProgress,
                color: batteryColor
            )
        case .connection:
            return TileSpec(
                icon: connectionIcon, title: "Network",
                value: sample.connection.summary,
                progress: nil, color: .indigo
            )
        case .publicIP:
            return TileSpec(
                icon: "globe", title: "Public IP",
                value: sample.publicIP.location,
                progress: nil, color: .cyan
            )
        case .time:
            return TileSpec(
                icon: "clock", title: "Time",
                value: sample.timeText,
                progress: nil, color: .red,
                hideIcon: true,
                centered: true
            )
        case .date:
            return TileSpec(
                icon: "calendar", title: "Date",
                value: sample.weekdayText,
                progress: nil, color: .yellow,
                detail: sample.dateText,
                detailValueSized: true,
                hideIcon: true,
                centered: true
            )
        case .weather:
            return TileSpec(
                icon: sample.weather.symbol ?? "cloud",
                title: "Weather",
                value: weatherValue, progress: nil, color: .orange
            )
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    // MARK: - Temperature

    private var temperatureValue: String {
        if let t = store.sample.cpuTemperature {
            return appearance.degrees(t)
        }
        return store.sample.thermalState.shortLabel
    }

    private var temperatureIcon: String {
        store.sample.cpuTemperature != nil ? "thermometer" : "thermometer.medium"
    }

    private var temperatureProgress: Double {
        guard let t = store.sample.cpuTemperature else { return 0 }
        return min(max((t - 30) / 60, 0), 1)
    }

    private var temperatureColor: Color {
        if let t = store.sample.cpuTemperature {
            switch t {
            case ..<55: return .orange
            case ..<80: return .yellow
            default: return .red
            }
        }
        switch store.sample.thermalState {
        case .nominal: return .green
        case .fair: return .orange
        default: return .red
        }
    }

    // MARK: - Battery

    private var batteryValue: String {
        guard let p = store.sample.batteryPercent else { return "—" }
        return "\(Int((p * 100).rounded()))%"
    }

    private var batteryIcon: String {
        guard let p = store.sample.batteryPercent else { return "battery.0" }
        if store.sample.batteryIsCharging { return "bolt.fill" }
        switch p {
        case ..<0.2: return "battery.0"
        case ..<0.45: return "battery.25"
        case ..<0.7: return "battery.50"
        case ..<0.9: return "battery.75"
        default: return "battery.100"
        }
    }

    private var batteryProgress: Double {
        store.sample.batteryPercent ?? 0
    }

    private var batteryColor: Color {
        guard let p = store.sample.batteryPercent else { return .secondary }
        if store.sample.batteryIsCharging { return .green }
        if p < 0.2 { return .red }
        return .yellow
    }

    // MARK: - Connection & weather

    private var connectionIcon: String {
        let connection = store.sample.connection
        if connection.isWired { return "network" }
        if connection.ssid != nil { return "wifi" }
        return "wifi.slash"
    }

    private var weatherValue: String {
        guard let t = store.sample.weather.temperature else { return "—" }
        return appearance.degrees(t)
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: "normal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        default: "unknown"
        }
    }

    var shortLabel: String {
        switch self {
        case .nominal: "NORM"
        case .fair: "FAIR"
        case .serious: "SER"
        case .critical: "CRIT"
        default: "—"
        }
    }
}