import AppKit
import CoreServices
import UniformTypeIdentifiers

/// The LaunchServices role a handler is registered for.
enum HandlerRole: String, CaseIterable, Identifiable {
    case viewer
    case editor
    case all

    var id: String { rawValue }
}

/// A macOS application identified by bundle ID, with resolved name/icon/url.
struct AppInfo: Identifiable, Hashable {
    let bundleID: String
    var url: URL?
    var name: String
    var icon: NSImage?

    var id: String { bundleID }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.bundleID == rhs.bundleID }
    func hash(into hasher: inout Hasher) { hasher.combine(bundleID) }
}

/// 解析 LaunchServices 用户覆盖库，用于区分「用户配置」与「系统默认」。
///
/// 用户通过 Finder「显示简介 → 全部更改」、本工具或 duti 设置的默认打开方式，
/// 都会写入 `~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist`
/// 的 LSHandlers 数组；没有对应记录时，当前处理器即来自系统/应用声明的默认值。
enum UserOverrides {

    struct Snapshot {
        var extensions: Set<String> = []
        var utis: Set<String> = []
    }

    private static let path = NSHomeDirectory()
        + "/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"

    static func load() -> Snapshot {
        var snapshot = Snapshot()
        guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let handlers = dict["LSHandlers"] as? [[String: Any]] else {
            return snapshot
        }
        for handler in handlers {
            // URL scheme（http/https/ssh…）与文件类型无关，跳过。
            if handler["LSHandlerURLScheme"] != nil { continue }
            if let tagClass = handler["LSHandlerContentTagClass"] as? String,
               tagClass == "public.filename-extension",
               let tag = handler["LSHandlerContentTag"] as? String {
                snapshot.extensions.insert(tag.lowercased())
            }
            if let uti = handler["LSHandlerContentType"] as? String {
                snapshot.utis.insert(uti)
            }
        }
        return snapshot
    }

    /// 指定 UTI 的「所有角色」(LSHandlerRoleAll) 槽位持有者。
    /// 某些应用（如 WorkBuddy）会只抢占这个槽位，导致它与其他角色注册不一致。
    static func roleAllHandler(forUTI uti: String) -> String? {
        guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let handlers = dict["LSHandlers"] as? [[String: Any]] else {
            return nil
        }
        for handler in handlers where (handler["LSHandlerContentType"] as? String) == uti {
            if let bid = handler["LSHandlerRoleAll"] as? String {
                return bid
            }
        }
        return nil
    }
}

@MainActor
enum LaunchServices {

    /// Resolve a filename extension (dots and case ignored) to its UTI.
    static func uti(forExtension ext: String) -> String? {
        let cleaned = ext.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
        guard !cleaned.isEmpty else { return nil }
        return UTType(tag: cleaned, tagClass: .filenameExtension, conformingTo: nil)?.identifier
    }

    /// Current default handler bundle id, trying viewer then editor then any role.
    static func defaultHandlerBundleID(forExtension ext: String) -> String? {
        guard let uti = uti(forExtension: ext) else { return nil }
        for role: LSRolesMask in [.viewer, .editor, .all] {
            if let bid = LSCopyDefaultRoleHandlerForContentType(uti as CFString, role)?.takeRetainedValue() as String? {
                return bid
            }
        }
        return nil
    }

    static func defaultHandler(forExtension ext: String) -> AppInfo? {
        guard let bid = defaultHandlerBundleID(forExtension: ext) else { return nil }
        return appInfo(forBundleID: bid)
    }

