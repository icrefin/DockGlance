import AppKit
import DockGlanceCore
import SwiftUI

/// Owns the single hover pop-up: one borderless panel reused across all
/// cards, shown above the hovered card and hidden (debounced) when the
/// pointer leaves it. Hover positions arrive from the widget panels'
/// AppKit tracking areas (`WidgetPanel.onHoverMove`). Content lives in
/// `PopupView`.
@MainActor
final class PopupManager {
    private var panel: PopupPanel?
    private var hideTask: Task<Void, Never>?
    /// The tile the popup currently belongs to, for move-deduplication.
    private var active: (panel: WidgetPanel, index: Int)?

    /// Delay before the popup hides after the pointer leaves a card, so
    /// moving across the small gaps between tiles does not flicker.
    private static let hideDelay: TimeInterval = 0.15

    /// Pointer moved to x (panel-local coordinate) inside `widget`.
    /// Shows the hovered card's pop-up; the tile layout is deterministic
    /// (fixed tile width), so the mapping from x to card is exact.
    func hover(
        x: CGFloat,
        in widget: WidgetPanel,
        kinds: [CardKind],
        scale: CGFloat,
        appearance: AppSettings,
        store: SystemStore
    ) {
        hideTask?.cancel()
        let tileWidth = MetricTile.referenceTileWidth * scale
        let spacing: CGFloat = 2 * scale
        let padding: CGFloat = 8 * scale
        let index = Int(((x - padding) / (tileWidth + spacing)).rounded(.down))
        guard index >= 0, index < kinds.count else {
            hide()
            return
        }
        let kind = kinds[index]
        guard kind.hasPopup else {
            hide()
            return
        }
        // Skip only when this tile's popup is *currently visible* — the
        // pointer can leave and re-enter the same card while the popup is
        // hidden (debounce fired), and the dedupe must not swallow the
        // re-show.
        if let active, active.panel === widget, active.index == index,
           panel?.isVisible == true {
            return
        }
        active = (widget, index)
        let centerX = widget.frame.minX + padding
            + CGFloat(index) * (tileWidth + spacing) + tileWidth / 2
        show(
            kind: kind,
            centerX: centerX,
            above: widget.frame.maxY,
            appearance: appearance,
            store: store,
            anchorScreen: widget.screen
        )
    }

    /// Hides the popup shortly after the pointer leaves a card.
    func hide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.hideDelay))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }

    /// Closes the popup immediately (e.g. when the panels are rebuilt).
    func closeNow() {
        hideTask?.cancel()
        active = nil
        panel?.orderOut(nil)
    }

    private func show(
        kind: CardKind,
        centerX: CGFloat,
        above bandTop: CGFloat,
        appearance: AppSettings,
        store: SystemStore,
        anchorScreen: NSScreen?
    ) {
        let popup = panel ?? makePanel()
        popup.display(kind: kind, appearance: appearance, store: store)
        let size = popup.contentSize
        popup.setFrame(
            frameRect(size: size, centerX: centerX, above: bandTop, screen: anchorScreen),
            display: true
        )
        popup.orderFrontRegardless()
    }

    private func makePanel() -> PopupPanel {
        let popup = PopupPanel()
        panel = popup
        return popup
    }

    /// A frame for the popup: horizontally centered on the card, just
    /// above the widget band, clamped to the visible screen — flipped to
    /// below the band when there is no room above.
    private func frameRect(
        size: CGSize, centerX: CGFloat, above bandTop: CGFloat,
        screen: NSScreen?
    ) -> NSRect {
        let bounds = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let gap: CGFloat = 8
        var x = centerX - size.width / 2
        x = min(max(x, bounds.minX + 4), bounds.maxX - size.width - 4)
        var y = bandTop + gap
        if y + size.height > bounds.maxY {
            y = bandTop - size.height - gap
        }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

/// A borderless, non-activating panel that floats above every window and
/// hosts the hover popup's SwiftUI content.
private final class PopupPanel: NSPanel {
    private var host: NSHostingView<AnyView>?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
    }

    /// Re-roots the panel with the content for `kind` and sizes it to that
    /// content's natural size.
    func display(kind: CardKind, appearance: AppSettings, store: SystemStore) {
        let view = PopupView(kind: kind)
            .environment(appearance)
            .environment(store)
        let host = NSHostingView(rootView: AnyView(view))
        host.wantsLayer = true
        self.host = host
        contentView = host
        host.layoutSubtreeIfNeeded()
        let fitted = host.fittingSize
        let width = fitted.width > 0 ? fitted.width : 260
        let height = fitted.height > 0 ? fitted.height : 200
        setFrame(
            NSRect(x: frame.minX, y: frame.minY, width: width, height: height),
            display: false
        )
    }

    var contentSize: CGSize {
        let fitted = host?.fittingSize ?? frame.size
        return CGSize(
            width: fitted.width > 0 ? fitted.width : 260,
            height: fitted.height > 0 ? fitted.height : 200
        )
    }
}