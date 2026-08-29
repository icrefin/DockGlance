import DockGlanceCore
import SwiftUI

/// The hover pop-up content: a rounded card identical to the widget tiles
/// (same background color and opacity, shadow comes from the panel) with a
/// per-card detail layout. Re-renders live with the tick.
struct PopupView: View {
    let kind: CardKind

    @Environment(AppSettings.self) private var appearance
    @Environment(SystemStore.self) private var store

    private static let popupWidth: CGFloat = 250
    /// Detail-heavy popups (public IP rows carry long ISP/org names).
    private static let widePopupWidth: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(popupTitle.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(textColor.opacity(0.55))
            content
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(appearance.backgroundColor.opacity(appearance.backgroundOpacity))
        )
        .frame(width: Self.width(for: kind), alignment: .leading)
    }

    /// Pop-up header; the connection card uses the short form.
    private var popupTitle: String {
        kind == .connection
            ? appearance.localized("Connection")
            : appearance.localized(kind.title)
    }

    private static func width(for kind: CardKind) -> CGFloat {
        kind == .publicIP ? Self.widePopupWidth : Self.popupWidth
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .cpu:
            processList(store.sample.topCpu) { Row(name: $0.name, value: "\(Int($0.value.rounded()))%") }
        case .memory:
            processList(store.sample.topMemory) {
                Row(name: $0.name, value: ByteFormat.bytes(UInt64($0.value * 1024)))
            }
        case .disk:
            diskDetail
        case .download:
            let procs = store.sample.networkProcs
                .sorted { $0.rxBytesPerSec > $1.rxBytesPerSec }
                .filter { $0.rxBytesPerSec > 0 }
            processList(procs) {
                Row(name: $0.name, value: ByteFormat.bytes(UInt64($0.rxBytesPerSec)) + "/s")
            }
        case .upload:
            let procs = store.sample.networkProcs
                .sorted { $0.txBytesPerSec > $1.txBytesPerSec }
                .filter { $0.txBytesPerSec > 0 }
            processList(procs) {
                Row(name: $0.name, value: ByteFormat.bytes(UInt64($0.txBytesPerSec)) + "/s")
            }
        case .battery:
            batteryDetail
        case .weather:
            weatherDetail
        case .time:
            tickingClock
        case .date:
            calendarView
        case .temperature:
            thermalDetail
        case .connection:
            bluetoothList
        case .publicIP:
            publicIPDetail
        }
    }

    // MARK: - Temperature

    private var thermalDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(temperatureValue)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(textColor)
            tempTrend
            fanLine
        }
    }

    private var temperatureValue: String {
        store.sample.cpuTemperature
            .map { appearance.degrees($0, decimals: 1) } ?? "—"
    }

    /// A small polyline of the last ~2 minutes of CPU temperature
    /// (5-point moving average), with dotted level lines running from the
    /// highest and lowest points to the right edge, labeled above/below.
    /// Fills whatever width the pop-up gives it.
    private var tempTrend: some View {
        let history = movingAverage(store.temperatureHistory, window: 5)
        let low = history.min() ?? 0
        let span = max((history.max() ?? low) - low, 1)
        let maxIndex = history.indices.max { history[$0] < history[$1] } ?? 0
        let minIndex = history.indices.min { history[$0] < history[$1] } ?? 0

        return GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let xAt: (Int) -> CGFloat = {
                width * CGFloat($0) / CGFloat(max(history.count - 1, 1))
            }
            let yAt: (Int) -> CGFloat = {
                height * (1 - CGFloat((history[$0] - low) / span))
            }

            ZStack {
                if history.count >= 2 {
                    Path { path in
                        for (index, value) in history.enumerated() {
                            let point = CGPoint(x: xAt(index), y: yAt(index))
                            if index == 0 {
                                path.move(to: point)
                            } else {
                                path.addLine(to: point)
                            }
                        }
                    }
                    .stroke(textColor.opacity(0.85), lineWidth: 1.5)

                    dashedLevel(
                        y: yAt(maxIndex), fromX: xAt(maxIndex),
                        width: width, color: .orange
                    )
                    trendLabel(
                        appearance.degrees(history[maxIndex], decimals: 1),
                        y: yAt(maxIndex) - 9,
                        x: (xAt(maxIndex) + width) / 2,
                        color: .orange,
                        containerWidth: width
                    )
                    if minIndex != maxIndex {
                        dashedLevel(
                            y: yAt(minIndex), fromX: xAt(minIndex),
                            width: width, color: .cyan
                        )
                        trendLabel(
                            appearance.degrees(history[minIndex], decimals: 1),
                            y: yAt(minIndex) + 10,
                            x: (xAt(minIndex) + width) / 2,
                            color: .cyan,
                            containerWidth: width
                        )
                    }
                } else {
                    Color.clear
                }
            }
            .frame(width: width, height: height)
        }
        .frame(height: 52)
    }

    /// Centered moving average; a short series is returned unchanged.
    private func movingAverage(_ values: [Double], window: Int) -> [Double] {
        guard values.count > window else { return values }
        let half = window / 2
        return values.indices.map { index in
            let lo = max(0, index - half)
            let hi = min(values.count, index + half + 1)
            let slice = values[lo..<hi]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    private func dashedLevel(
        y: CGFloat, fromX: CGFloat, width: CGFloat, color: Color
    ) -> some View {
        Path { path in
            path.move(to: CGPoint(x: fromX, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }
        .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func trendLabel(
        _ text: String, y: CGFloat, x: CGFloat,
        color: Color, containerWidth: CGFloat
    ) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(color)
            .position(x: min(x, containerWidth - 24), y: max(y, 10))
    }

    @ViewBuilder
    private var fanLine: some View {
        let status = store.sample.fanStatus
        if let status, status.count == 0 || status.rpm.isEmpty {
            thermalLine(appearance.localized("Fanless"))
        } else if let status, !status.rpm.isEmpty {
            let speeds = status.rpm
                .map { "\(Int($0.rounded()))" }
                .joined(separator: " / ")
            thermalLine("\(appearance.localized("Fan")): \(speeds) \(appearance.localized("RPM"))")
        }
    }

    /// A body-size line for the thermal popup (slightly larger than the
    /// generic detail rows).
    private func thermalLine(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(textColor)
    }

    // MARK: - Bluetooth devices

    private var bluetoothList: some View {
        let devices = store.sample.bluetoothDevices
        if devices.isEmpty {
            return AnyView(placeholder("—"))
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(devices.enumerated()), id: \.offset) { _, name in
                    HStack(spacing: 8) {
                        BluetoothIcon()
                            .fill(textColor.opacity(0.6))
                            .frame(width: 11, height: 11)
                        Text(name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .font(.system(size: 12))
                            .foregroundStyle(textColor)
                    }
                }
            }
        )
    }

    // MARK: - Process lists

    /// Up to five rows, or a placeholder when there is no data yet.
    @ViewBuilder
    private func processList<T>(_ items: [T], row: @escaping (T) -> Row) -> some View {
        let rows = items.prefix(5).map(row)
        if rows.isEmpty {
            placeholder("—")
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                    item
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(textColor)
    }

    private struct Row: View {
        let name: String
        let value: String

        @Environment(AppSettings.self) private var appearance

        var body: some View {
            HStack(spacing: 8) {
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .font(.system(size: 12))
            .foregroundStyle(appearance.textColor)
        }
    }

    // MARK: - Disk

    private var diskDetail: some View {
        let used = store.sample.diskUsed
        let total = store.sample.diskTotal
        let free = total > used ? total - used : 0
        return VStack(alignment: .leading, spacing: 5) {
            labelRow(appearance.localized("Used"), ByteFormat.bytes(used))
            labelRow(appearance.localized("Free"), ByteFormat.bytes(free))
            labelRow(appearance.localized("Total"), ByteFormat.bytes(total))
        }
    }

    private func labelRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12))
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(textColor)
    }

    // MARK: - Public IP

    private var publicIPDetail: some View {
        let info = store.sample.publicIP
        return VStack(alignment: .leading, spacing: 5) {
            labelRow(appearance.localized("IP address"), ipValue(info))
            // Everything below is derived from the same lookup; when the
            // lookup has failed, a single "—" row is enough.
            if info.ip != "—" {
                labelRow(
                    appearance.localized("Country"),
                    info.flagEmoji == "—" ? info.country : "\(info.flagEmoji) \(info.country)"
                )
                labelRow(appearance.localized("Region"), info.region)
                labelRow(appearance.localized("City"), info.city)
                labelRow(appearance.localized("Postal code"), info.postal)
                labelRow(appearance.localized("ISP"), info.isp)
                labelRow(appearance.localized("Organization"), info.org)
                labelRow(appearance.localized("ASN"), info.asn)
                labelRow(appearance.localized("Timezone"), info.timezone)
            }
        }
    }

    private func ipValue(_ info: PublicIPInfo) -> String {
        info.type == "—" ? info.ip : "\(info.ip) (\(info.type))"
    }

    // MARK: - Battery

    private var batteryDetail: some View {
        let sample = store.sample
        return VStack(alignment: .leading, spacing: 5) {
            labelRow(appearance.localized("Charge"), batteryPercentText)
            labelRow(
                appearance.localized("Status"),
                sample.batteryIsCharging
                    ? appearance.localized("Charging")
                    : appearance.localized("On battery")
            )
            if let minutes = sample.batteryMinutesToFull, sample.batteryIsCharging {
                labelRow(appearance.localized("Time to full"), durationText(minutes))
            }
        }
    }

    private var batteryPercentText: String {
        guard let p = store.sample.batteryPercent else { return "—" }
        return "\(Int((p * 100).rounded()))%"
    }

    private func durationText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        let hourUnit = appearance.localized("h")
        if hours > 0 {
            return rest > 0
                ? "\(hours) \(hourUnit) \(rest) \(appearance.localized("min"))"
                : "\(hours) \(hourUnit)"
        }
        return "\(rest) \(appearance.localized("min"))"
    }

    // MARK: - Weather

    private var weatherDetail: some View {
        let weather = store.sample.weather
        return VStack(alignment: .leading, spacing: 5) {
            locationLine
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(weatherText(weather.temperature))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(appearance.localized(weather.title))
                    .font(.system(size: 12))
            }
            .foregroundStyle(textColor)
            if let humidity = validHumidity(weather.humidity) {
                detailLine("\(appearance.localized("Humidity")): \(humidity)%")
            }
            if let wind = validWind(weather.windSpeedKmh) {
                detailLine(
                    "\(appearance.localized("Wind")): \(wind) \(appearance.localized("km/h"))"
                )
            }
            if let feels = validTemperature(weather.apparentTemperature) {
                detailLine(
                    "\(appearance.localized("Feels like")): \(appearance.degrees(Double(feels)))"
                )
            }
            if let next = weather.nextDay, let symbol = Self.symbol(next.weatherCode),
               validTemperature(next.min) != nil, validTemperature(next.max) != nil {
                detailLine(
                    "\(appearance.localized("Tomorrow")): \(symbol) \(appearance.degrees(next.min))–\(appearance.degrees(next.max))"
                )
            }
        }
    }

    /// Renders the value only when it is physically plausible; nil when a
    /// sensor glitch or bogus payload sneaks in (nothing renders then).
    private func validHumidity(_ value: Double?) -> Int? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        return Int(value.rounded())
    }

    private func validWind(_ value: Double?) -> Int? {
        guard let value, value.isFinite, (0...200).contains(value) else { return nil }
        return Int(value.rounded())
    }

    private func validTemperature(_ value: Double?) -> Int? {
        guard let value, value.isFinite, (-100...70).contains(value) else { return nil }
        return Int(value.rounded())
    }

    @ViewBuilder
    private var locationLine: some View {
        let location = store.sample.location
        if let primary = location.primary {
            if let secondary = location.secondary {
                detailLine("\(primary) · \(secondary)")
            } else {
                detailLine(primary)
            }
        }
    }

    private func detailLine(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(textColor)
    }

    private func weatherText(_ temperature: Double?) -> String {
        temperature.map { appearance.degrees($0) } ?? "—"
    }

    private static func symbol(_ code: Int) -> String? {
        switch code {
        case 0: "☀️"
        case 1, 2: "🌤"
        case 3: "☁️"
        case 45, 48: "🌫"
        case 51...67: "🌧"
        case 71...77: "🌨"
        case 80...82: "🌦"
        case 85, 86: "🌨"
        case 95...99: "⛈"
        default: nil
        }
    }

    // MARK: - Ticking clock

    private var tickingClock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.timeFormatter.string(from: context.date))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(clockFooter(context.date))
                    .font(.system(size: 13))
            }
            .foregroundStyle(textColor)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// "Wed, Aug 8"-style footer, in the current language.
    private func clockFooter(_ date: Date) -> String {
        let locale = appearance.language.locale
        return "\(ClockText.weekday(date, locale: locale)), \(ClockText.date(date, locale: locale))"
    }

    // MARK: - Monthly calendar

    /// A month grid with the real calendar's weekday offset (1 = Sunday),
    /// today highlighted. Refreshes once a minute.
    private var calendarView: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    context.date.formatted(
                        Date.FormatStyle(locale: appearance.language.locale)
                            .month(.wide).year()
                    )
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(textColor)
                HStack(spacing: 0) {
                    ForEach(Self.weekdayHeaders[appearance.language] ?? [], id: \.self) { header in
                        Text(header)
                            .font(.system(size: 10))
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(textColor.opacity(0.55))
                    }
                }
                ForEach(Array(monthGrid(for: context.date).enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            dayCell(day)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: (day: Int?, isToday: Bool)) -> some View {
        if let number = day.day {
            Text("\(number)")
                .font(.system(size: 11, weight: day.isToday ? .bold : .regular))
                .monospacedDigit()
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(day.isToday ? textColor : .clear)
                )
                .foregroundStyle(day.isToday ? appearance.backgroundColor : textColor)
        } else {
            Color.clear.frame(width: 22, height: 22)
        }
    }

    private func monthGrid(
        for date: Date
    ) -> [[(day: Int?, isToday: Bool)]] {
        let calendar = Calendar.current
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start
        else { return [] }
        let dayRange = calendar.range(of: .day, in: .month, for: monthStart)
        let leading = calendar.component(.weekday, from: monthStart) - 1
        var rows: [[(day: Int?, isToday: Bool)]] = []
        var row: [(day: Int?, isToday: Bool)] = Array(
            repeating: (nil, false), count: leading
        )
        for day in dayRange ?? 1..<1 {
            let dayStart = calendar.date(
                byAdding: .day, value: day - 1, to: monthStart
            ) ?? Date.distantPast
            row.append((day, calendar.isDateInToday(dayStart)))
            if row.count == 7 {
                rows.append(row)
                row = []
            }
        }
        if !row.isEmpty {
            row += Array(repeating: (nil, false), count: 7 - row.count)
            rows.append(row)
        }
        return rows
    }

    /// Column headers, Sunday-first, indexed by language.
    private static let weekdayHeaders: [Language: [String]] = [
        .english: ["S", "M", "T", "W", "T", "F", "S"],
        .chinese: ["日", "一", "二", "三", "四", "五", "六"],
    ]

    private var textColor: Color { appearance.textColor }

    // MARK: - Bluetooth rune icon

    /// The classic Bluetooth logo (Hagall+Bjarkan rune), since no SF
    /// Symbols glyph exists for Bluetooth.
    private struct BluetoothIcon: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height) / 24
            let dx = rect.midX - 12 * s
            let dy = rect.midY - 12 * s
            return Path { p in
                // Upper-right triangle tip
                p.move(to: CGPoint(x: dx + 14.88 * s, y: dy + 16.29 * s))
                p.addLine(to: CGPoint(x: dx + 13 * s, y: dy + 18.17 * s))
                p.addLine(to: CGPoint(x: dx + 13 * s, y: dy + 14.41 * s))
                // Lower-right triangle tip
                p.move(to: CGPoint(x: dx + 13 * s, y: dy + 5.83 * s))
                p.addLine(to: CGPoint(x: dx + 14.88 * s, y: dy + 7.71 * s))
                p.addLine(to: CGPoint(x: dx + 13 * s, y: dy + 9.58 * s))
                // Main rune outline
                p.move(to: CGPoint(x: dx + 17.71 * s, y: dy + 7.71 * s))
                p.addLine(to: CGPoint(x: dx + 12 * s, y: dy + 2 * s))
                p.addLine(to: CGPoint(x: dx + 11 * s, y: dy + 2 * s))
                p.addLine(to: CGPoint(x: dx + 11 * s, y: dy + 9.58 * s))
                p.addLine(to: CGPoint(x: dx + 6.41 * s, y: dy + 5 * s))
                p.addLine(to: CGPoint(x: dx + 5 * s, y: dy + 6.41 * s))
                p.addLine(to: CGPoint(x: dx + 10.59 * s, y: dy + 12 * s))
                p.addLine(to: CGPoint(x: dx + 5 * s, y: dy + 17.58 * s))
                p.addLine(to: CGPoint(x: dx + 6.41 * s, y: dy + 19 * s))
                p.addLine(to: CGPoint(x: dx + 11 * s, y: dy + 14.41 * s))
                p.addLine(to: CGPoint(x: dx + 11 * s, y: dy + 22 * s))
                p.addLine(to: CGPoint(x: dx + 12 * s, y: dy + 22 * s))
                p.addLine(to: CGPoint(x: dx + 17.71 * s, y: dy + 16.29 * s))
                p.addLine(to: CGPoint(x: dx + 13.41 * s, y: dy + 12 * s))
                p.addLine(to: CGPoint(x: dx + 17.71 * s, y: dy + 7.71 * s))
                p.closeSubpath()
            }
        }
    }
}