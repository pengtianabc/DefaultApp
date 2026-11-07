import SwiftUI

/// 「检查更新」弹出面板：版本对比结论 + 一键下载安装进度。
/// 触发点在工具栏 GitHub 按钮，状态全部来自 GitHubRelease.shared。
struct UpdatePanel: View {
    @Environment(I18n.self) private var i18n
    @Environment(\.dismiss) private var dismiss

    private let release = GitHubRelease.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            stateContent
        }
        .frame(width: 380)
        .padding(18)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("DefaultApp").font(.headline)
                Text(i18n.t(.updateCurrent, release.currentVersion))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - 状态区

    @ViewBuilder
    private var stateContent: some View {
        switch release.status {
        case .updateAvailable(let info):
            updateAvailable(info)
        case .unknown:
            unknownView
        case .uptodate(let tag):
            upToDateView(tag)
        case .dev(let tag):
            devView(tag)
        }
    }

    // MARK: - 有新版本

    private func updateAvailable(_ info: GitHubRelease.ReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.orange)
                Text(i18n.t(.updateFound, info.tag))
                    .font(.title3.bold())
            }
            metaLine(info)
            notesView(info.notes)
            installArea(info)
        }
    }

    private func metaLine(_ info: GitHubRelease.ReleaseInfo) -> some View {
        HStack(spacing: 10) {
            if let date = info.published {
                Label(Self.dateString(date), systemImage: "calendar")
            }
            if info.size > 0 {
                Label(Self.byteString(info.size), systemImage: "arrow.down.circle")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func notesView(_ notes: String) -> some View {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return Group {
            if !trimmed.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(i18n.t(.updateNotes)).font(.caption.weight(.semibold))
                    ScrollView {
                        Text(trimmed)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: 140, alignment: .top)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.separator.opacity(0.5))
                    )
                }
            }
        }
    }

    // MARK: - 安装区（按钮 / 进度 / 失败重试）

    @ViewBuilder
    private func installArea(_ info: GitHubRelease.ReleaseInfo) -> some View {
        switch release.phase {
        case .idle:
            HStack {
                Button(i18n.t(.updateLater)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(i18n.t(.visitGitHub)) { release.visit() }
                Button(i18n.t(.updateInstall, info.tag)) {
                    release.downloadAndInstall(info)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        case .downloading(let received, let total):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: total > 0 ? Double(received) / Double(total) : nil)
                Text(i18n.t(.updateDownloading, Self.byteString(received), total > 0 ? Self.byteString(total) : "…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(i18n.t(.updateInstalling))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(i18n.t(.updateFailed, message), systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(i18n.t(.updateLater)) {
                        release.resetInstall()
                        dismiss()
                    }
                    Spacer()
                    Button(i18n.t(.updateRetry)) { release.resetInstall() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    // MARK: - 其他状态

    private var unknownView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(i18n.t(.updateUnknown), systemImage: "questionmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(i18n.t(.visitGitHub)) { release.visit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func upToDateView(_ tag: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(i18n.t(.updateUpToDate, tag), systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
            HStack {
                Spacer()
                Button(i18n.t(.visitGitHub)) { release.visit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func devView(_ tag: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(i18n.t(.updateDev, release.currentVersion, tag), systemImage: "hammer.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.purple)
                .fixedSize(horizontal: false, vertical: true)
            Text(i18n.t(.updateDevDesc))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(i18n.t(.visitGitHub)) { release.visit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - 格式化

    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func byteString(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }
}
