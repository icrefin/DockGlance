import AppKit
import DockGlanceCore
import SwiftUI

/// An `NSHostingView` that pops a context menu on right-click and reports
/// the pointer's horizontal position while it hovers the widget. Setting
/// the plain `.menu` property is unreliable inside a borderless,
/// non-activating panel, so we handle the right-click explicitly; SwiftUI's
/// `.onHover` does not fire in a non-key panel, so hover is tracked here
/// with an `.activeAlways` AppKit tracking area.
private final class MenuHostingView<Content: View>: NSHostingView<Content> {
    var contextMenu: NSMenu?

    /// Fired with the pointer's x position (panel coordinates) on every
    /// hover move; the panel's hover machinery deduplicates per tile.
    var onHoverMove: ((CGFloat) -> Void)?
    /// Fired once when the pointer leaves the widget.
    var onHoverEnd: (() -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        if let contextMenu {
            NSMenu.popUpContextMenu(contextMenu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu ?? super.menu(for: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverMove?(convert(event.locationInWindow, from: nil).x)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverEnd?()
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverMove?(convert(event.locationInWindow, from: nil).x)
    }
}

/// Borderless, non-activating panel that floats above regular windows and
/// stays in every Space; it hosts the SwiftUI dashboard.
final class WidgetPanel: NSPanel {
    /// Which end of the dock band this panel anchors to.
    var placement = Placement.first

    /// Hover callbacks, wired by the owner (e.g. to open detail pop-ups).
    var onHoverMove: ((CGFloat) -> Void)?
    var onHoverEnd: (() -> Void)?

    init<Content: View>(rootView: Content, menu: NSMenu?) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true

        let host = MenuHostingView(rootView: rootView)
        host.contextMenu = menu
        host.wantsLayer = true
        host.menu = menu
        host.onHoverMove = { [weak self] x in self?.onHoverMove?(x) }
        host.onHoverEnd = { [weak self] in self?.onHoverEnd?() }
        contentView = host
    }

    /// Positions the panel so its bottom edge sits `bottomMargin` points
    /// above the bottom of the primary screen, flush to the left or right
    /// edge depending on `placement` with a `margin`-point side gap.
    func place(placement: Placement, margin: CGFloat, bottomMargin: CGFloat) {
        guard let screen = NSScreen.screens.first else { return }
        let f = screen.frame
        let size = frame.size
        let x: CGFloat
        switch placement {
        case .first: x = f.minX + margin
        case .second: x = f.maxX - margin - size.width
        }
        let y = f.minY + bottomMargin
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}