import AppKit
import Foundation

/// 查询 GitHub 仓库最新版本，工具栏据此展示版本入口。
/// 仓库为私有时 API 返回 404——静默降级为纯仓库链接，不影响使用。
@MainActor
@Observable
final class GitHubRelease {
    static let shared = GitHubRelease()

    let repoURL = URL(string: "https://github.com/pengtianabc/DefaultApp")!

    struct ReleaseInfo: Equatable {
        let tag: String
        let htmlURL: URL
        let dmgURL: URL
        let notes: String
        let published: Date?
        let size: Int64
    }

    /// 版本对比结论。
    enum Status: Equatable {
        case unknown          // 尚未拿到结果（或网络失败）
        case uptodate(String) // 已是最新（参数：远程 tag）
        case updateAvailable(ReleaseInfo)
        case dev(String)      // 本地为开发版本，高于线上（参数：远程 tag）
    }

    /// 一键更新的安装阶段。
    enum InstallPhase: Equatable {
        case idle
        case downloading(received: Int64, total: Int64)
        case installing
        case failed(String)
    }

    /// 最新 release/tag（如 "v1.0.0"）；拿不到时为空。
    private(set) var latestTag: String?
    /// 有新版本（高于本应用版本）。
    private(set) var isNewer = false
    private(set) var status: Status = .unknown
    private(set) var phase: InstallPhase = .idle

    private var started = false
    private var installTask: Task<Void, Never>?

    private init() {}

    /// 当前应用版本号。
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// 应用启动后调用一次即可；结果通过 @Observable 推送到界面。
    func check() {
        guard !started else { return }
        started = true
        Task { await fetchLatest() }
    }

    /// 打开仓库页面。
    func visit() {
        NSWorkspace.shared.open(repoURL)
    }

    // MARK: - 获取

    private func fetchLatest() async {
        let endpoints = [
            "https://api.github.com/repos/pengtianabc/DefaultApp/releases/latest",
            "https://api.github.com/repos/pengtianabc/DefaultApp/tags?per_page=1",
        ]
        for endpoint in endpoints {
            guard let (tag, info) = await requestRelease(endpoint) else { continue }
            apply(tag: tag, info: info)
            return
        }
    }

    /// 依次尝试把响应当作 release 对象 / tag 数组解析，取出版本与下载信息。
    private func requestRelease(_ endpoint: String) async -> (String, ReleaseInfo?)? {
        guard let url = URL(string: endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return nil }

        if let obj = json as? [String: Any] {
            guard let tag = (obj["tag_name"] as? String) ?? (obj["name"] as? String) else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            var dmgURL: URL?
            var size: Int64 = 0
            if let assets = obj["assets"] as? [[String: Any]] {
                for asset in assets where (asset["name"] as? String) == "DefaultApp.dmg" {
                    if let s = asset["browser_download_url"] as? String { dmgURL = URL(string: s) }
                    size = asset["size"] as? Int64 ?? 0
                }
            }
            let info = ReleaseInfo(
                tag: tag,
                htmlURL: (obj["html_url"] as? String).flatMap(URL.init(string:)) ?? repoURL,
                dmgURL: dmgURL ?? repoURL.appendingPathComponent("releases/latest"),
                notes: obj["body"] as? String ?? "",
                published: (obj["published_at"] as? String).flatMap(formatter.date(from:)),
                size: size
            )
            return (tag, info)
        }
        if let arr = json as? [[String: Any]], let tag = arr.first?["name"] as? String {
            return (tag, nil)
        }
        return nil
    }

