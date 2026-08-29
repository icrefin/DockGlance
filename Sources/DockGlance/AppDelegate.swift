import AppKit
import DockGlanceCore
import Observation
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Gap between a card panel and the left/right screen edge. The gap to
    /// the screen bottom is the user-facing `bottomGap` setting.
    private static let margin: CGFloat = 4

    private let store = SystemStore()
    private let cardSettings = CardSettings()
    private let appSettings = AppSettings()
    private let profileStore = ProfileStore()
    private let popup = PopupManager()
    private var panels: [WidgetPanel] = []
    private var settingsPanel: NSWindow?
    private var aboutPanel: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
        store.clockLocale = appSettings.language.locale
        observeSettings()
        observeBottomGap()
        observeLanguage()
        rebuildPanels()
        observeScreenChanges()
        // Apply the profile matching the current display configuration once
        // panels are up (a no-op when none matches or it is already active).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.autoApplyProfileForDisplay()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    // MARK: - Panel

    /// Rebuilds the panels that host the visible cards. Each card is placed
    /// on the side the user chose (left or right), in the user's chosen
    /// order, at the card height the user set (width, icons and text keep
    /// the card's aspect ratio).
    private func rebuildPanels() {
        popup.closeNow()
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()

        let visible = CardKind.allCases.filter(cardSettings.isVisible)
        guard !visible.isEmpty else { return }

        let scale = min(
            max(appSettings.cardHeight / DashboardView.referenceThickness, 0.4), 3
        )

        let ordered = cardSettings.ordered(visible)
        let leftKinds = ordered.filter { cardSettings.side(of: $0) == .left }
        let rightKinds = ordered.filter { cardSettings.side(of: $0) == .right }
        if !leftKinds.isEmpty {
            panels.append(makePanel(kinds: leftKinds, placement: .first, scale: scale))
        }
        if !rightKinds.isEmpty {
            panels.append(makePanel(kinds: rightKinds, placement: .second, scale: scale))
        }

        panels.forEach { $0.orderFrontRegardless() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.placePanels()
        }
    }

    private func makePanel(
        kinds: [CardKind], placement: Placement, scale: CGFloat
    ) -> WidgetPanel {
        let root = DashboardView(kinds: kinds, scale: scale)
            .environment(store)
            .environment(cardSettings)
            .environment(appSettings)
        let panel = WidgetPanel(rootView: root, menu: appMenu)
        panel.placement = placement

        // Hover tracking (AppKit, see WidgetPanel) drives the pop-ups.
        panel.onHoverMove = { [weak self] x in
            guard let self else { return }
            self.popup.hover(
                x: x, in: panel, kinds: kinds, scale: scale,
                appearance: self.appSettings, store: self.store
            )
        }
        panel.onHoverEnd = { [weak self] in
            self?.popup.hide()
        }

        // Size the panel to match the SwiftUI content exactly.
        let tileWidth = MetricTile.referenceTileWidth * scale
        let tileHeight = MetricTile.referenceThickness * scale
        let count = CGFloat(kinds.count)
        let spacing: CGFloat = 2 * scale
        let padding: CGFloat = 8 * scale
        let panelWidth = count * tileWidth + (count - 1) * spacing + 2 * padding
        let panelHeight = tileHeight
        panel.setFrame(
            NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            display: false
        )
        return panel
    }

    private func placePanels() {
        for panel in panels {
            panel.place(
                placement: panel.placement,
                margin: Self.margin,
                bottomMargin: appSettings.bottomGap
            )
        }
    }

    // MARK: - Menus

    /// Shared context menu for right-clicking any card.
    private lazy var appMenu: NSMenu = {
        let menu = NSMenu(title: "DockGlance")
        menu.delegate = self
        menu.addItem(makeAboutItem())
        menu.addItem(makeSettingsItem())
        menu.addItem(makeStartAtLoginItem())
        menu.addItem(makeProfilesItem())
        menu.addItem(.separator())
        menu.addItem(quitItem)
        return menu
    }()

    // MARK: - Login item

    private func makeStartAtLoginItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Start at Login",
            action: #selector(toggleStartAtLogin),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }

    // MARK: - Profiles menu

    /// "Profiles ›" submenu: one row per saved profile (click to apply, the
    /// active one is checkmarked) plus save-current and delete items. Built
    /// fresh every time the menu opens so profiles saved or deleted from the
    /// settings window show up immediately.
    private func makeProfilesItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        item.submenu = rebuildProfilesMenu()
        return item
    }

    private func rebuildProfilesMenu() -> NSMenu {
        let submenu = NSMenu(title: "Profiles")
        for profile in profileStore.profiles {
            let row = NSMenuItem(
                title: profile.name,
                action: #selector(applyProfile(_:)),
                keyEquivalent: ""
            )
            row.target = self
            row.representedObject = profile.name
            row.state = profile.name == profileStore.activeProfileName ? .on : .off
            submenu.addItem(row)
        }
        if !profileStore.profiles.isEmpty {
            submenu.addItem(.separator())
        }
        let save = NSMenuItem(
            title: L10n.localized(
                "Save Current as Profile…", appSettings.language
            ),
            action: #selector(saveCurrentAsProfile),
            keyEquivalent: ""
        )
        save.target = self
        submenu.addItem(save)
        let delete = NSMenuItem(
            title: L10n.localized(
                "Delete Active Profile…", appSettings.language
            ),
            action: #selector(deleteActiveProfile),
            keyEquivalent: ""
        )
        delete.target = self
        delete.isEnabled = profileStore.activeProfile != nil
        submenu.addItem(delete)
        return submenu
    }

    @objc private func applyProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let profile = profileStore.profile(named: name) else { return }
        profileStore.apply(profile, settings: appSettings, cards: cardSettings)
    }

    @objc private func saveCurrentAsProfile() {
        let alert = NSAlert()
        alert.messageText = appSettings.localized("Save current settings as profile")
        alert.informativeText = appSettings.localized(
            "Overwrites an existing profile with the same name."
        )
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        field.placeholderString = appSettings.localized("Profile name")
        alert.accessoryView = field
        alert.addButton(withTitle: appSettings.localized("Save"))
        alert.addButton(withTitle: appSettings.localized("Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        profileStore.saveCurrentAs(name, settings: appSettings, cards: cardSettings)
    }

    @objc private func deleteActiveProfile() {
        guard let profile = profileStore.activeProfile else { return }
        let alert = NSAlert()
        alert.messageText = "\(appSettings.localized("Delete profile")) \"\(profile.name)\"?"
        alert.informativeText = appSettings.localized(
            "Your current settings stay unchanged."
        )
        alert.addButton(withTitle: appSettings.localized("Delete"))
        alert.addButton(withTitle: appSettings.localized("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        profileStore.delete(profile)
    }

    private var quitItem: NSMenuItem {
        let item = NSMenuItem(
            title: "Quit DockGlance",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return item
    }

    // MARK: - Login item

    private static let loginService = SMAppService.mainApp

    @objc private func toggleStartAtLogin() {
        do {
            if Self.loginService.status == .enabled {
                try Self.loginService.unregister()
            } else {
                try Self.loginService.register()
            }
        } catch {
            NSLog("DockGlance: failed to toggle login item: \(error)")
        }
    }

    private func refreshLoginItemState() {
        appMenu.items.forEach { item in
            if item.action == #selector(toggleStartAtLogin) {
                item.state = Self.loginService.status == .enabled ? .on : .off
            }
        }
    }

/// Syncs the login-item checkmark, refreshes localized titles and
/// rebuilds the Profiles submenu every time the menu opens, so changes
/// made elsewhere (language, profiles) show up immediately.
func menuWillOpen(_ menu: NSMenu) {
    refreshLoginItemState()
    refreshMenuTitles()
    guard let profilesItem = appMenu.items.first(
        where: { $0.submenu?.title == "Profiles" }
    ) else { return }
    profilesItem.submenu = rebuildProfilesMenu()
}

/// Re-localizes the fixed menu items (titles are set once at creation and
/// only change here, on language changes).
private func refreshMenuTitles() {
    let language = appSettings.language
    for item in appMenu.items {
        switch item.action {
        case #selector(openAbout):
            item.title = L10n.localized("About DockGlance", language)
        case #selector(openSettings):
            item.title = L10n.localized("Settings…", language)
        case #selector(toggleStartAtLogin):
            item.title = L10n.localized("Start at Login", language)
        case #selector(NSApplication.terminate(_:)):
            item.title = L10n.localized("Quit DockGlance", language)
        default:
            if item.submenu?.title == "Profiles" {
                item.title = L10n.localized("Profiles", language)
            }
        }
    }
}

    // MARK: - About window

    private func makeAboutItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "About DockGlance", action: #selector(openAbout), keyEquivalent: ""
        )
        item.target = self
        return item
    }

    @objc private func openAbout() {
        if aboutPanel == nil {
            aboutPanel = AboutWindow.make(settings: appSettings)
        }
        aboutPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings window

    private func makeSettingsItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ","
        )
        item.target = self
        return item
    }

    @objc private func openSettings() {
        if settingsPanel == nil {
            settingsPanel = SettingsWindow.make(
                settings: appSettings, cards: cardSettings
            )
        }
        settingsPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Rebuilds the panels whenever the card height or any card attribute
    /// (visibility, side, order) changes — from the settings window or the
    /// Cards menu. Opacity and text color re-render via SwiftUI's
    /// observation and don't need a rebuild.
    private func observeSettings() {
        withObservationTracking {
            _ = appSettings.cardHeight
            _ = cardSettings.order
            _ = CardKind.allCases.map(cardSettings.side(of:))
            _ = CardKind.allCases.map(cardSettings.isVisible)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.rebuildPanels()
                self?.observeSettings()
            }
        }
    }

    /// Repositions the panels when the bottom gap changes — only the y
    /// position moves, so no rebuild is needed.
    private func observeBottomGap() {
        withObservationTracking {
            _ = appSettings.bottomGap
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.placePanels()
                self?.observeBottomGap()
            }
        }
    }

    /// Applies the UI language live: the date/weekday cards re-format via
    /// the store's locale, the context menu re-localizes, and all SwiftUI
    /// text re-renders through observation.
    private func observeLanguage() {
        withObservationTracking {
            _ = appSettings.language
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.store.clockLocale = self.appSettings.language.locale
                self.refreshMenuTitles()
                self.observeLanguage()
            }
        }
    }

    // MARK: - Screen change handling

    private func observeScreenChanges() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func screenDidChange(_ note: Notification) {
        rebuildPanels()
        autoApplyProfileForDisplay()
    }

    /// When the display configuration changes, applies the saved profile
    /// whose recorded display mode matches the new configuration.
    private func autoApplyProfileForDisplay() {
        let current = DisplayMode.current()
        guard let profile = profileStore.profiles.first(where: {
            guard let mode = $0.displayMode else { return false }
            return mode.matches(current)
        }) else { return }
        guard profileStore.activeProfileName != profile.name else { return }
        profileStore.apply(profile, settings: appSettings, cards: cardSettings)
    }
}