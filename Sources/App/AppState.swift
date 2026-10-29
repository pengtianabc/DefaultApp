import Foundation

/// 默认打开方式的来源：无默认 / 用户显式配置 / 系统（应用声明）默认。
enum SourceKind {
    case none
    case user
    case system
}

@MainActor
@Observable
final class AppState {

    struct Entry: Identifiable, Hashable, Codable {
        var id: UUID
        var ext: String
    }

    /// 首次启动预置的后缀列表：覆盖常用分类，让用户一打开就能看到
    /// 一批真实存在的默认打开方式（也直观说明任意格式都支持）。
    /// 仅在首次运行时写入一次；用户清空后不会再次出现。
    static let starterExtensions: [String] = [
        // 文档
        "txt", "md", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "csv", "rtf", "pages", "epub",
        // 代码
        "json", "xml", "html", "css", "js", "ts", "py", "java", "c", "cpp",
        "h", "swift", "go", "sh", "yaml", "sql", "log",
        // 图片
        "png", "jpg", "jpeg", "gif", "bmp", "svg", "webp", "heic", "psd",
        // 视频 / 音频
        "mp4", "mov", "mkv", "avi", "webm", "mp3", "wav", "flac", "m4a",
        // 邮件 / 压缩
        "eml", "msg", "ics", "vcf",
        "zip", "rar", "7z", "tar", "gz", "dmg", "iso",
    ]

    var entries: [Entry] = []
    var selectedID: Entry.ID?
    var statusMessage: String {
        didSet { I18n.shared.markStatus(success: false) }
    }
    /// Bumped by the Refresh button so detail views re-query LaunchServices.
    var refreshToken = UUID()

    /// LaunchServices 用户覆盖表快照（用于区分用户配置 / 系统默认）。
    private(set) var userOverrides = UserOverrides.Snapshot()
    /// 本工具设置过的后缀（补充信息源，覆盖 plist 读取失败的情况）。
    private var ownSet: Set<String>

    private let storeKey = "entries.v1"
    private let ownSetKey = "ownSet.v1"
    private let didSeedKey = "didSeed.v1"

    private var i18n: I18n { I18n.shared }

    init() {
        ownSet = Set(UserDefaults.standard.stringArray(forKey: ownSetKey) ?? [])
        statusMessage = I18n.shared.t(.statusWelcome)
        userOverrides = UserOverrides.load()
        load()
    }

    // MARK: - 增删

    func addExtension(_ raw: String) {
        let cleaned = Self.sanitize(raw)
        guard !cleaned.isEmpty else {
            setStatus(i18n.t(.statusInvalid, raw), success: false)
            return
        }
        if let existing = entries.first(where: { $0.ext == cleaned }) {
            selectedID = existing.id
            setStatus(i18n.t(.statusExists, ".\(cleaned)"), success: false)
            return
        }
        insert([cleaned])
        setStatus(i18n.t(.statusAdded, ".\(cleaned)"), success: true)
    }

    /// 批量添加（常用后缀面板），返回实际新增数量。
    @discardableResult
    func addExtensions(_ raws: [String]) -> Int {
        let cleaned = raws.map(Self.sanitize).filter { !$0.isEmpty }
        let fresh = cleaned.filter { ext in !entries.contains(where: { $0.ext == ext }) }
        insert(fresh)
        if fresh.isEmpty {
            setStatus(i18n.t(.nothingNew), success: false)
        } else {
            setStatus(i18n.t(.addedBatch, fresh.count), success: true)
        }
        return fresh.count
    }

    private func insert(_ exts: [String]) {
        guard !exts.isEmpty else { return }
        entries.append(contentsOf: exts.map { Entry(id: UUID(), ext: $0) })
        entries.sort { $0.ext.localizedCaseInsensitiveCompare($1.ext) == .orderedAscending }
        selectedID = entries.last(where: { exts.contains($0.ext) })?.id
        save()
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        if selectedID == entry.id { selectedID = entries.first?.id }
        save()
        setStatus(i18n.t(.statusRemoved, ".\(entry.ext)"), success: true)
    }

    // MARK: - 查询

    func refresh() {
        userOverrides = UserOverrides.load()
        refreshToken = UUID()
        setStatus(i18n.t(.statusReloaded), success: true)
    }

    func currentDefault(for ext: String) -> AppInfo? {
        LaunchServices.defaultHandler(forExtension: ext)
    }

    func candidates(for ext: String) -> [AppInfo] {
        LaunchServices.handlers(forExtension: ext)
    }

    /// 默认打开方式的来源。优先看 LaunchServices 用户覆盖表，
    /// 其次看本工具自己设置过的记录。
    func source(for ext: String) -> SourceKind {
        guard currentDefault(for: ext) != nil else { return .none }
        let lowered = ext.lowercased()
        if userOverrides.extensions.contains(lowered) || ownSet.contains(lowered) {
            return .user
        }
        if let uti = LaunchServices.uti(forExtension: ext), userOverrides.utis.contains(uti) {
            return .user
        }
        return .system
    }

    // MARK: - 设置

    func setDefault(bundleID: String, for ext: String, role: HandlerRole) -> Bool {
        let ok = LaunchServices.setDefaultHandler(bundleID: bundleID, forExtension: ext, role: role)
        let appName = LaunchServices.appInfo(forBundleID: bundleID).name
        if ok {
            ownSet.insert(ext.lowercased())
            UserDefaults.standard.set(Array(ownSet), forKey: ownSetKey)
            userOverrides = UserOverrides.load()
            setStatus(i18n.t(.statusSetOk, ".\(ext)", appName), success: true)
        } else {
            setStatus(i18n.t(.statusSetFail, appName, ".\(ext)"), success: false)
        }
        return ok
    }

    // MARK: - 工具

    static func sanitize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private func setStatus(_ message: String, success: Bool) {
        statusMessage = message
        I18n.shared.markStatus(success: success)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
            selectedID = saved.first?.id
            setStatus(i18n.t(.statusLoaded, saved.count), success: true)
            return
        }
        // 首次运行：写入一次预置列表（已有记录或已预置过则跳过）。
        guard !UserDefaults.standard.bool(forKey: didSeedKey) else { return }
        UserDefaults.standard.set(true, forKey: didSeedKey)
        entries = Self.starterExtensions
            .map { Entry(id: UUID(), ext: $0) }
            .sorted { $0.ext.localizedCaseInsensitiveCompare($1.ext) == .orderedAscending }
        selectedID = entries.first?.id
        save()
        setStatus(i18n.t(.statusLoaded, entries.count), success: true)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }
}
