import SwiftUI
import AppKit

@main
struct FortiSplitApp: App {
    @StateObject private var vpn = VPNController()

    var body: some Scene {
        // Меню в статус-баре. Иконка меняется в зависимости от состояния.
        MenuBarExtra {
            MenuContentView(vpn: vpn)
        } label: {
            statusIcon
        }
        .menuBarExtraStyle(.menu)

        // Окно настроек: конфиги + маршруты (открывается из меню).
        // Заголовок — LocalizedStringKey, перевод берётся из <язык>.lproj.
        Window("FortiSplit Settings", id: "settings") {
            SettingsWindowView(vpn: vpn)
        }
        .windowResizability(.contentSize)
    }

    /// Иконка статус-бара — монохромные глифы, собранные из иконки приложения
    /// (scripts/make-menubar-icon.swift). Залитый щит = туннель поднят,
    /// контурный = выключено. Ошибка остаётся символом SF: она должна
    /// выбиваться из ряда, а мотив щита при этом сохраняется.
    @ViewBuilder private var statusIcon: some View {
        switch vpn.state {
        case .connected:    brandIcon("MenuIcon")
        case .connecting:   brandIcon("MenuIcon").opacity(0.45)
        case .disconnected: brandIcon("MenuIconOutline")
        case .error:        Image(systemName: "exclamationmark.shield")
        }
    }

    /// Вне бандла (запуск бинарника напрямую) ресурсов нет — тогда символ SF.
    private func brandIcon(_ name: String) -> Image {
        guard let image = NSImage(named: name) else { return Image(systemName: "lock.shield") }
        image.isTemplate = true          // цвет под светлую/тёмную строку меню подберёт macOS
        return Image(nsImage: image)
    }
}
