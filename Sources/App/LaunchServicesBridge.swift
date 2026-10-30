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
        return ok
    }

    /// 移除用户在 LaunchServices 中的覆盖记录，把默认打开方式交还给系统。
    /// 注意：LSSetDefaultRoleHandlerForContentType 传 NULL 在现代 macOS 返回
    /// paramErr（无法通过 API 清除），因此直接编辑
    /// com.apple.launchservices.secure.plist 的 LSHandlers 记录，
    /// 再重启 lsd / cfprefsd 使其重新加载。
    @discardableResult
    static func removeOverride(forExtension ext: String) -> Bool {
        guard let uti = uti(forExtension: ext) else { return false }
        let path = NSHomeDirectory()
            + "/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
        guard let raw = FileManager.default.contents(atPath: path),
              var dict = (try? PropertyListSerialization.propertyList(from: raw, format: nil)) as? [String: Any],
              var handlers = dict["LSHandlers"] as? [[String: Any]] else {
            return false
        }
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
        let binary = raw.prefix(6).starts(with: [0x62, 0x70, 0x6C, 0x69, 0x73, 0x74]) // "bplist"
        let format: PropertyListSerialization.PropertyListFormat = binary ? .binary : .xml
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: format, options: 0) else {
            return false
        }
        // 原子写回：先写临时文件再 rename 覆盖
        let tmp = "\(path).tmp-\(ProcessInfo.processInfo.processIdentifier)"
        guard FileManager.default.createFile(atPath: tmp, contents: data) else { return false }
        try? FileManager.default.removeItem(atPath: path)
        do {
            try FileManager.default.moveItem(atPath: tmp, toPath: path)
        } catch {
            return false
        }
        // 重启缓存该偏好的守护进程（launchd 会自动拉起）
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        kill.arguments = ["-9", "lsd", "cfprefsd"]
        try? kill.run()
        kill.waitUntilExit()
        return true
    }

    /// 「所有角色」槽位的当前持有者（来自 LaunchServices 用户覆盖表）。
    static func roleAllClaimant(forExtension ext: String) -> AppInfo? {
        guard let uti = uti(forExtension: ext),
              let bid = UserOverrides.roleAllHandler(forUTI: uti) else { return nil }
        return appInfo(forBundleID: bid)
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
}
