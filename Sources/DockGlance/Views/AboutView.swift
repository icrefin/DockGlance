import AppKit
import SwiftUI

/// The About page: app icon, version, author and contact info. Opened from
/// the "About DockGlance" item in the card context menu.
struct AboutView: View {
    private static let authorName = "icrefin"
    private static let authorEmail = "icrefinai@gmail.com"

    @Environment(AppSettings.self) private var appearance

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 72, height: 72)
            Text("DockGlance")
                .font(.title2.bold())
            Text("\(appearance.localized("Version")) \(version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 220)

            VStack(spacing: 6) {
                Text("\(appearance.localized("Author")): \(Self.authorName)")
                Link(Self.authorEmail, destination: mailURL)
            }
            .font(.body)

            Text("© \(Self.authorName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .frame(width: 300)
    }

    private var appIcon: NSImage {
        NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0.1.0"
    }

    private var mailURL: URL {
        URL(string: "mailto:\(Self.authorEmail)")!
    }
}