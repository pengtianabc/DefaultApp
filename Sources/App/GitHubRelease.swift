import AppKit
import Foundation

/// 查询 GitHub 仓库最新版本，工具栏据此展示版本入口。
/// 仓库为私有时 API 返回 404——静默降级为纯仓库链接，不影响使用。
@MainActor
@Observable
final class GitHubRelease {
    static let shared = GitHubRelease()

    let repoURL = URL(string: "https://github.com/pengtianabc/DefaultApp")!

    /// 最新 release/tag（如 "v1.0.0"）；拿不到时为空。
    private(set) var latestTag: String?
    /// 有新版本（高于本应用版本）。
    private(set) var isNewer = false

    private var started = false

    private init() {}

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
            guard let tag = await requestTag(endpoint) else { continue }
            apply(tag: tag)
            return
        }
    }

    /// 依次尝试把响应当作 release 对象 / tag 数组解析，取出版本名。
    private func requestTag(_ endpoint: String) async -> String? {
        guard let url = URL(string: endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        if let obj = json as? [String: Any] {
            return (obj["tag_name"] as? String) ?? (obj["name"] as? String)
        }
        if let arr = json as? [[String: Any]] {
            return arr.first?["name"] as? String
        }
        return nil
    }

    private func apply(tag: String) {
        let cleaned = tag.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return }
        latestTag = cleaned
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        isNewer = Self.compare(Self.numbers(cleaned), Self.numbers(current)) > 0
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
