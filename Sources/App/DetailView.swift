import AppKit
import SwiftUI

struct DetailView: View {
    let entry: AppState.Entry
    @Environment(AppState.self) private var state
    @Environment(I18n.self) private var i18n

    @State private var role: HandlerRole = .all
    @State private var current: AppInfo?
    @State private var roleBased: AppInfo?
    @State private var roleAll: AppInfo?
    @State private var candidates: [AppInfo] = []
    @State private var errorMessage: String?
    @State private var toast: Toast?

    private var taskID: String {
        "\(entry.id.uuidString)-\(state.refreshToken.uuidString)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            rolePicker
            candidatesSection
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.smooth, value: entry.id)
        .task(id: taskID) { await reload() }
        .alert(
            i18n.t(.alertTitle),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { _ in errorMessage = nil }
            )
        ) {
            Button(i18n.t(.ok)) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .overlay(alignment: .bottom) { toastOverlay }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast {
            ToastView(toast: toast)
                .padding(.bottom, 14)
        }
    }

    private func showToast(_ newToast: Toast) {
        withAnimation(.snappy) { toast = newToast }
        let id = newToast.id
        Task {
            try? await Task.sleep(for: .seconds(4))
            if toast?.id == id {
                withAnimation(.snappy) { toast = nil }
            }
        }
    }

    // MARK: - 当前默认

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(i18n.t(.extSuffixLabel))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(".\(entry.ext)")
                    .textSelection(.enabled)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: ExtPalette.gradient(for: entry.ext),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .shadow(
                        color: ExtPalette.gradient(for: entry.ext).first?.opacity(0.4) ?? .clear,
                        radius: 6,
                        y: 3
                    )
            }

            if let current {
                currentCard(app: current)
            } else {
                noDefaultHint
            }

            if let roleBased, let current, roleBased.bundleID != current.bundleID {
                mismatchBanner(roleApp: roleBased)
            }

            // 「所有角色」槽位被第三方应用（如 WorkBuddy）抢占时的提示
            if let roleAll, let current,
               roleAll.bundleID != current.bundleID,
               roleAll.bundleID != roleBased?.bundleID {
                Label {
                    Text(i18n.t(.mismatchRoleAll, roleAll.name))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(.red.opacity(0.08)))
            }
        }
    }

    private func mismatchBanner(roleApp: AppInfo) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(i18n.t(.mismatchWarning, roleApp.name))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.1)))
    }

    private func currentCard(app: AppInfo) -> some View {
        HStack(spacing: 14) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.name).font(.title3.bold())
                    Text(i18n.t(.currentBadge))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.green.opacity(0.2)))
                    sourceBadge
                }
                Text(app.bundleID)
                    .textSelection(.enabled)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let url = app.url {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label(i18n.t(.showInFinder), systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.5))
        }
    }

    @ViewBuilder
    private var sourceBadge: some View {
        switch state.source(for: entry.ext) {
        case .user:
            Text(i18n.t(.sourceUser))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.blue))
                .help(i18n.t(.sourceUserTip))
        case .system:
            Text(i18n.t(.sourceSystem))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.quaternary.opacity(0.6)))
                .help(i18n.t(.sourceSystemTip))
        case .none:
            EmptyView()
        }
    }

    private var noDefaultHint: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(i18n.t(.noDefaultTitle)).font(.headline)
                Text(i18n.t(.noDefaultDesc, ".\(entry.ext)"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.08)))
    }

    // MARK: - 注册角色

    private var rolePicker: some View {
        HStack(spacing: 12) {
            Label(i18n.t(.roleLabel), systemImage: "checkmark.shield")
                .font(.headline)
            Picker("", selection: $role) {
                ForEach(HandlerRole.allCases) { Text(i18n.roleTitle($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            Text(roleHint)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var roleHint: String {
        switch role {
        case .viewer: return i18n.t(.roleHintViewer)
        case .editor: return i18n.t(.roleHintEditor)
        case .all: return i18n.t(.roleHintAll)
        }
    }

    // MARK: - 候选应用

    private var candidatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(i18n.t(.candidatesTitle, ".\(entry.ext)"))
                    .font(.headline)
                if !candidates.isEmpty {
                    Text("\(candidates.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.secondary.opacity(0.15)))
                }
                Spacer()
                Button { chooseApp() } label: {
                    Label(i18n.t(.chooseApp), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if candidates.isEmpty {
                Text(i18n.t(.candidatesEmpty, ".\(entry.ext)"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
            } else {
                List {
                    ForEach(candidates) { app in
                        ActionCandidateRow(
                            app: app,
                            isCurrent: app.bundleID == current?.bundleID,
                            onPreview: { preview(app) },
                            onSetDefault: { apply(app) }
                        )
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 180, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.6)))
                .animation(.default, value: candidates.count)
            }
        }
    }

    // MARK: - 行内操作

    /// 临时打开：在临时目录生成测试文件并用目标应用打开，完全不修改默认设置。
    private func preview(_ app: AppInfo) {
        guard let appURL = app.url else { return }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("defaultapp-try-\(entry.ext)-\(UUID().uuidString.prefix(4)).\(entry.ext)")
        let content = "DefaultApp try-open test for .\(entry.ext) with \(app.name)\n"
        try? content.write(to: tmp, atomically: true, encoding: .utf8)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([tmp], withApplicationAt: appURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    self.showToast(Toast(kind: .failure, message: self.i18n.t(.previewFailed, error.localizedDescription)))
                } else {
                    self.showToast(Toast(kind: .success, message: self.i18n.t(.previewOpened, app.name)))
                }
            }
        }
    }

    @MainActor
    private func reload() async {
        // current 使用与双击一致的解析；roleBased/roleAll 记录角色注册值用于一致性对比
        current = state.currentDefault(for: entry.ext)
        roleBased = LaunchServices.defaultHandler(forExtension: entry.ext)
        roleAll = LaunchServices.roleAllClaimant(forExtension: entry.ext)
        candidates = state.candidates(for: entry.ext)
        // 截图模式：展示成功提示条，演示操作反馈效果
        if Snapshotter.isActive {
            try? await Task.sleep(for: .milliseconds(300))
            if let current {
                showToast(Toast(kind: .success, message: i18n.t(.toastSetOk, entry.ext, current.name)))
            }
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = i18n.t(.chooseApp)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bid = Bundle(url: url)?.bundleIdentifier else {
            errorMessage = i18n.t(.alertMsgBundleID, url.lastPathComponent)
            return
        }
        let info = LaunchServices.appInfo(forBundleID: bid)
        if !candidates.contains(info) {
            candidates.append(info)
            candidates.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func apply(_ app: AppInfo) {
        let bid = app.bundleID
        let outcome = state.setDefault(bundleID: bid, for: entry.ext, role: role)
        switch outcome {
        case .verified(let appName):
            showToast(Toast(kind: .success, message: i18n.t(.toastSetOk, entry.ext, appName)))
        case .unconfirmed(let actualName):
            showToast(Toast(kind: .warning, message: i18n.t(.toastSetUnconfirmed, entry.ext, actualName)))
        case .failed:
            errorMessage = i18n.t(.alertMsgGeneric)
            let appName = LaunchServices.appInfo(forBundleID: bid).name
            showToast(Toast(kind: .failure, message: i18n.t(.toastSetFail, appName, entry.ext)))
        }
        Task { await reload() }
    }
}

struct CandidateRow: View {
    let app: AppInfo
    let isCurrent: Bool
    @Environment(I18n.self) private var i18n

    var body: some View {
        HStack(spacing: 10) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.5)))
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name).font(.body)
                    if isCurrent {
                        Text(i18n.t(.currentBadge))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.green.opacity(0.22)))
                    }
                }
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 操作结果浮动提示

/// 操作结果提示：成功（绿）/ 被抢占警告（橙）/ 失败（红），4 秒自动消失。
private struct Toast: Identifiable {
    enum Kind { case success, warning, failure }
    let id = UUID()
    let kind: Kind
    let message: String
}

private struct ToastView: View {
    let toast: Toast

    private var iconName: String {
        switch toast.kind {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch toast.kind {
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            Text(toast.message)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(iconColor.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .frame(maxWidth: 460)
        .padding(.horizontal, 24)
    }
}

// MARK: - 候选行（常显操作）

/// 候选行：「临时打开」与「设为默认」按钮常显（感知明确），行高充裕。
/// 文件后缀页与 URL 协议页共用，保持两页风格一致。
struct ActionCandidateRow: View {
    let app: AppInfo
    let isCurrent: Bool
    var onPreview: (() -> Void)?
    let onSetDefault: () -> Void
    @Environment(I18n.self) private var i18n

    var body: some View {
        HStack(spacing: 12) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name).font(.body)
                    if isCurrent {
                        Text(i18n.t(.currentBadge))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.green.opacity(0.22)))
                    }
                }
                Text(app.bundleID)
                    .textSelection(.enabled)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isCurrent {
                HStack(spacing: 10) {
                    if let onPreview {
                        Button(action: onPreview) {
                            Label(i18n.t(.previewShort), systemImage: "play.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .help(i18n.t(.previewTip))
                    }
                    Button(action: onSetDefault) {
                        Label(i18n.t(.setDefaultShort), systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
