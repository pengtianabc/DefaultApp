import CoreServices
import Foundation

// defaultapp — DefaultApp 的命令行工具（与 App 共用同一 LaunchServices 封装）。
// 版本与 App 保持一致（build.sh 中的 CFBundleShortVersionString）。
let CLIVersion = "1.0"

// MARK: - 终端样式（仅 TTY 输出时着色；尊重 NO_COLOR）

enum Term {
    static let isTTY = isatty(STDOUT_FILENO) != 0
    static let colorEnabled = isTTY && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    static func wrap(_ code: String, _ s: String) -> String {
        colorEnabled ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s
    }
    static func bold(_ s: String) -> String { wrap("1", s) }
    static func dim(_ s: String) -> String { wrap("2", s) }
    static func green(_ s: String) -> String { wrap("32", s) }
    static func yellow(_ s: String) -> String { wrap("33", s) }
    static func red(_ s: String) -> String { wrap("31", s) }
    static func cyan(_ s: String) -> String { wrap("36", s) }
}

func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

@MainActor func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(Term.red("error:")) \(message)\n".utf8))
    exit(1)
}

// MARK: - 帮助

let helpText = """
\(Term.bold("defaultapp")) \(CLIVersion) — manage which app opens each file extension on macOS

\(Term.bold("USAGE"))
  defaultapp <command> [arguments] [options]

\(Term.bold("COMMANDS"))
  \(Term.cyan("get")) <ext>                 Show what opens an extension: double-click resolution,
                            role registration and the all-roles slot, side by side
  \(Term.cyan("list")) <ext>                List every app that declared it can open an extension
  \(Term.cyan("set")) <ext> <app>           Make an app the default opener — <app> can be
                            an app name ("Cursor"), a bundle id, or a path
                            (/Applications/Cursor.app); default role: all
           [--role viewer|editor|all]
  \(Term.cyan("unset")) <ext>               Remove your override; hand the choice back to macOS
  \(Term.cyan("check"))                     Scan all common extensions for registration mismatches
  \(Term.cyan("version"))                   Print version
  \(Term.cyan("help"))                      Show this help

\(Term.bold("OPTIONS"))
  --json                    Machine-readable output (get / list / check)
  -h, --help                Show help

\(Term.bold("EXAMPLES"))
  defaultapp get md
  defaultapp set md Cursor
  defaultapp unset md
  defaultapp check --json

<ext> is an extension without the dot (md, png, ...). Any extension works —
macOS resolves it to a UTI automatically.
"""

// MARK: - 参数解析

struct Arguments {
    var command = ""
    var positional: [String] = []
    var role: HandlerRole = .all
    var json = false
    var help = false
}

@MainActor func parseArguments(_ argv: [String]) -> Arguments {
    var args = Arguments()
    var index = 0
    while index < argv.count {
        let token = argv[index]
        switch token {
        case "--json":
            args.json = true
        case "-h", "--help", "help":
            args.help = true
            if token == "help" && args.command.isEmpty { args.command = "help" }
        case "--role":
            index += 1
            guard index < argv.count, let role = HandlerRole(rawValue: argv[index]) else {
                fail("--role expects viewer, editor or all")
            }
            args.role = role
        default:
            if token.hasPrefix("--") {
                fail("unknown option \(token) (see: defaultapp help)")
            }
            if args.command.isEmpty {
                args.command = token
            } else {
                args.positional.append(token)
            }
        }
        index += 1
    }
    // 兼容旧写法：set <ext> <bundle> [role] 的位置角色参数
    if args.command == "set", args.positional.count >= 3,
       let legacy = HandlerRole(rawValue: args.positional[2]) {
        args.role = legacy
        args.positional.remove(at: 2)
    }
    return args
}

// MARK: - JSON 输出

func printJSON(_ object: Any) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
          let text = String(data: data, encoding: .utf8) else { return }
    print(text)
}

func appDict(_ app: AppInfo?, isDefault: Bool = false) -> [String: Any] {
    var dict: [String: Any] = [
        "name": app?.name ?? NSNull(),
        "bundleID": app?.bundleID ?? NSNull(),
        "path": app?.url?.path ?? NSNull(),
    ]
    dict["isDefault"] = isDefault
    return dict
}

// MARK: - 子命令

