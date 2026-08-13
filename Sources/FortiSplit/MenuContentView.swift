import SwiftUI

/// Строковые литералы в SwiftUI-вью — это LocalizedStringKey: перевод для них
/// macOS подбирает сама по языку системы, из <язык>.lproj/Localizable.strings
/// внутри бандла. Строки, которые собираются в коде, переводим через
/// NSLocalizedString явно.
struct MenuContentView: View {
    @ObservedObject var vpn: VPNController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(verbatim: statusLine)

        Divider()

        if vpn.state == .connected || vpn.state == .connecting {
            Button("Disconnect") { vpn.disconnect() }
        } else {
            Button("Connect") { vpn.connect() }
        }

        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }

        Button("Show Log") { vpn.openLogs() }

        Divider()

        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    private var statusLine: String {
        let config = vpn.activeConfig.isEmpty ? "" : " · \(vpn.activeConfig)"
        switch vpn.state {
        case .connected:
            let base = String(format: NSLocalizedString("● Connected%@", comment: "menu status line"), config)
            return vpn.detail.isEmpty ? base : "\(base) · \(vpn.detail)"
        case .connecting:
            return String(format: NSLocalizedString("◌ Connecting…%@", comment: "menu status line"), config)
        case .disconnected:
            return String(format: NSLocalizedString("○ Disconnected%@", comment: "menu status line"), config)
        case .error:
            let base = NSLocalizedString("⚠ Error", comment: "menu status line")
            return vpn.detail.isEmpty ? base : "⚠ \(vpn.detail)"
        }
    }
}
