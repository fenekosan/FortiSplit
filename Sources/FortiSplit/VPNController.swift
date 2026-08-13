import Foundation
import Combine
import AppKit

enum VPNState: String {
    case disconnected = "DISCONNECTED"
    case connecting   = "CONNECTING"
    case connected    = "CONNECTED"
    case error        = "ERROR"
}

/// Привилегированная часть — один root-скрипт:
///   sudo -n /usr/local/bin/fortisplit-vpnctl --lang=xx start <config>
/// Скрипт разрешён в /etc/sudoers.d/fortisplit с NOPASSWD, поэтому GUI
/// не хранит и не спрашивает пароль. Это единственная доверенная граница.
///
/// Сами файлы конфигов правятся без root — см. ConfigStore.
/// Все completion-и вызываются на главной очереди.
final class VPNController: ObservableObject {
    @Published var state: VPNState = .disconnected
    @Published var detail: String = ""
    @Published var lastError: String = ""

    @Published var configs: [String] = []
    @Published var activeConfig: String = ""

    let store = ConfigStore()

    private let vpnctl = "/usr/local/bin/fortisplit-vpnctl"
    /// sudo вычищает окружение, поэтому LANG до скрипта может не доехать —
    /// передаём язык, который macOS выбрала для самого приложения, явным флагом.
    private let langFlag = "--lang=" +
        ((Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("ru") ? "ru" : "en")
    private var timer: Timer?
    /// Момент запуска `start`: если через несколько секунд туннеля так и нет,
    /// openfortivpn умер (пароль, сертификат) — вытаскиваем причину из лога.
    private var connectStartedAt: Date?

    init() {
        try? store.ensureDirectory()
        reloadConfigs()

        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        // .common, иначе опрос замирает ровно тогда, когда открыто меню
        // (run loop уходит в .eventTracking).
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refreshStatus()
    }

    // MARK: - Конфиги

    func reloadConfigs() {
        configs = store.names()
        let active = store.activeName()
        // активным мог остаться удалённый конфиг — тогда берём первый доступный
        if configs.contains(active) {
            activeConfig = active
        } else if let first = configs.first {
            activeConfig = first
            try? store.setActive(first)
        } else {
            activeConfig = ""
        }
    }

    func setActive(_ name: String) {
        do {
            try store.setActive(name)
            activeConfig = name
            lastError = ""
        } catch {
            lastError = String(format: NSLocalizedString("could not select config: %@", comment: "error"),
                               error.localizedDescription)
        }
    }

    // MARK: - Подключение

    func connect() {
        guard !activeConfig.isEmpty else {
            state = .error
            detail = NSLocalizedString("no configs — create or import one", comment: "menu status detail")
            return
        }
        let config = store.configURL(activeConfig)
        state = .connecting
        lastError = ""
        run(["start", config.path]) { [weak self] r in
            guard let self else { return }
            if r.status != 0 {
                self.state = .error
                self.detail = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
                self.lastError = r.output
                return
            }
            self.connectStartedAt = Date()
            self.refreshStatus()
        }
    }

    func disconnect() {
        connectStartedAt = nil
        run(["stop"]) { [weak self] _ in self?.refreshStatus() }
    }

    /// Проложить подсети на поднятый ppp-интерфейс. Зовётся, когда туннель
    /// только что поднялся, и после правки списка. Повторный вызов безвреден:
    /// уже проложенный маршрут просто не добавится второй раз.
    func applyRoutes(_ name: String, completion: @escaping (Bool) -> Void) {
        let routes = store.routesURL(name)
        // список мог ни разу не сохраняться — vpnctl ждёт существующий файл
        if !FileManager.default.fileExists(atPath: routes.path) {
            try? store.writeRoutes(name, "")
        }
        run(["apply-routes", routes.path]) { [weak self] r in
            self?.lastError = r.status == 0 ? "" : r.output.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(r.status == 0)
        }
    }

    func refreshStatus() {
        run(["status"]) { [weak self] r in
            guard let self else { return }
            let previous = self.state

            if r.status != 0 && r.output.contains("sudo") {
                self.state = .error
                self.detail = NSLocalizedString("sudoers is not configured — run install.sh",
                                                comment: "menu status detail")
                return
            }

            let parts = r.output.split(separator: "\t", maxSplits: 1).map { String($0) }
            let raw = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let s = VPNState(rawValue: raw) ?? .disconnected
            let d = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""

            if let started = self.connectStartedAt {
                switch s {
                case .connected:
                    self.connectStartedAt = nil
                case .disconnected where Date().timeIntervalSince(started) > 6:
                    // процесс не дожил до туннеля — показываем, на чём он упал
                    self.connectStartedAt = nil
                    self.state = .error
                    self.detail = NSLocalizedString("could not connect", comment: "menu status detail")
                    self.loadFailureReason()
                    return
                case .disconnected:
                    self.state = .connecting
                    return
                default:
                    break
                }
            }

            self.state = s
            self.detail = d

            // Туннель только что поднялся — самое время разложить подсети.
            // Раньше это делал хук pppd; теперь маршруты ставит vpnctl, и
            // повод для этого даёт переход статуса.
            if s == .connected && previous != .connected && !self.activeConfig.isEmpty {
                self.applyRoutes(self.activeConfig) { _ in }
            }
        }
    }

    /// Последняя содержательная строка лога — обычно там и есть причина отказа.
    private func loadFailureReason() {
        run(["logs"]) { [weak self] r in
            guard let self else { return }
            self.lastError = r.output
            let lines = r.output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if let last = lines.last {
                self.detail = String(last.prefix(120))
            }
        }
    }

    func openLogs() {
        run(["logs"]) { r in
            // Показываем логи в TextEdit через временный файл.
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("fortisplit-log.txt")
            try? r.output.write(to: tmp, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(tmp)
        }
    }

    // MARK: - Запуск процесса

    struct RunResult { let status: Int32; let output: String }

    private func run(_ args: [String], completion: @escaping (RunResult) -> Void) {
        let vpnctl = self.vpnctl
        let lang = self.langFlag
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            p.arguments = ["-n", vpnctl, lang] + args

            let outPipe = Pipe()
            p.standardOutput = outPipe
            p.standardError  = outPipe

            let result: RunResult
            do {
                try p.run()
                // читаем до EOF и только потом ждём выхода — иначе труба
                // переполнится и процесс встанет
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                result = RunResult(status: p.terminationStatus,
                                   output: String(data: data, encoding: .utf8) ?? "")
            } catch {
                result = RunResult(
                    status: 1,
                    output: String(format: NSLocalizedString("Could not run sudo/vpnctl: %@", comment: "error"),
                                   error.localizedDescription))
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