@MainActor func commandGet(_ ext: String, json: Bool) -> Int32 {
    guard let uti = LaunchServices.uti(forExtension: ext) else {
        fail("'\(ext)' is not a valid extension")
    }
    let cleaned = ext.lowercased()
    let actual = LaunchServices.actualDefault(forExtension: cleaned)
    let role = LaunchServices.defaultHandler(forExtension: cleaned)
    let roleAll = LaunchServices.roleAllClaimant(forExtension: cleaned)
    let override = UserOverrides.load()
    let source = (override.extensions.contains(cleaned) || override.utis.contains(uti)) ? "user" : "system"
    let mismatch = (role?.bundleID ?? "") != (actual?.bundleID ?? "")

    if json {
        printJSON([
            "extension": cleaned,
            "uti": uti,
            "doubleClickOpens": appDict(actual),
            "roleRegistration": appDict(role),
            "allRolesSlot": roleAll?.bundleID ?? NSNull(),
            "source": source,
            "mismatch": mismatch,
        ])
        return mismatch ? 1 : 0
    }

    let title = Term.bold(".\(cleaned)") + Term.dim("  (\(uti))")
    print(title)
    print()
    var rows: [(String, String, String)] = [
        ("Double-click opens", actual?.name ?? "—", actual?.bundleID ?? Term.dim("no app resolves this yet")),
    ]
    if let role {
        rows.append(("Role registration", role.name, role.bundleID))
    }
    if let roleAll, roleAll.bundleID != role?.bundleID {
        rows.append(("All-roles slot", roleAll.name, Term.yellow(roleAll.bundleID)))
    }
    rows.append(("Source", source == "user" ? Term.green("user override") : "system default",
                 source == "user" ? "~/Library/Preferences/...launchservices.secure.plist" : "inferred from app declarations"))
    let labelWidth = rows.map { $0.0.count }.max()! + 3
    for (label, name, detail) in rows {
        print("  \(Term.dim(pad(label, labelWidth)))\(Term.bold(name))  \(Term.dim(detail))")
    }
    if mismatch {
        print()
        print("  " + Term.yellow("⚠ MISMATCH") + "  role registration points to \(role?.name ?? "—"), but a double-click opens \(actual?.name ?? "—").")
        print("  " + Term.dim("Fix: defaultapp set \(cleaned) <bundle-id>"))
        return 1
    }
    return 0
}

@MainActor func commandList(_ ext: String, json: Bool) -> Int32 {
    let cleaned = ext.lowercased()
    guard LaunchServices.uti(forExtension: cleaned) != nil else {
        fail("'\(ext)' is not a valid extension")
    }
    let apps = LaunchServices.handlers(forExtension: cleaned)
    let current = LaunchServices.actualDefault(forExtension: cleaned)?.bundleID

    if json {
        printJSON(apps.map { appDict($0, isDefault: $0.bundleID == current) })
        return 0
    }
    guard !apps.isEmpty else {
        print(Term.dim("No installed app declares it can open .\(cleaned)."))
        print(Term.dim("You can still assign one: defaultapp set \(cleaned) \"App Name\" — name or bundle id"))
        return 0
    }
    print(Term.bold(".\(cleaned)") + Term.dim("  — \(apps.count) app(s) can open it") + (current == nil ? "" : Term.dim(", * = current default")))
    print()
    // 名字为主列，Bundle ID 为灰色次要列
    let nameWidth = min(apps.map { $0.name.count }.max()!, 30) + 3
    for (index, app) in apps.enumerated() {
        let isDefault = app.bundleID == current
        let marker = isDefault ? Term.green("*") : Term.dim(" ")
        // 先对纯文本补白再上色：ANSI 转义序列不算显示宽度
        let name = isDefault ? Term.bold(pad(app.name, nameWidth)) : pad(app.name, nameWidth)
        let id = isDefault ? Term.green(app.bundleID) : Term.dim(app.bundleID)
        print(" \(marker) \(pad("\(index + 1).", 4))\(name)\(id)")
    }
    return 0
}

@MainActor func commandSet(_ ext: String, appRef: String, role: HandlerRole) -> Int32 {
    let cleaned = ext.lowercased()
    guard LaunchServices.uti(forExtension: cleaned) != nil else {
        fail("'\(ext)' is not a valid extension")
    }
    // 接受应用名或 Bundle ID；名字自动解析
    guard let bundleID = LaunchServices.resolveBundleID(appRef) else {
        fail("'\(appRef)' is not an app path, app name or bundle id — see defaultapp list \(cleaned) for candidates")
    }
    let target = LaunchServices.appInfo(forBundleID: bundleID)
    let before = LaunchServices.actualDefault(forExtension: cleaned)
    guard LaunchServices.setDefaultHandler(bundleID: bundleID, forExtension: cleaned, role: role) else {
        fail("LaunchServices rejected the change for .\(cleaned)")
    }
    let after = LaunchServices.actualDefault(forExtension: cleaned)
    let roleText = role == .all ? "all roles" : "\(role.rawValue) role"

    print(Term.bold(".\(cleaned)") + Term.dim("  (\(roleText))"))
    print("  \(Term.dim("before"))  \(before?.name ?? "—")")
    print("  \(Term.dim("after "))  \(Term.bold(target.name))  \(Term.dim(target.bundleID))")
    if after?.bundleID == bundleID {
        print("  " + Term.green("✔ verified") + Term.dim(" — double-click now resolves to \(target.name), effective immediately"))
        return 0
    }
    print("  " + Term.yellow("⚠ written, but double-click still resolves to \(after?.name ?? "—")") + Term.dim(" — another app may be overriding it"))
    return 1
}

