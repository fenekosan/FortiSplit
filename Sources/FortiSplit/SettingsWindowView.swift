import SwiftUI
import AppKit

/// Окно настроек: сверху выбор конфига и действия над ним, ниже две вкладки —
/// сам конфиг и список подсетей для split-tunnel. Обе вкладки работают с тем
/// конфигом, который выбран в шапке; маршруты лежат рядом с ним (<имя>.routes).
///
/// Файлы читаются и пишутся напрямую (ConfigStore), root тут не участвует —
/// он нужен только чтобы применить маршруты к поднятому туннелю.
struct SettingsWindowView: View {
    @ObservedObject var vpn: VPNController

    /// Шапка зависит от вкладки: у конфигов свой набор действий, у маршрутов свой.
    private enum Tab: Hashable { case config, routes }
    @State private var tab: Tab = .config

    @State private var selected = ""
    @State private var configText = ""
    @State private var routesText = ""
    @State private var note = ""

    @State private var showNewSheet = false
    @State private var newName = ""
    @State private var confirmDelete = false

    private var store: ConfigStore { vpn.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            TabView(selection: $tab) {
                TextFileEditor(
                    hint: NSLocalizedString(
                        "The openfortivpn config, in «key = value» form. It lives in ~/.config/fortisplit; the password is stored as plain text, the file is kept at mode 0600.",
                        comment: "config tab hint"),
                    saveTitle: NSLocalizedString("Save", comment: "button"),
                    text: $configText,
                    onReload: loadConfigText,
                    onSave: saveConfigText
                )
                .tabItem { Text("Config") }
                .tag(Tab.config)

                TextFileEditor(
                    hint: NSLocalizedString(
                        "Subnets to send through the tunnel — one CIDR per line, e.g. 10.0.0.0/8. Lines starting with # are comments. Everything else goes through the normal connection.",
                        comment: "routes tab hint"),
                    saveTitle: NSLocalizedString("Save", comment: "button"),
                    text: $routesText,
                    onReload: loadRoutesText,
                    onSave: { saveRoutesText(applyAfterwards: false) },
                    extra: .init(
                        title: NSLocalizedString("Apply Now", comment: "button"),
                        help: NSLocalizedString(
                            "Push the subnets onto the running tunnel — no reconnect needed. Available while this config is the active one and its tunnel is up.",
                            comment: "tooltip"),
                        // маршруты кладутся на живой pppN, поэтому нужен поднятый
                        // туннель именно этого конфига
                        enabled: vpn.state == .connected && selected == vpn.activeConfig,
                        action: { saveRoutesText(applyAfterwards: true) })
                )
                .tabItem { Text("Routes") }
                .tag(Tab.routes)
            }

            footer
        }
        .padding(12)
        .frame(minWidth: 520, minHeight: 480)
        .onAppear { reload(select: vpn.activeConfig) }
        .sheet(isPresented: $showNewSheet) { newConfigSheet }
        .confirmationDialog(
            Text(verbatim: String(format: NSLocalizedString("Delete config “%@” together with its routes?",
                                                            comment: "delete confirmation"), selected)),
            isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(spacing: 8) {
            Picker("Config", selection: selectionBinding) {
                ForEach(vpn.configs, id: \.self) { name in
                    Text(verbatim: name == vpn.activeConfig ? "\(name) ✓" : name).tag(name)
                }
            }
            .labelsHidden()
            .frame(minWidth: 180)

            if tab == .config {
                Button("Make Active") {
                    vpn.setActive(selected)
                    note = String(format: NSLocalizedString("Active config: %@", comment: "status note"), selected)
                }
                .disabled(selected.isEmpty || selected == vpn.activeConfig)
            }

            Spacer()

            switch tab {
            case .config:
                Button("New") { newName = ""; showNewSheet = true }
                Button("Import…") { importConfig() }
                Button("Delete") { confirmDelete = true }
                    .disabled(selected.isEmpty || selected == vpn.activeConfig)
            case .routes:
                // здесь конфиги не заводят и не удаляют — только выбирают, к
                // какому относится список подсетей
                Button("Import…") { importRoutes() }
                    .disabled(selected.isEmpty)
                    .help(NSLocalizedString("Replace the subnet list of the selected config from a file",
                                            comment: "tooltip"))
            }
        }
    }

