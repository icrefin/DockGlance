import AppKit
import SwiftUI

/// The About window hosting the SwiftUI page.
@MainActor
enum AboutWindow {
    static func make(settings: AppSettings) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = settings.localized("About DockGlance")
        window.contentView = NSHostingView(
            rootView: AboutView().environment(settings)
        )
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}