import Foundation

// defaultapp — DefaultApp 的命令行工具（与 App 共用同一 LaunchServices 封装）。
// Usage:
//   defaultapp get <ext>
//   defaultapp list <ext>
//   defaultapp set <ext> <bundleID> [viewer|editor|all]
//   defaultapp check

@MainActor
func run() -> Int32 {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        FileHandle.standardError.write(Data("usage: defaultapp <get|list|set|check> <ext> [bundleID] [viewer|editor|all]\n".utf8))
        return 2
    }

    switch args[1] {
    case "get":
        guard args.count >= 3 else {
            FileHandle.standardError.write(Data("usage: defaultapp get <ext>\n".utf8))
            return 2
        }
        guard let uti = LaunchServices.uti(forExtension: args[2]) else {
            print("no UTI for '\(args[2])'")
            return 1
        }
        print("uti: \(uti)")
        if let app = LaunchServices.actualDefault(forExtension: args[2]) {
            print("actual-open(default): \(app.name) [\(app.bundleID)] \(app.url?.path ?? "")")
        } else {
            print("actual-open(default): (none)")
        }
        if let app = LaunchServices.defaultHandler(forExtension: args[2]) {
            print("role-query: \(app.name) [\(app.bundleID)]")
        } else {
            print("role-query: (none)")
        }
        if LaunchServices.hasMismatch(forExtension: args[2]) {
            print("⚠️ MISMATCH: 双击实际打开与角色注册不一致")
        }
        return 0

    case "check":
        // 扫描后缀目录，列出「角色注册 ≠ 双击实际打开」的后缀
        let catalog = ExtensionCatalog.extensions(for: .all)
        var count = 0
        for ext in catalog {
            guard let uti = LaunchServices.uti(forExtension: ext) else { continue }
            let role = LaunchServices.defaultHandler(forExtension: ext)
            let actual = LaunchServices.actualDefault(forExtension: ext)
            if role?.bundleID != actual?.bundleID {
                count += 1
                print(".\(ext)\trole=\(role?.bundleID ?? "(none)")\topen=\(actual?.bundleID ?? "(none)")")
            }
        }
        print("-- \(count) 个不一致 / \(catalog.count)")
        return 0

    case "list":
        guard args.count >= 3 else {
            FileHandle.standardError.write(Data("usage: defaultapp list <ext>\n".utf8))
            return 2
        }
        let apps = LaunchServices.handlers(forExtension: args[2])
        for app in apps {
            print("\(app.bundleID)\t\(app.name)")
        }
        print("-- \(apps.count) app(s)")
        return 0

    case "set":
        guard args.count >= 4 else {
            FileHandle.standardError.write(Data("usage: defaultapp set <ext> <bundleID> [viewer|editor|all]\n".utf8))
            return 2
        }
        let role = HandlerRole(rawValue: args.count >= 5 ? args[4] : "all") ?? .all
        let ok = LaunchServices.setDefaultHandler(bundleID: args[3], forExtension: args[2], role: role)
        print(ok ? "ok" : "failed")
        return ok ? 0 : 1

    default:
        FileHandle.standardError.write(Data("unknown command '\(args[1])'\n".utf8))
        return 2
    }
}

exit(MainActor.assumeIsolated { run() })