    private var footer: some View {
        Group {
            if !vpn.lastError.isEmpty {
                Text(verbatim: vpn.lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            } else if !note.isEmpty {
                Text(verbatim: note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var newConfigSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name of the new config").font(.headline)
            Text("Latin letters, digits, dot, dash, underscore.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("for example office", text: $newName)
                .frame(width: 260)
            HStack {
                Spacer()
                Button("Cancel") { showNewSheet = false }
                Button("Create") { createConfig() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(ConfigStore.sanitize(newName).isEmpty)
            }
        }
        .padding(16)
    }

    // MARK: - Выбор конфига

    private var selectionBinding: Binding<String> {
        Binding(
            get: { selected },
            set: { name in
                selected = name
                loadConfigText()
                loadRoutesText()
            }
        )
    }

    private func reload(select preferred: String) {
        vpn.reloadConfigs()
        selected = vpn.configs.contains(preferred) ? preferred
                 : (vpn.configs.contains(vpn.activeConfig) ? vpn.activeConfig : vpn.configs.first ?? "")
        loadConfigText()
        loadRoutesText()
    }

    // MARK: - Чтение и запись

    private func loadConfigText() { configText = store.readConfig(selected) }
    private func loadRoutesText() { routesText = store.readRoutes(selected) }

    private func saveConfigText() {
        guard !selected.isEmpty else { return }
        do {
            try store.writeConfig(selected, configText)
            vpn.lastError = ""
            note = String(format: NSLocalizedString("Config “%@” saved", comment: "status note"), selected)
        } catch {
            vpn.lastError = String(format: NSLocalizedString("could not save: %@", comment: "error"),
                                   error.localizedDescription)
        }
    }

    /// Сохраняет список и, если попросили, тут же кладёт его на поднятый
    /// туннель. Сохраняем и при «Применить сейчас» тоже — иначе применилось бы
    /// не то, что человек видит в редакторе.
    private func saveRoutesText(applyAfterwards: Bool) {
        guard !selected.isEmpty else { return }

        let bad = ConfigStore.invalidRouteLines(routesText)
        guard bad.isEmpty else {
            vpn.lastError = String(format: NSLocalizedString("not saved, unrecognized lines: %@", comment: "error"),
                                   bad.prefix(3).joined(separator: ", "))
            return
        }

        do {
            try store.writeRoutes(selected, routesText)
            vpn.lastError = ""
        } catch {
            vpn.lastError = String(format: NSLocalizedString("could not save: %@", comment: "error"),
                                   error.localizedDescription)
            return
        }

        guard applyAfterwards else {
            note = NSLocalizedString("Routes saved", comment: "status note")
            loadRoutesText()
            return
        }
        vpn.applyRoutes(selected) { ok in
            note = ok ? NSLocalizedString("Routes applied to the tunnel", comment: "status note") : ""
            loadRoutesText()
        }
    }

    // MARK: - Создание, импорт, удаление

    private func createConfig() {
        let name = uniqueName(ConfigStore.sanitize(newName))
        showNewSheet = false
        do {
            try store.writeConfig(name, ConfigStore.template)
            try store.writeRoutes(name, ConfigStore.routesTemplate)
            note = String(format: NSLocalizedString("Created config “%@”", comment: "status note"), name)
            reload(select: name)
        } catch {
            vpn.lastError = String(format: NSLocalizedString("could not create: %@", comment: "error"),
                                   error.localizedDescription)
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = NSLocalizedString("Choose an openfortivpn config file", comment: "open panel")
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }

        let name = uniqueName(ConfigStore.sanitize(url.deletingPathExtension().lastPathComponent))
        do {
            try store.writeConfig(name, text)
            if store.readRoutes(name).isEmpty { try store.writeRoutes(name, ConfigStore.routesTemplate) }
            note = String(format: NSLocalizedString("Imported as “%@”", comment: "status note"), name)
            reload(select: name)
        } catch {
            vpn.lastError = String(format: NSLocalizedString("could not import: %@", comment: "error"),
                                   error.localizedDescription)
        }
    }

    /// Заменяет список подсетей выбранного конфига содержимым файла.
    /// Негодные строки не проглатываем: текст показываем в редакторе, но на
    /// диск не пишем, пока человек их не поправит.
    private func importRoutes() {
        guard !selected.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = NSLocalizedString("Choose a file with the subnet list", comment: "open panel")
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }

        routesText = text
        let bad = ConfigStore.invalidRouteLines(text)
        guard bad.isEmpty else {
            vpn.lastError = String(format: NSLocalizedString("not saved, unrecognized lines: %@", comment: "error"),
                                   bad.prefix(3).joined(separator: ", "))
            return
        }
        do {
            try store.writeRoutes(selected, text)
            vpn.lastError = ""
            note = String(format: NSLocalizedString("Routes replaced from “%@”", comment: "status note"),
                          url.lastPathComponent)
            loadRoutesText()
        } catch {
            vpn.lastError = String(format: NSLocalizedString("could not import: %@", comment: "error"),
                                   error.localizedDescription)
        }
    }

    private func deleteSelected() {
        let name = selected
        do {
            try store.delete(name)
            note = String(format: NSLocalizedString("Config “%@” deleted", comment: "status note"), name)
            reload(select: vpn.activeConfig)
        } catch {
            vpn.lastError = String(format: NSLocalizedString("could not delete: %@", comment: "error"),
                                   error.localizedDescription)
        }
    }

    private func uniqueName(_ base: String) -> String {
        guard vpn.configs.contains(base) else { return base }
        var n = 2
        while vpn.configs.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }
}
