import Foundation

/// 应用内语言环境：支持跟随系统 / English / 简体中文，可实时切换。
@MainActor
@Observable
final class I18n {

    enum Lang: String, CaseIterable, Identifiable {
        case system
        case en
        case zh

        var id: String { rawValue }
    }

    enum Key: String {
        case sidebarTitle
        case searchPlaceholder
        case filterAll, filterUser, filterSystem
        case noMatch
        case quickAddButton
        case categoryAll, categoryDocument, categoryCode, categoryImage, categoryVideo
        case categoryAudio, categoryEmail, categoryArchive, categoryOther
        case selectedCount, addSelected, addedBatch, nothingNew, alreadyAdded, clearSelection
        case addPlaceholder, add, remove
        case emptyExtTitle, emptyExtDesc
        case noSelectionTitle, noSelectionDesc
        case refresh
        case statusWelcome, statusInvalid, statusExists, statusAdded, statusRemoved
        case statusReloaded, statusLoaded, statusSetOk, statusSetFail
        case extSuffixLabel
        case currentBadge
        case sourceUser, sourceSystem
        case sourceUserTip, sourceSystemTip
        case showInFinder
        case noDefaultTitle, noDefaultDesc
        case roleLabel, roleViewer, roleEditor, roleAll
        case roleHintViewer, roleHintEditor, roleHintAll
        case candidatesTitle, candidatesEmpty
        case chooseApp, setDefault
        case alertTitle, alertMsgGeneric, alertMsgBundleID, ok
        case languageLabel, followSystem
    }

    static let shared = I18n()

    var lang: Lang {
        didSet { UserDefaults.standard.set(lang.rawValue, forKey: "app.lang") }
    }

    /// 最近一条状态消息是否表示操作成功（用于状态栏着色）。
    private(set) var statusIsSuccess = false

    private init() {
        lang = Lang(rawValue: UserDefaults.standard.string(forKey: "app.lang") ?? "") ?? .system
    }

    var resolved: Lang {
        if lang != .system { return lang }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zh : .en
    }

    func t(_ key: Key, _ args: CVarArg...) -> String {
        let template = table[key]?[resolved] ?? table[key]?[.en] ?? key.rawValue
        guard !args.isEmpty else { return template }
        // %@ 期望对象参数：全部转为 String，避免 Int 等值类型被当作指针解引用导致崩溃。
        let safeArgs = args.map { String(describing: $0) }
        return String(format: template, arguments: safeArgs)
    }

    func roleTitle(_ role: HandlerRole) -> String {
        switch role {
        case .viewer: return t(.roleViewer)
        case .editor: return t(.roleEditor)
        case .all: return t(.roleAll)
        }
    }

    func categoryTitle(_ category: ExtCategory) -> String {
        switch category {
        case .all: return t(.categoryAll)
        case .document: return t(.categoryDocument)
        case .code: return t(.categoryCode)
        case .image: return t(.categoryImage)
        case .video: return t(.categoryVideo)
        case .audio: return t(.categoryAudio)
        case .email: return t(.categoryEmail)
        case .archive: return t(.categoryArchive)
        case .other: return t(.categoryOther)
        }
    }

    func markStatus(success: Bool) {
        statusIsSuccess = success
    }