    /// 与双击行为一致的默认打开应用解析（临时文件 + NSWorkspace）。
    /// 注意：此路径与 LSCopyDefaultRoleHandlerForContentType 可能不一致——
    /// 真实打开以此为准。
    static func actualDefault(forExtension ext: String) -> AppInfo? {
        guard !ext.isEmpty else { return nil }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()
            + "defaultapp-probe-\(UUID().uuidString).\(ext)")
        try? Data().write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: tmp) else { return nil }
        guard let bid = Bundle(url: url)?.bundleIdentifier else { return nil }
        return appInfo(forBundleID: bid)
    }

    /// 角色注册值与真实打开值是否不一致。
    static func hasMismatch(forExtension ext: String) -> Bool {
        let role = defaultHandlerBundleID(forExtension: ext) ?? ""
        let actual = actualDefault(forExtension: ext)?.bundleID ?? ""
        return !actual.isEmpty && role != actual
    }

    /// All apps that declared they can handle the extension (editor + viewer roles,
    /// deduped, current default first if it exists).
    static func handlers(forExtension ext: String) -> [AppInfo] {
        guard let uti = uti(forExtension: ext) else { return [] }
        var bids: [String] = []
        for role: LSRolesMask in [.editor, .viewer] {
            let arr = LSCopyAllRoleHandlersForContentType(uti as CFString, role)?.takeRetainedValue() as? [String] ?? []
            for bid in arr where !bids.contains(bid) {
                bids.append(bid)
            }
        }
        if let cur = defaultHandlerBundleID(forExtension: ext), let idx = bids.firstIndex(of: cur) {
            bids.remove(at: idx)
            bids.insert(cur, at: 0)
        }
        return bids.map(appInfo(forBundleID:))
    }

    /// 设置默认打开方式。
    /// - `.all`：依次写入 查看 / 编辑 / 所有角色 三个槽位，确保任何解析路径
    ///   （访达双击、`open` 命令、其他应用请求）都得到同一结果，且能覆盖
    ///   只抢占了「所有角色」槽位的应用（如 WorkBuddy）。
    /// - 目标应用未在 Info.plist 声明该内容类型时（如 Edge 没有声明
    ///   `public.html`），LSSet API 会拒绝；此时回退到 macOS 12+ 的
    ///   NSWorkspace API（系统设置同款接口），它不做声明校验。
    @discardableResult
    static func setDefaultHandler(bundleID: String, forExtension ext: String, role: HandlerRole) -> Bool {
        guard let uti = uti(forExtension: ext) else { return false }
        let masks: [LSRolesMask]
        switch role {
        case .viewer: masks = [[.viewer]]
        case .editor: masks = [[.editor]]
        case .all: masks = [[.viewer], [.editor], [.all]]
        }
        var ok = true
        for mask in masks {
            let status = LSSetDefaultRoleHandlerForContentType(uti as CFString, mask, bundleID as CFString)
            if status != noErr { ok = false }
        }
        if ok { return true }
        guard role == .all else { return false }
        // 回退 1：NSWorkspace.setDefaultApplication（System Settings 同款接口）。
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let type = UTType(uti) {
            let semaphore = DispatchSemaphore(value: 0)
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type) { _ in semaphore.signal() }
            semaphore.wait()
        }
        // 回退 2：直接写入查看/编辑/所有角色三槽位覆盖记录。
        // NSWorkspace 对未声明该类型的应用只写 RoleAll 槽位，双击解析仍会被
        // 角色注册抢走（如 html 仍是 Safari），必须补齐 viewer/editor。
        return stampOverride(ext: ext, bundleID: bundleID)
    }

    /// 移除用户在 LaunchServices 中的覆盖记录，把默认打开方式交还给系统。
    /// 注意：LSSetDefaultRoleHandlerForContentType 传 NULL 在现代 macOS 返回
    /// paramErr（无法通过 API 清除），因此直接编辑
    /// com.apple.launchservices.secure.plist 的 LSHandlers 记录，
    /// 再重启 lsd / cfprefsd 使其重新加载。
    @discardableResult
    static func removeOverride(forExtension ext: String) -> Bool {
        guard let uti = uti(forExtension: ext) else { return false }
        guard var (dict, handlers) = readHandlers() else { return false }
        let before = handlers.count
        let lowered = ext.lowercased()
        handlers.removeAll { handler in
            if let tagClass = handler["LSHandlerContentTagClass"] as? String,
               tagClass == "public.filename-extension",
               let tag = handler["LSHandlerContentTag"] as? String {
                return tag.lowercased() == lowered
            }
            if let type = handler["LSHandlerContentType"] as? String {
                return type == uti
            }
            return false
        }
        guard handlers.count < before else { return true }  // 本无覆盖，视为成功
        dict["LSHandlers"] = handlers
        return writeHandlers(dict)
    }

    /// 直接写入 LSHandlers 覆盖记录（查看/编辑/所有角色三个槽位全部设置为
    /// 同一应用），用于 LSSet 与 NSWorkspace API 都搞不定的场景
    /// （目标应用未声明该内容类型，如 Edge 对 .html）。
    /// 条目格式与系统设置写入的一致。
    @discardableResult
    static func stampOverride(ext: String, bundleID: String) -> Bool {
        guard let uti = uti(forExtension: ext) else { return false }
        guard var (dict, handlers) = readHandlers() else { return false }
        let lowered = ext.lowercased()
        handlers.removeAll { handler in
            if let tagClass = handler["LSHandlerContentTagClass"] as? String,
               tagClass == "public.filename-extension",
               let tag = handler["LSHandlerContentTag"] as? String {
                return tag.lowercased() == lowered
            }
            if let type = handler["LSHandlerContentType"] as? String {
                return type == uti
            }
            return false
        }
        var entry: [String: Any] = [
            "LSHandlerRoleAll": bundleID,
            "LSHandlerRoleViewer": bundleID,
            "LSHandlerRoleEditor": bundleID,
            "LSHandlerPreferredVersions": [
                "LSHandlerRoleAll": "-",
                "LSHandlerRoleViewer": "-",
                "LSHandlerRoleEditor": "-",
            ],
        ]
        if uti.hasPrefix("dyn.") {
            entry["LSHandlerContentTagClass"] = "public.filename-extension"
            entry["LSHandlerContentTag"] = lowered
        } else {
            entry["LSHandlerContentType"] = uti
        }
        handlers.append(entry)
        dict["LSHandlers"] = handlers
        return writeHandlers(dict)
    }

    // MARK: - 用户覆盖表读写

    private static var lsPrefsPath: String {
        NSHomeDirectory() + "/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
    }

    private static func readHandlers() -> (dict: [String: Any], handlers: [[String: Any]])? {
        guard let raw = FileManager.default.contents(atPath: lsPrefsPath),
              var dict = (try? PropertyListSerialization.propertyList(from: raw, format: nil)) as? [String: Any],
              let handlers = dict["LSHandlers"] as? [[String: Any]] else {
            return nil
        }
        dict["LSHandlers"] = handlers
        return (dict, handlers)
    }

    /// 原子写回并重启 lsd / cfprefsd（launchd 会自动拉起，重新加载偏好）。
    /// 写回后校验一次：若守护进程在我们写入后把内存中的旧状态回写到磁盘
    /// （lsd 重启时的同步竞态），再写一遍并再次重启。
    private static func writeHandlers(_ dict: [String: Any]) -> Bool {
        guard let raw = FileManager.default.contents(atPath: lsPrefsPath) else { return false }
        let binary = raw.prefix(6).starts(with: [0x62, 0x70, 0x6C, 0x69, 0x73, 0x74]) // "bplist"
        let format: PropertyListSerialization.PropertyListFormat = binary ? .binary : .xml
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: format, options: 0) else {
            return false
        }
        func writeOnce() -> Bool {
            let tmp = "\(lsPrefsPath).tmp-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)"
            guard FileManager.default.createFile(atPath: tmp, contents: data) else { return false }
            try? FileManager.default.removeItem(atPath: lsPrefsPath)
            do {
                try FileManager.default.moveItem(atPath: tmp, toPath: lsPrefsPath)
            } catch {
                return false
            }
            restartDaemons()
            return true
        }
        guard writeOnce() else { return false }
        // 校验：守护进程可能在我们写入后把内存中的旧状态异步回写（lsd 的
        // 持久化有延迟，连续 set→unset 时尤其明显），发现被覆盖就重写，
        // 最多 3 次、每次间隔 1 秒，给 lsd 的写回窗口留足收敛时间。
        for attempt in 0..<3 {
            Thread.sleep(forTimeInterval: attempt == 0 ? 1.0 : 1.5)
            if let reread = FileManager.default.contents(atPath: lsPrefsPath), reread != data {
                guard writeOnce() else { return false }
            } else {
                return true
            }
        }
        return false
    }

    private static func restartDaemons() {
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        kill.arguments = ["-9", "lsd", "cfprefsd"]
        try? kill.run()
        kill.waitUntilExit()
    }

    /// 「所有角色」槽位的当前持有者（来自 LaunchServices 用户覆盖表）。
    static func roleAllClaimant(forExtension ext: String) -> AppInfo? {
        guard let uti = uti(forExtension: ext),
              let bid = UserOverrides.roleAllHandler(forUTI: uti) else { return nil }
        return appInfo(forBundleID: bid)
    }

    /// 用户覆盖表中该后缀任一角色槽位的持有者（覆盖表为磁盘上的事实来源，
    /// 可用于复核刚写入但本进程 LS 客户端缓存尚未刷新的场景）。
    static func overrideSlotHolder(forExtension ext: String) -> String? {
        guard let uti = uti(forExtension: ext),
              let (_, handlers) = readHandlers() else { return nil }
        let lowered = ext.lowercased()
        for handler in handlers {
            let matches: Bool
            if let tagClass = handler["LSHandlerContentTagClass"] as? String,
               tagClass == "public.filename-extension",
               let tag = handler["LSHandlerContentTag"] as? String {
                matches = tag.lowercased() == lowered
            } else if let type = handler["LSHandlerContentType"] as? String {
                matches = type == uti
            } else {
                matches = false
            }
            guard matches else { continue }
            for key in ["LSHandlerRoleAll", "LSHandlerRoleViewer", "LSHandlerRoleEditor"] {
                if let bid = handler[key] as? String { return bid }
            }
        }
        return nil
    }

    static func appInfo(forBundleID bid: String) -> AppInfo {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
        var name = bid
        if let url {
            if let bundle = Bundle(url: url) {
                name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? FileManager.default.displayName(atPath: url.path)
            } else {
                name = FileManager.default.displayName(atPath: url.path)
            }
        }
        let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        return AppInfo(bundleID: bid, url: url, name: name, icon: icon)
    }

    /// 把用户输入解析为 Bundle ID，支持三种形式：
    /// 1. 路径——指向 .app 本身或其内部任意位置（如 .../Cursor.app/Contents/MacOS/Cursor），
    ///    自动向上找到包根；支持 ~ 与相对路径。
    /// 2. Bundle ID——直接校验存在性。
    /// 3. 应用名——在 /Applications、/Applications/Utilities、/System/Applications、
    ///    ~/Applications 下按显示名 / CFBundleName 匹配（不区分大小写，须唯一）。
    static func resolveBundleID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // 1) 路径
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.hasPrefix(".") {
            var candidate = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
                .standardizedFileURL
            let fileManager = FileManager.default
            while candidate.path.count > 1 {
                if candidate.pathExtension == "app" || candidate.lastPathComponent == "app" {
                    if let bundle = Bundle(url: candidate), let bid = bundle.bundleIdentifier {
                        return bid
                    }
                }
                if fileManager.fileExists(atPath: candidate.appendingPathComponent("Info.plist").path),
                   let bundle = Bundle(url: candidate), let bid = bundle.bundleIdentifier {
                    return bid
                }
                if candidate.path == "/" { break }
                candidate = candidate.deletingLastPathComponent()
            }
            return nil
        }

        // 2) Bundle ID
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) != nil {
            return trimmed
        }

        // 3) 应用名
        let roots = ["/Applications", "/Applications/Utilities",
                     "/System/Applications", "/System/Applications/Utilities",
                     NSHomeDirectory() + "/Applications"]
        var matches: [String] = []
        for root in roots {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let path = root + "/" + entry
                guard let bundle = Bundle(path: path) else { continue }
                let display = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? entry
                if display.caseInsensitiveCompare(trimmed) == .orderedSame,
                   let bid = bundle.bundleIdentifier, !matches.contains(bid) {
                    matches.append(bid)
                }
            }
        }
        return matches.count == 1 ? matches.first : nil
    }

    /// 应用声明的文档类型（Info.plist CFBundleDocumentTypes / UT*TypeDeclarations）。
    /// 有 UTI 的返回 UTI，仅有扩展名的返回 ".ext" 形式；兼容现代
    /// UTTypeTagSpecification 与旧式 CFBundleTypeExtensions 两种声明。
    static func declaredTypes(forBundleID bid: String) -> [String] {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid),
              let bundle = Bundle(url: url) else { return [] }
        let plist: [String: Any] = bundle.infoDictionary ?? [:]
        var result: [String] = []
        var seen = Set<String>()
        func append(_ value: String) {
            guard !seen.contains(value) else { return }
            seen.insert(value)
            result.append(value)
        }
        for group in ["CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations"] {
            guard let types = plist[group] as? [[String: Any]] else { continue }
            for type in types {
                let uti = type["UTTypeIdentifier"] as? String
                var emittedExtension = false
                if let spec = type["UTTypeTagSpecification"] as? [String: Any] {
                    let raw = spec["public.filename-extension"]
                    let exts = (raw as? [String]) ?? ((raw as? String).map { [$0] } ?? [])
                    for e in exts {
                        emittedExtension = true
                        if let u = uti { append(u) } else { append(".\(e.lowercased())") }
                    }
                } else if let exts = (type["CFBundleTypeExtensions"] as? [String])
                            ?? ((type["CFBundleTypeExtensions"] as? String).map { [$0] }) {
                    // 旧式声明：没有 UTI，输出 .ext 形式
                    for e in exts {
                        emittedExtension = true
                        if let u = uti { append(u) } else { append(".\(e.lowercased())") }
                    }
                }
                if let u = uti, (!emittedExtension || type["LSItemContentTypes"] is [String]) {
                    append(u)
                }
            }
        }
        return result
    }
    // MARK: - URL Schemes（默认浏览器 https、默认邮件客户端 mailto 等）

    /// 当前处理指定协议的应用（与系统解析一致）。
    static func schemeDefaultHandler(_ scheme: String) -> AppInfo? {
        guard let url = URL(string: "\(scheme)://defaultapp-system-check") else { return nil }
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
              let bid = Bundle(url: appURL)?.bundleIdentifier else { return nil }
        return appInfo(forBundleID: bid)
    }

    /// 所有声明可处理该协议的应用，当前默认排最前。
    static func schemeHandlers(_ scheme: String) -> [AppInfo] {
        guard let url = URL(string: "\(scheme)://defaultapp-system-check") else { return [] }
        var bids: [String] = []
        for appURL in NSWorkspace.shared.urlsForApplications(toOpen: url) {
            if let bid = Bundle(url: appURL)?.bundleIdentifier, !bids.contains(bid) {
                bids.append(bid)
            }
        }
        if let cur = schemeDefaultHandler(scheme)?.bundleID, let idx = bids.firstIndex(of: cur) {
            bids.remove(at: idx)
            bids.insert(cur, at: 0)
        }
        return bids.map(appInfo(forBundleID:))
    }

    /// 设置协议的默认处理应用，三级回退（与文件类型同一思路）：
    /// LSSet API → NSWorkspace（系统设置同款）→ 直写覆盖记录。
    @discardableResult
    static func setSchemeHandler(bundleID: String, scheme: String) -> Bool {
        let status = LSSetDefaultHandlerForURLScheme(scheme as CFString, bundleID as CFString)
        if status == noErr { return true }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let semaphore = DispatchSemaphore(value: 0)
            var nsError: Error?
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) { error in
                nsError = error
                semaphore.signal()
            }
            semaphore.wait()
            if nsError == nil { return true }
        }
        return stampSchemeOverride(scheme: scheme, bundleID: bundleID)
    }

    /// 移除协议的默认处理设置，交还给系统。
    @discardableResult
    static func removeSchemeOverride(_ scheme: String) -> Bool {
        guard var (dict, handlers) = readHandlers() else { return false }
        let before = handlers.count
        handlers.removeAll { ($0["LSHandlerURLScheme"] as? String)?.lowercased() == scheme.lowercased() }
        guard handlers.count < before else { return true }
        dict["LSHandlers"] = handlers
        return writeHandlers(dict)
    }

    /// 直写协议覆盖记录（LSHandlerURLScheme 形式，与系统写入格式一致）。
    private static func stampSchemeOverride(scheme: String, bundleID: String) -> Bool {
        guard var (dict, handlers) = readHandlers() else { return false }
        handlers.removeAll { ($0["LSHandlerURLScheme"] as? String)?.lowercased() == scheme.lowercased() }
        handlers.append([
            "LSHandlerURLScheme": scheme,
            "LSHandlerRoleAll": bundleID,
            "LSHandlerPreferredVersions": ["LSHandlerRoleAll": "-"],
        ])
        dict["LSHandlers"] = handlers
        return writeHandlers(dict)
    }
    /// 动态发现所有已知协议：内置常见协议 + 已安装应用 CFBundleURLTypes 声明的 +
    /// 用户覆盖表中出现过的。不再依赖硬编码列表（代理协议 vmess/vless/trojan…
    /// 由各客户端自行声明，这里自动收集）。
    static func allKnownSchemes() -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        func append(_ raw: String) {
            let lower = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard !lower.isEmpty, !seen.contains(lower) else { return }
            seen.insert(lower)
            result.append(lower)
        }
        // 常见协议：即使当前没有应用声明也保留，便于先设置后装应用
        for scheme in ["https", "http", "mailto", "ftp", "ssh", "tel", "sms", "facetime", "facetime-audio"] {
            append(scheme)
        }
        // 已安装应用声明的
        for scheme in declaredSchemesFromApps() { append(scheme) }
        // 用户覆盖表里的（含已卸载应用的历史记录）
        if let (_, handlers) = readHandlers() {
            for handler in handlers {
                if let scheme = handler["LSHandlerURLScheme"] as? String { append(scheme) }
            }
        }
        return result
    }

    /// 扫描 /Applications、Utilities、/System/Applications、~/Applications 下所有
    /// .app 的 CFBundleURLTypes，返回去重排序后的协议列表。
    private static func declaredSchemesFromApps() -> [String] {
        let roots = ["/Applications", "/Applications/Utilities",
                     "/System/Applications", "/System/Applications/Utilities",
                     NSHomeDirectory() + "/Applications"]
        var seen = Set<String>()
        var out: [String] = []
        for root in roots {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                guard let plist = Bundle(path: root + "/" + entry)?.infoDictionary else { continue }
                for type in (plist["CFBundleURLTypes"] as? [[String: Any]]) ?? [] {
                    for scheme in (type["CFBundleURLSchemes"] as? [String]) ?? [] {
                        let lower = scheme.lowercased()
                        guard !lower.isEmpty, !seen.contains(lower) else { continue }
                        seen.insert(lower)
                        out.append(lower)
                    }
                }
            }
        }
        return out.sorted()
    }
}
