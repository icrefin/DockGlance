import AppKit
import SwiftUI

/// The settings window hosting the SwiftUI form.
@MainActor
enum SettingsWindow {
    static func make(settings: AppSettings, cards: CardSettings) -> NSWindow {
        let host = NSHostingView(
            rootView: SettingsView(settings: settings)
                .environment(cards)
                .fixedSize()
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = settings.localized("DockGlance Settings")
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}