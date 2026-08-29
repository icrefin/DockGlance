import CoreGraphics
import Foundation

/// Did a window's frame instruct the dock to be, or did we have to guess?
public enum DockEdge: String, Sendable {
    case bottom
    case left
    case right
    case top
}

/// Which of the two corners adjacent to the dock the widget occupies:
/// "first" is the corner nearest the screen origin on the edge's axis.
public enum Placement: String, Sendable {
    case first
    case second

/// The corner currently occupied, for the given edge.
    public func corner(for edge: DockEdge) -> Corner {
        let corners = DockPosition.corners(for: edge)
        return self == .first ? corners[0] : corners[1]
    }
}

/// The four physical screen corners.
public enum Corner: String, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    /// The other corner sharing the same edge.
    public func flipped() -> Corner {
        switch self {
        case .topLeft: .topRight
        case .topRight: .topLeft
        case .bottomLeft: .bottomRight
        case .bottomRight: .bottomLeft
        }
    }
}

/// Pure geometry for detecting the dock edge from screen frames and
/// computing where the widget window must sit in the dock's band.
public enum DockPosition {
    /// The default band thickness when the dock is hidden or undetectable.
    public static let defaultDockThickness: CGFloat = 54

    /// Deduces the dock edge by comparing the screen's visible frame with
    /// its full frame: the dock shrinks the visible frame on one edge only.
    public static func edge(screenFrame: CGRect, visibleFrame: CGRect) -> DockEdge {
        let f = screenFrame
        let v = visibleFrame
        let tolerance: CGFloat = 1
        if v.minX - f.minX > tolerance { return .left }
        if v.minY - f.minY > tolerance { return .bottom }
        if f.maxX - v.maxX > tolerance { return .right }
        if f.maxY - v.maxY > tolerance { return .top }
        return .bottom
    }

    /// The two corners adjacent to the given edge, in first/second order.
    public static func corners(for edge: DockEdge) -> [Corner] {
        switch edge {
        case .bottom: [.bottomLeft, .bottomRight]
        case .top: [.topLeft, .topRight]
        case .left: [.topLeft, .bottomLeft]
        case .right: [.topRight, .bottomRight]
        }
    }

    /// The dock's thickness along its own band, e.g. the vertical extent of
    /// a bottom dock. Falls back to `defaultDockThickness` when the dock is
    /// hidden (visible frame equals screen frame).
    public static func dockThickness(
        _ edge: DockEdge, screenFrame: CGRect, visibleFrame: CGRect
    ) -> CGFloat {
        let f = screenFrame
        let v = visibleFrame
        let thickness: CGFloat
        switch edge {
        case .bottom: thickness = v.minY - f.minY
        case .top: thickness = f.maxY - v.maxY
        case .left: thickness = v.minX - f.minX
        case .right: thickness = f.maxX - v.maxX
        }
        return thickness > 0 ? thickness : defaultDockThickness
    }

    /// Distributes `count` equal-sized cards between the two ends of the
    /// dock's band: cards fill one by one from the first end (left of a
    /// bottom/top dock, top of a left/right dock) toward the Dock's icons;
    /// when the remaining gap can no longer hold another card, the rest
    /// are placed at the second end, starting at the screen's edge and
    /// working inward.
    ///
    /// `cardWidth` is one card's width, `spacing` the gap between cards,
    /// and `endPadding` the padding at each end of a card row. Without a
    /// `dockFrame` the band is split at its midpoint. Returns how many
    /// cards fit at the first end; the remainder goes to the second end.
    public static func splitCards(
        count: Int,
        cardWidth: CGFloat,
        spacing: CGFloat,
        endPadding: CGFloat,
        screenFrame: CGRect,
        dockFrame: CGRect?,
        edge: DockEdge,
        margin: CGFloat
    ) -> Int {
        guard count > 0 else { return 0 }
        let horizontal = edge == .bottom || edge == .top
        let axisMin = horizontal ? screenFrame.minX : screenFrame.minY
        let band = horizontal ? screenFrame.width : screenFrame.height

        let firstGap: CGFloat
        if let dock = dockFrame {
            let dockStart = horizontal ? dock.minX : dock.minY
            firstGap = max(dockStart - axisMin, 0)
        } else {
            // No dock bounds (hidden, or Accessibility not granted): reserve
            // a conservative central zone so cards never overlap a real
            // centered dock. Each side gets 30% of the band.
            firstGap = band * 0.3
        }

        let firstUsable = firstGap - 2 * margin
        let firstMax = maxCards(
            in: firstUsable,
            cardWidth: cardWidth,
            spacing: spacing,
            endPadding: endPadding
        )
        return min(count, firstMax)
    }

    /// How many cards fit in a row of `usable` width: each card takes
    /// `cardWidth`, with `spacing` between neighbors and `endPadding`
    /// at each end of the row.
    private static func maxCards(
        in usable: CGFloat,
        cardWidth: CGFloat,
        spacing: CGFloat,
        endPadding: CGFloat
    ) -> Int {
        var count = 0
        while rowWidth(
            count + 1, cardWidth: cardWidth, spacing: spacing, endPadding: endPadding
        ) <= usable {
            count += 1
        }
        return count
    }

    /// Total width of a row of `count` cards with the given metrics.
    private static func rowWidth(
        _ count: Int,
        cardWidth: CGFloat,
        spacing: CGFloat,
        endPadding: CGFloat
    ) -> CGFloat {
        CGFloat(count) * cardWidth
            + CGFloat(max(count - 1, 0)) * spacing
            + 2 * endPadding
    }

    /// Where to draw a window of `windowSize` inside the dock's band.
    ///
    /// The window keeps `windowSize.height` (or width for a vertical dock)
    /// while its span along the band matches the dock thickness; it is
    /// placed `margin` points inside the screen's edge, at the first or
    /// second end of the band like a dock app icon.
    public static func frame(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        placement: Placement,
        windowSize: CGSize,
        margin: CGFloat
    ) -> CGRect {
        let f = screenFrame
        let v = visibleFrame
        let edge = edge(screenFrame: f, visibleFrame: v)
        let thickness = dockThickness(edge, screenFrame: f, visibleFrame: v)
        let span = windowSize.width
        let length = windowSize.height
        let first = placement == .first

        switch edge {
        case .bottom:
            let x = first ? f.minX + margin : f.maxX - margin - span
            return CGRect(x: x, y: f.minY, width: span, height: thickness)
        case .top:
            let x = first ? f.minX + margin : f.maxX - margin - span
            return CGRect(x: x, y: v.maxY, width: span, height: thickness)
        case .left:
            let y = first ? f.minY + margin : f.maxY - margin - length
            return CGRect(x: f.minX, y: y, width: thickness, height: length)
        case .right:
            let y = first ? f.minY + margin : f.maxY - margin - length
            return CGRect(x: v.maxX, y: y, width: thickness, height: length)
        }
    }
}