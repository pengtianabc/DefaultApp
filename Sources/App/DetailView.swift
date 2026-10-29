import AppKit
import SwiftUI

struct DetailView: View {
    let entry: AppState.Entry
    @Environment(AppState.self) private var state
    @Environment(I18n.self) private var i18n

    @State private var role: HandlerRole = .all
    @State private var current: AppInfo?
    @State private var candidates: [AppInfo] = []
    @State private var pickedID: String?
    @State private var errorMessage: String?

    private var taskID: String {
        "\(entry.id.uuidString)-\(state.refreshToken.uuidString)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            rolePicker
            candidatesSection
            Spacer(minLength: 0)
            actionBar
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
    }

    // MARK: - 当前默认

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(i18n.t(.extSuffixLabel))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(".\(entry.ext)")
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
        }
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
            Picker(i18n.t(.roleLabel), selection: $role) {
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
                List(selection: $pickedID) {
                    ForEach(candidates) { app in
                        CandidateRow(app: app, isCurrent: app.bundleID == current?.bundleID)
                            .tag(app.id)
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 180, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.6)))
                .animation(.default, value: candidates.count)
            }
        }
    }

    // MARK: - 操作

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(i18n.t(.chooseApp)) { chooseApp() }
                .buttonStyle(.bordered)
            Spacer()
            Button(i18n.t(.setDefault)) { apply() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(pickedID == nil)
        }
    }

    @MainActor
    private func reload() async {
        current = state.currentDefault(for: entry.ext)
        candidates = state.candidates(for: entry.ext)
        pickedID = nil
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
        pickedID = bid
    }

    private func apply() {
        guard let bid = pickedID else { return }
        guard state.setDefault(bundleID: bid, for: entry.ext, role: role) else {
            errorMessage = i18n.t(.alertMsgGeneric)
            return
        }
        Task { await reload() }
    }
}

private struct CandidateRow: View {
    let app: AppInfo
    let isCurrent: Bool

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
                        Text("CURRENT")
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
