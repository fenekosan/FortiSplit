import Foundation

/// Конфиги и списки маршрутов лежат у пользователя в ~/.config/fortisplit и
/// правятся обычным FileManager — root для этого не нужен. Привилегии нужны
/// только чтобы запустить openfortivpn и проложить маршруты, этим занимается
/// VPNController через vpnctl.
///
///   <имя>.config   конфиг openfortivpn (0600, в нём пароль)
///   <имя>.routes   подсети этого конфига
///   active         имя выбранного конфига
struct ConfigStore {
    let root: URL

    init() {
        root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/fortisplit", isDirectory: true)
    }

    /// Заготовка нового конфига. Комментарии переводятся — файл читает человек,
    /// а не openfortivpn.
    static var template: String {
        """
        host = vpn.example.com
        port = 443
        username =
        password =

        # \(NSLocalizedString("Split tunnel: the gateway must not push routes or DNS — the app lays the routes down itself.", comment: "config template comment"))
        set-routes = 0
        set-dns = 0

        # \(NSLocalizedString("On the first connection openfortivpn prints the gateway certificate hash — paste it here to trust that gateway.", comment: "config template comment"))
        # trusted-cert = <sha256>
        """
    }

    static var routesTemplate: String {
        "# " + NSLocalizedString("Subnets to send through the tunnel — one CIDR per line, e.g. 10.0.0.0/8.",
                                 comment: "routes template comment") + "\n"
    }

    // MARK: - Пути

    func configURL(_ name: String) -> URL { root.appendingPathComponent("\(name).config") }
    func routesURL(_ name: String) -> URL { root.appendingPathComponent("\(name).routes") }
    private var activeURL: URL { root.appendingPathComponent("active") }

    func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }

    // MARK: - Список и активный

    func names() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return files
            .filter { $0.hasSuffix(".config") }
            .map { String($0.dropLast(".config".count)) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    func activeName() -> String {
        let raw = (try? String(contentsOf: activeURL, encoding: .utf8)) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setActive(_ name: String) throws {
        try ensureDirectory()
        try (name + "\n").write(to: activeURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Чтение и запись

    func readConfig(_ name: String) -> String {
        guard !name.isEmpty else { return "" }
        return (try? String(contentsOf: configURL(name), encoding: .utf8)) ?? ""
    }

    func writeConfig(_ name: String, _ text: String) throws {
        try ensureDirectory()
        let url = configURL(name)
        try normalized(text).write(to: url, atomically: true, encoding: .utf8)
        // пароль лежит здесь открытым текстом — прячем от остальных пользователей
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func readRoutes(_ name: String) -> String {
        guard !name.isEmpty else { return "" }
        return (try? String(contentsOf: routesURL(name), encoding: .utf8)) ?? ""
    }

    func writeRoutes(_ name: String, _ text: String) throws {
        try ensureDirectory()
        try normalized(text).write(to: routesURL(name), atomically: true, encoding: .utf8)
    }

    func delete(_ name: String) throws {
        try? FileManager.default.removeItem(at: routesURL(name))
        try FileManager.default.removeItem(at: configURL(name))
    }

    /// Записываем файл как нормальный текстовый: без \r и с переводом строки
    /// в конце — иначе `while read` в хуке потерял бы последнюю подсеть.
    private func normalized(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: "\r", with: "")
        return clean.hasSuffix("\n") || clean.isEmpty ? clean : clean + "\n"
    }

    // MARK: - Проверки

    /// Имя становится частью имени файла — оставляем только безопасный алфавит.
    static func sanitize(_ raw: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        let cleaned = String(raw.filter { allowed.contains($0) })
        return String(cleaned.drop(while: { $0 == "." }).prefix(64))
    }

    /// Строки, которые не являются ни пустыми, ни комментарием, ни IPv4-CIDR.
    /// vpnctl проверит их ещё раз у себя, но лучше сказать об ошибке сразу.
    static func invalidRouteLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .filter { $0.range(of: #"^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$"#,
                               options: .regularExpression) == nil }
    }
}