    private func apply(tag: String, info: ReleaseInfo?) {
        let cleaned = tag.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return }
        latestTag = cleaned
        let current = currentVersion
        let order = Self.compare(Self.numbers(cleaned), Self.numbers(current))
        isNewer = order > 0
        if isNewer, let info {
            status = .updateAvailable(info)
        } else if order < 0 {
            status = .dev(cleaned)
        } else {
            status = .uptodate(cleaned)
        }
    }

    // MARK: - 一键更新

    /// 下载 release 中的 DefaultApp.dmg 并交给自助安装脚本替换当前应用。
    func downloadAndInstall(_ info: ReleaseInfo) {
        guard phase == .idle || (phase.isFailed) else { return }
        phase = .downloading(received: 0, total: info.size)
        installTask = Task {
            do {
                let dmg = try await SelfUpdate.download(info, progress: { [weak self] received, total in
                    Task { @MainActor in
                        self?.phase = .downloading(received: received, total: total)
                    }
                })
                phase = .installing
                try await Task.sleep(for: .milliseconds(400))
                SelfUpdate.installReplacingCurrentApp(dmg: dmg)
                NSApp.terminate(nil)
            } catch {
                phase = .failed(String(describing: error))
            }
        }
    }

    /// 取消失败状态，允许重试。
    func resetInstall() {
        if phase.isFailed { phase = .idle }
    }

    // MARK: - 版本比较

    /// 提取版本数字："v1.2.0" → [1, 2, 0]。
    static func numbers(_ string: String) -> [Int] {
        string.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    /// 逐位比较，不足位补 0：[1,0] 与 [1,0,0] 视为相同。
    static func compare(_ a: [Int], _ b: [Int]) -> Int {
        let count = max(a.count, b.count)
        for index in 0..<count {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}

extension GitHubRelease.InstallPhase {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    /// 下载进度 0...1；总量未知时返回 received 的字节数展示即可。
    var progressText: (fraction: Double?, received: Int64, total: Int64) {
        switch self {
        case .downloading(let received, let total):
            let fraction = total > 0 ? Double(received) / Double(total) : nil
            return (fraction, received, total)
        default:
            return (nil, 0, 0)
        }
    }
}

// MARK: - 自助更新（下载 + 脚本替换安装）

/// 与界面无关的更新原语：下载 release DMG，派生一个独立 shell 脚本
/// 在当前应用退出后替换它并重新打开。独立进程是必须的——应用不能替换正在运行中的自己。
enum SelfUpdate {
    /// 下载到 ~/Library/Caches/<bundle>/updates/ 下，文件名带版本号避免串包。
    static func download(
        _ info: GitHubRelease.ReleaseInfo,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: info.dmgURL)
        let total = response.expectedContentLength > 0 ? response.expectedContentLength : info.size

        let dir = cacheDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = info.dmgURL.lastPathComponent.isEmpty ? "DefaultApp.dmg" : info.dmgURL.lastPathComponent
        let dest = dir.appendingPathComponent("\(info.tag)-\(name)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }

        var received: Int64 = 0
        var lastReport: Int64 = 0
        for try await byte in bytes {
            try handle.write(contentsOf: [byte])
            received += 1
            if received - lastReport >= 64 * 1024 || (total > 0 && received == total) {
                lastReport = received
                progress(received, total)
            }
        }
        try handle.close()
        progress(received, total)
        return dest
    }

    /// 生成安装脚本并作为独立进程启动。脚本先等本进程退出，再替换应用。
    /// 失败时脚本自身会清理；错误信息不回流（进程已退出），重试路径在 UI 层。
    static func installReplacingCurrentApp(dmg: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let target = Bundle.main.bundleURL.path
        let script = self.script(dmg: dmg.path, target: target, pid: pid)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("defaultapp-update-\(UUID().uuidString.prefix(6)).sh")
        try? script.write(to: tmp, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [tmp.path]
        try? process.run()
    }

    /// 安装脚本：等待宿主退出 → 挂载 DMG → 原位替换（不可写则落到 ~/Applications）
    /// → 去除隔离属性（等价 Homebrew 行为，避免自更新后被 Gatekeeper 拦截）→ 重新打开。
    /// 提取为独立函数，便于构建期用同一份代码做端到端验证。
    static func script(dmg: String, target: String, pid: Int32) -> String {
        """
        #!/bin/sh
        set -u
        DMG='\(dmg)'
        TARGET='\(target)'
        PID='\(pid)'

        # 1. 等宿主退出（最多 30 秒，防僵死）
        i=0
        while kill -0 "$PID" 2>/dev/null; do
            sleep 0.2
            i=$((i+1))
            [ $i -ge 150 ] && exit 1
        done

        # 2. 校验 DMG 并挂载到临时目录
        MNT=$(mktemp -d /tmp/defaultapp-update-mount.XXXXXX)
        [ -f "$DMG" ] || exit 2
        hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$DMG" || exit 3
        [ -d "$MNT/DefaultApp.app" ] || { hdiutil detach -quiet "$MNT"; exit 4; }

        # 3. 选择安装目录：原位不可写则落到 ~/Applications
        DEST_DIR=$(dirname "$TARGET")
        APP_NAME=$(basename "$TARGET")
        if [ ! -w "$DEST_DIR" ]; then
            DEST_DIR="$HOME/Applications"
            APP_NAME="DefaultApp.app"
            mkdir -p "$DEST_DIR"
        fi

        # 4. 暂存拷贝 → 去隔离 → 原子替换
        STAGED="$DEST_DIR/.$APP_NAME.update"
        rm -rf "$STAGED"
        ditto "$MNT/DefaultApp.app" "$STAGED" || { hdiutil detach -quiet "$MNT"; exit 5; }
        xattr -dr com.apple.quarantine "$STAGED" 2>/dev/null

        # 5. 替换旧版本并重新打开
        rm -rf "$DEST_DIR/$APP_NAME"
        mv "$STAGED" "$DEST_DIR/$APP_NAME"
        hdiutil detach -quiet "$MNT"
        rm -rf "$MNT"
        rm -f "$DMG" "$0"
        open "$DEST_DIR/$APP_NAME"
        """
    }

    private static func cacheDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/\(Bundle.main.bundleIdentifier ?? "DefaultApp")/updates")
    }
}