    private let table: [Key: [Lang: String]] = [
        .sidebarTitle: [.zh: "文件后缀", .en: "File Extensions"],
        .searchPlaceholder: [.zh: "搜索后缀或应用名", .en: "Search extensions or apps"],
        .filterAll: [.zh: "全部", .en: "All"],
        .filterUser: [.zh: "用户配置", .en: "Custom"],
        .filterSystem: [.zh: "系统默认", .en: "System"],
        .noMatch: [.zh: "无匹配结果", .en: "No matches"],
        .quickAddButton: [.zh: "添加常用后缀", .en: "Add Common Extensions…"],
        .categoryAll: [.zh: "全部", .en: "All"],
        .categoryDocument: [.zh: "文档", .en: "Documents"],
        .categoryCode: [.zh: "代码", .en: "Code"],
        .categoryImage: [.zh: "图片", .en: "Images"],
        .categoryVideo: [.zh: "视频", .en: "Video"],
        .categoryAudio: [.zh: "音频", .en: "Audio"],
        .categoryEmail: [.zh: "邮件", .en: "Email"],
        .categoryArchive: [.zh: "压缩", .en: "Archives"],
        .categoryOther: [.zh: "其他", .en: "Other"],
        .selectedCount: [.zh: "已选 %@ 项", .en: "%@ selected"],
        .addSelected: [.zh: "批量添加 (%@)", .en: "Add (%@)"],
        .addedBatch: [.zh: "已添加 %@ 个后缀。", .en: "Added %@ extensions."],
        .nothingNew: [.zh: "没有可添加的新后缀。", .en: "Nothing new to add."],
        .alreadyAdded: [.zh: "已添加", .en: "Added"],
        .clearSelection: [.zh: "清空", .en: "Clear"],
        .addPlaceholder: [.zh: "输入后缀，如 txt", .en: "Type an extension, e.g. txt"],
        .add: [.zh: "添加", .en: "Add"],
        .remove: [.zh: "删除", .en: "Remove"],
        .emptyExtTitle: [.zh: "暂无文件后缀", .en: "No Extensions Yet"],
        .emptyExtDesc: [.zh: "在下方输入任意后缀，或点击「添加常用后缀」按分类批量添加。支持任意文件格式。", .en: "Type any extension below, or use “Add Common Extensions…” to batch-add by category. Any file format is supported."],
        .noSelectionTitle: [.zh: "未选择文件后缀", .en: "No Extension Selected"],
        .noSelectionDesc: [.zh: "在左侧添加或选择一个文件后缀，即可查看并修改它的默认打开应用。", .en: "Add or select a file extension on the left to view or change its default app."],
        .refresh: [.zh: "刷新", .en: "Refresh"],
        .statusWelcome: [.zh: "请输入文件后缀开始管理默认打开方式。", .en: "Add a file extension to start managing default apps."],
        .statusInvalid: [.zh: "无效的后缀：%@", .en: "Invalid extension: %@"],
        .statusExists: [.zh: "%@ 已在列表中。", .en: "%@ is already in the list."],
        .statusAdded: [.zh: "已添加 %@。", .en: "Added %@."],
        .statusRemoved: [.zh: "已删除 %@。", .en: "Removed %@."],
        .statusReloaded: [.zh: "已从 LaunchServices 重新加载。", .en: "Reloaded from LaunchServices."],
        .statusLoaded: [.zh: "已加载 %@ 个文件后缀。", .en: "Loaded %@ extensions."],
        .statusSetOk: [.zh: "已将 %@ 的默认打开方式设为「%@」。", .en: "Set %@ to open with “%@”."],
        .statusSetFail: [.zh: "设置失败：无法将 %@ 设为 %@ 的默认打开方式。", .en: "Failed to set %@ as the default for %@."],
        .extSuffixLabel: [.zh: "文件后缀", .en: "FILE EXTENSION"],
        .currentBadge: [.zh: "当前默认", .en: "CURRENT"],
        .sourceUser: [.zh: "用户配置", .en: "CUSTOM"],
        .sourceSystem: [.zh: "系统默认", .en: "SYSTEM"],
        .sourceUserTip: [.zh: "该打开方式由用户显式设置（存储于 LaunchServices 用户偏好）", .en: "This handler was set explicitly by the user (stored in LaunchServices user preferences)"],
        .sourceSystemTip: [.zh: "该打开方式来自系统或应用安装时的声明，并非用户设置", .en: "This handler comes from the system or an app's declared defaults, not a user setting"],
        .showInFinder: [.zh: "在访达中显示", .en: "Show in Finder"],
        .noDefaultTitle: [.zh: "尚未设置默认应用", .en: "No Default App"],
        .noDefaultDesc: [.zh: "尚未为 %@ 设置默认打开方式，当前显示的是系统按应用声明推断的结果。你可以从下方列表选择任意应用设为默认。", .en: "No explicit default for %@ — macOS is inferring one from app declarations. Pick any app below to make it the default."],
        .roleLabel: [.zh: "注册角色", .en: "Register As"],
        .roleViewer: [.zh: "查看", .en: "Viewer"],
        .roleEditor: [.zh: "编辑", .en: "Editor"],
        .roleAll: [.zh: "全部", .en: "All"],
        .roleHintViewer: [.zh: "双击打开文件时使用", .en: "Used when you double-click the file"],
        .roleHintEditor: [.zh: "其他应用请求编辑器时使用", .en: "Used when apps ask for an editor"],
        .roleHintAll: [.zh: "同时设置查看与编辑角色", .en: "Sets both viewer and editor roles"],
        .candidatesTitle: [.zh: "可打开 %@ 的应用", .en: "Apps that can open %@"],
        .candidatesEmpty: [.zh: "没有应用声明支持 %@，仍可在下方手动选择任意应用。本工具支持任意后缀，并非仅限常见格式。", .en: "No installed app declares support for %@. You can still pick any app below — any extension is supported, not just common ones."],
        .chooseApp: [.zh: "选择其他应用…", .en: "Choose Another App…"],
        .setDefault: [.zh: "设为默认打开方式", .en: "Set as Default"],
        .alertTitle: [.zh: "无法设置默认应用", .en: "Cannot Set Default App"],
        .alertMsgGeneric: [.zh: "LaunchServices 拒绝了此次更改，请确认所选应用可以打开此类文件后重试。", .en: "LaunchServices rejected the change. Make sure the selected app can open this file type and try again."],
        .alertMsgBundleID: [.zh: "无法读取 %@ 的 Bundle ID。", .en: "Could not read the bundle identifier of %@."],
        .ok: [.zh: "好", .en: "OK"],
        .languageLabel: [.zh: "语言", .en: "Language"],
        .followSystem: [.zh: "跟随系统", .en: "System"],
    ]
}