@MainActor func commandUnset(_ ext: String) -> Int32 {
    let cleaned = ext.lowercased()
    guard LaunchServices.uti(forExtension: cleaned) != nil else {
        fail("'\(ext)' is not a valid extension")
    }
    guard LaunchServices.removeOverride(forExtension: cleaned) else {
        fail("could not remove the override for .\(cleaned)")
    }
    let fallback = LaunchServices.actualDefault(forExtension: cleaned)
    print(Term.bold(".\(cleaned)") + "  " + Term.green("✔ override removed") + Term.dim(" — handed back to macOS"))
    if let fallback {
        print(Term.dim("  System now resolves double-click to: \(fallback.name) (\(fallback.bundleID))"))
    } else {
        print(Term.dim("  No app resolves this extension yet."))
    }
    return 0
}

@MainActor func commandCheck(json: Bool) -> Int32 {
    let catalog = ExtensionCatalog.extensions(for: .all)
    var mismatches: [(ext: String, role: AppInfo?, actual: AppInfo?)] = []
    for ext in catalog {
        guard LaunchServices.uti(forExtension: ext) != nil else { continue }
        let role = LaunchServices.defaultHandler(forExtension: ext)
        let actual = LaunchServices.actualDefault(forExtension: ext)
        if role?.bundleID != actual?.bundleID {
            mismatches.append((ext, role, actual))
        }
    }

    if json {
        printJSON([
            "scanned": catalog.count,
            "mismatchCount": mismatches.count,
            "mismatches": mismatches.map {
                [
                    "extension": $0.ext,
                    "roleRegistration": appDict($0.role),
                    "doubleClickOpens": appDict($0.actual),
                ] as [String: Any]
            },
        ])
        return mismatches.isEmpty ? 0 : 1
    }

    if mismatches.isEmpty {
        print(Term.green("✔ all clear") + Term.dim(" — \(catalog.count) extensions checked, registration matches double-click everywhere"))
        return 0
    }
    print(Term.yellow("⚠ \(mismatches.count) mismatch(es)") + Term.dim(" out of \(catalog.count) common extensions:\n"))
    let extWidth = mismatches.map { $0.ext.count }.max()! + 4
    for item in mismatches {
        print("  \(pad(".\(item.ext)", extWidth))"
              + Term.dim("role ") + "\(item.role?.name ?? "—")"
              + Term.dim("  ≠ double-click ") + "\(item.actual?.name ?? "—")")
    }
    print()
    print(Term.dim("Re-set them to stamp all three roles: defaultapp set <ext> \"App Name\""))
    return 1
}

// MARK: - 入口

@MainActor
func run() -> Int32 {
    let args = parseArguments(Array(CommandLine.arguments.dropFirst()))

    if args.help || args.command.isEmpty || args.command == "help" {
        print(helpText)
        return args.command.isEmpty && !args.help ? 2 : 0
    }

    switch args.command {
    case "get":
        guard let ext = args.positional.first else { fail("usage: defaultapp get <ext>") }
        return commandGet(ext, json: args.json)
    case "list":
        guard let ext = args.positional.first else { fail("usage: defaultapp list <ext>") }
        return commandList(ext, json: args.json)
    case "set":
        guard args.positional.count >= 2 else { fail("usage: defaultapp set <ext> <app> [--role viewer|editor|all]\n  <app>: app name (\"Cursor\"), bundle id, or path (/Applications/Cursor.app)") }
        return commandSet(args.positional[0], appRef: args.positional[1], role: args.role)
    case "unset":
        guard let ext = args.positional.first else { fail("usage: defaultapp unset <ext>") }
        return commandUnset(ext)
    case "check":
        return commandCheck(json: args.json)
    case "version", "--version", "-v":
        print("defaultapp \(CLIVersion)")
        return 0
    default:
        fail("unknown command '\(args.command)' (see: defaultapp help)")
    }
}

exit(MainActor.assumeIsolated { run() })
