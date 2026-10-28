import SwiftUI

/// The date card's pop-up: a Sunday-first month grid with month/year
/// navigation and an inline month picker, so earlier and future months can be
/// browsed without leaving the hover pop-up.
///
/// The grid and the picker occupy exactly the same height (six week rows;
/// `Spacer` absorbs the difference in picker mode), so switching months or
/// opening the picker never resizes — and never jitters — the pop-up panel.
struct CalendarDetailView: View {
    @Environment(AppSettings.self) private var appearance

    /// A date inside the month currently shown.
    @State private var displayedMonth = Date()
    /// Whether the inline year/month picker replaces the day grid.
    @State private var isPickingMonth = false
    /// The year the picker browses; applying a month moves the calendar here.
    @State private var pickerYear = Calendar.current.component(.year, from: Date())

    private var calendar: Calendar {
        var calendar = Calendar.current
        // Weekday headers are Sunday-first; keep the day offsets in the same
        // frame even when the system calendar starts the week on Monday.
        calendar.firstWeekday = 1
        return calendar
    }

    private var locale: Locale { appearance.language.locale }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isPickingMonth {
                yearHeader
            } else {
                monthHeader
            }
            Group {
                if isPickingMonth {
                    monthPicker
                } else {
                    timelineGrid
                }
            }
            .frame(height: Layout.bodyHeight, alignment: .top)
        }
    }

    // MARK: - Headers

    /// Month browsing: year jump, month step, month/year title (opens the
    /// picker) and the same controls on the other side.
    private var monthHeader: some View {
        HStack(spacing: 2) {
            navButton("chevron.left.2", "Previous year") { shift(months: -12) }
            navButton("chevron.left", "Previous month") { shift(months: -1) }
            Spacer(minLength: 2)
            titleButton(
                monthTitle, chevron: "chevron.down",
                label: "Choose month and year"
            )
            Spacer(minLength: 2)
            navButton("chevron.right", "Next month") { shift(months: 1) }
            navButton("chevron.right.2", "Next year") { shift(months: 12) }
        }
    }

    /// Picker mode: browse the year, then choose one of its twelve months.
    private var yearHeader: some View {
        HStack(spacing: 2) {
            navButton("chevron.left", "Previous year") { pickerYear -= 1 }
            Spacer(minLength: 2)
            titleButton(yearTitle, chevron: "chevron.up", label: "Show calendar")
            Spacer(minLength: 2)
            navButton("chevron.right", "Next year") { pickerYear += 1 }
        }
    }

    private func titleButton(
        _ title: String, chevron: String, label: String
    ) -> some View {
        Button(action: togglePicker) {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: chevron)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(textColor.opacity(0.5))
            }
            .foregroundStyle(textColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appearance.localized(label))
    }

    private func navButton(
        _ symbol: String, _ label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(textColor.opacity(0.75))
                .frame(width: 16, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(textColor.opacity(0.07))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appearance.localized(label))
    }

    // MARK: - Day grid

    private var timelineGrid: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: Layout.rowSpacing) {
                weekdayHeader
                    .frame(height: Layout.weekdayHeight)
                ForEach(Array(monthGrid(for: displayedMonth).enumerated()), id: \.offset) {
                    _, week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            dayCell(day, today: context.date)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: Layout.dayCell)
                }
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, header in
                Text(header)
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(textColor.opacity(0.55))
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int?, today: Date) -> some View {
        if let number = day {
            let isToday = isToday(number, asOf: today)
            Text("\(number)")
                .font(.system(size: 11, weight: isToday ? .bold : .regular))
                .monospacedDigit()
                .frame(width: Layout.dayCell, height: Layout.dayCell)
                .background(
                    Circle().fill(isToday ? textColor : .clear)
                )
                .foregroundStyle(isToday ? appearance.backgroundColor : textColor)
        } else {
            Color.clear.frame(width: Layout.dayCell, height: Layout.dayCell)
        }
    }

    /// Six Sunday-first rows of day numbers (nil = empty cell). Always six
    /// rows, so the pop-up height is stable across months and years.
    private func monthGrid(for date: Date) -> [[Int?]] {
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start
        else { return Array(repeating: Array(repeating: nil, count: 7), count: Layout.weekCount) }
        let dayRange = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<1
        let leading = calendar.component(.weekday, from: monthStart) - 1
        var cells: [Int?] = Array(repeating: nil, count: leading)
        cells += dayRange.map { $0 }
        while cells.count < Layout.weekCount * 7 {
            cells.append(nil)
        }
        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }
    }

    private func isToday(_ day: Int, asOf date: Date) -> Bool {
        let shown = calendar.dateComponents([.year, .month], from: displayedMonth)
        let now = calendar.dateComponents([.year, .month, .day], from: date)
        return shown.year == now.year && shown.month == now.month && day == now.day
    }

    // MARK: - Month picker

    private var monthPicker: some View {
        VStack(spacing: 5) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
                spacing: 5
            ) {
                ForEach(1...12, id: \.self) { month in
                    monthButton(month)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button(action: goToToday) {
                    Text(appearance.localized("Today"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(textColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(textColor.opacity(0.1))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func monthButton(_ month: Int) -> some View {
        let selected = isSelectedMonth(month)
        return Button {
            select(month: month)
        } label: {
            Text(monthName(month))
                .font(.system(size: 10, weight: selected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(textColor.opacity(selected ? 0.2 : 0.06))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation

    private var monthTitle: String {
        displayedMonth.formatted(
            Date.FormatStyle(locale: locale).month(.wide).year()
        )
    }

    private var yearTitle: String {
        monthDate(month: 1, year: pickerYear).formatted(
            Date.FormatStyle(locale: locale).year()
        )
    }

    private func shift(months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private func togglePicker() {
        if !isPickingMonth {
            pickerYear = calendar.component(.year, from: displayedMonth)
        }
        isPickingMonth.toggle()
    }

    private func select(month: Int) {
        displayedMonth = monthDate(month: month, year: pickerYear)
        isPickingMonth = false
    }

    private func goToToday() {
        let now = Date()
        displayedMonth = now
        pickerYear = calendar.component(.year, from: now)
        isPickingMonth = false
    }

    private func monthDate(month: Int, year: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    private func isSelectedMonth(_ month: Int) -> Bool {
        let shown = calendar.dateComponents([.year, .month], from: displayedMonth)
        return shown.year == pickerYear && shown.month == month
    }

    private func monthName(_ month: Int) -> String {
        monthDate(month: month, year: pickerYear).formatted(
            Date.FormatStyle(locale: locale).month(.abbreviated)
        )
    }

    // MARK: - Geometry and symbols

    /// Fixed metrics keep both modes the same height.
    private enum Layout {
        static let dayCell: CGFloat = 22
        static let weekdayHeight: CGFloat = 12
        static let rowSpacing: CGFloat = 3
        static let weekCount = 6
        /// Weekday row + six day rows + six inter-row gaps.
        static let bodyHeight: CGFloat = weekdayHeight
            + CGFloat(weekCount) * dayCell
            + CGFloat(weekCount) * rowSpacing
    }

    /// Column headers, Sunday-first, indexed by language.
    private var weekdaySymbols: [String] {
        switch appearance.language {
        case .english: ["S", "M", "T", "W", "T", "F", "S"]
        case .chinese: ["日", "一", "二", "三", "四", "五", "六"]
        }
    }

    private var textColor: Color { appearance.textColor }
}