import AppKit
import CoreServices
import UniformTypeIdentifiers

/// The LaunchServices role a handler is registered for.
enum HandlerRole: String, CaseIterable, Identifiable {
    case viewer
    case editor
    case all

    var id: String { rawValue }

    var lsMask: LSRolesMask {
        switch self {
        case .viewer: return .viewer
        case .editor: return .editor
        case .all: return [.viewer, .editor]
        }
    }
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

    @discardableResult
    static func setDefaultHandler(bundleID: String, forExtension ext: String, role: HandlerRole) -> Bool {
        guard let uti = uti(forExtension: ext) else { return false }
        let status = LSSetDefaultRoleHandlerForContentType(uti as CFString, role.lsMask, bundleID as CFString)
        return status == noErr
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
}
