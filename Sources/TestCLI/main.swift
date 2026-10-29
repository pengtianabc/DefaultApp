import Foundation

// Test harness for the LaunchServices bridge.
// Usage:
//   lsctl get <ext>
//   lsctl list <ext>
//   lsctl set <ext> <bundleID> [viewer|editor|all]

@MainActor
func run() -> Int32 {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        FileHandle.standardError.write(Data("usage: lsctl <get|list|set> <ext> [bundleID] [viewer|editor|all]\n".utf8))
        return 2
    }

    switch args[1] {
    case "get":
        guard args.count >= 3 else {
            FileHandle.standardError.write(Data("usage: lsctl get <ext>\n".utf8))
            return 2
        }
        guard let uti = LaunchServices.uti(forExtension: args[2]) else {
            print("no UTI for '\(args[2])'")
            return 1
        }
        print("uti: \(uti)")
        if let app = LaunchServices.defaultHandler(forExtension: args[2]) {
            print("default: \(app.name) [\(app.bundleID)] \(app.url?.path ?? "")")
            return 0
        }
        print("default: (none)")
        return 0

    case "list":
        guard args.count >= 3 else {
            FileHandle.standardError.write(Data("usage: lsctl list <ext>\n".utf8))
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
            FileHandle.standardError.write(Data("usage: lsctl set <ext> <bundleID> [viewer|editor|all]\n".utf8))
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
