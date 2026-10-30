import AppKit
import SwiftUI

/// 「URL 协议」视图：默认浏览器（https）、邮件客户端（mailto）等系统级协议的处理应用。
struct SchemesView: View {
    @Environment(AppState.self) private var state
    @Environment(I18n.self) private var i18n

    /// 协议列表：动态发现（应用声明 + 覆盖表 + 内置常见项），见 LaunchServices.allKnownSchemes()。
    @State private var schemes: [String] = []
    /// 有用户覆盖记录的协议（「用户配置/系统默认」过滤的数据源）。
    @State private var overrideSchemes: Set<String> = []
    @State private var sourceFilter: SourceFilter = .all

    private enum SourceFilter: String, CaseIterable, Identifiable {
        case all, user, system
        var id: String { rawValue }
    }

    @State private var selected: String?
    @State private var handlers: [String: AppInfo] = [:]
    @State private var candidates: [AppInfo] = []
    @State private var pickedID: String?
    @State private var busy = false
    @State private var query = ""
    @State private var refreshSpin: Double = 0

    private var visibleSchemes: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return schemes.filter { scheme in
            if !q.isEmpty, !scheme.contains(q) { return false }
            switch sourceFilter {
            case .all: return true
            case .user: return overrideSchemes.contains(scheme)
            case .system: return !overrideSchemes.contains(scheme)
            }
        }
    }

    private var current: AppInfo? {
        guard let selected else { return nil }
        return handlers[selected]
    }

    var body: some View {
        HSplitView {
            schemeList
                .frame(minWidth: 280, maxWidth: 380)
            detailArea
                .frame(minWidth: 560)
                .layoutPriority(1)
        }
        .task(id: state.refreshToken.uuidString) { await reloadAll() }
    }

    // MARK: - 协议列表

    private var schemeList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(i18n.t(.searchPlaceholder), text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    refreshSpin += 360
                    state.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(i18n.t(.refresh))
                .rotationEffect(.degrees(refreshSpin))
                .animation(.snappy(duration: 0.5), value: refreshSpin)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
            .padding(.horizontal, 10)
            .padding(.top, 10)

            Picker("source filter", selection: $sourceFilter) {
                Text(i18n.t(.filterAll)).tag(SourceFilter.all)
                Text(i18n.t(.filterUser)).tag(SourceFilter.user)
                Text(i18n.t(.filterSystem)).tag(SourceFilter.system)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            List(selection: $selected) {
                Section(i18n.t(.tabSchemes)) {
                    ForEach(visibleSchemes, id: \.self) { scheme in
                        SchemeRow(
                            scheme: scheme,
                            handler: handlers[scheme],
                            isSelected: selected == scheme
                        )
                        .tag(scheme)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selected) { _, _ in
                Task { await reloadCandidates() }
            }

            Text(i18n.t(.schemesIntro))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .overlay(alignment: .top) { Divider() }
        }
    }

    // MARK: - 详情

    private var detailArea: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let scheme = selected {
                header(scheme: scheme)
                candidatesSection(scheme: scheme)
                Spacer(minLength: 0)
                actionBar(scheme: scheme)
            } else {
                Spacer()
                ContentUnavailableView {
                    Label(i18n.t(.tabSchemes), systemImage: "link")
                }
                Spacer()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(scheme: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(scheme):")
                .textSelection(.enabled)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Capsule()
                )
            if let current {
                HStack(spacing: 10) {
                    if let icon = current.icon {
                        Image(nsImage: icon)
                            .resizable().scaledToFit().frame(width: 30, height: 30)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(current.name).font(.headline)
                            Text(i18n.t(.currentBadge))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(.green.opacity(0.2)))
                        }
                        Text(current.bundleID)
                            .textSelection(.enabled)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let url = current.url {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                            Label(i18n.t(.showInFinder), systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.5)) }
            } else {
                Label(i18n.t(.schemeNoHandler), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    private func candidatesSection(scheme: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(i18n.t(.schemeCandidates, "\(scheme):"))
                .font(.headline)
            if candidates.isEmpty {
                Text(i18n.t(.candidatesEmpty, "\(scheme):"))
                    .font(.callout).foregroundStyle(.secondary)
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
                .frame(minHeight: 160, maxHeight: .infinity)
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.6)) }
            }
        }
    }

    private func actionBar(scheme: String) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await restore(scheme: scheme) }
            } label: {
                Label(i18n.t(.schemeUnset), systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(busy)
            Spacer()
            Button {
                Task { await apply(scheme: scheme) }
            } label: {
                Label(i18n.t(.setDefault), systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(pickedID == nil || busy)
        }
    }

    // MARK: - 数据

    @MainActor
    private func reloadAll() async {
        schemes = LaunchServices.allKnownSchemes()
        overrideSchemes = LaunchServices.schemesWithOverrides()
        var map: [String: AppInfo] = [:]
        for scheme in schemes {
            if let handler = LaunchServices.schemeDefaultHandler(scheme) {
                map[scheme] = handler
            }
        }
        handlers = map
        if selected == nil { selected = schemes.first }
        await reloadCandidates()
    }

    @MainActor
    private func reloadCandidates() async {
        pickedID = nil
        guard let selected else { candidates = []; return }
        candidates = LaunchServices.schemeHandlers(selected)
    }

    @MainActor
    private func apply(scheme: String) async {
        guard let bid = pickedID else { return }
        busy = true
        defer { busy = false }
        guard LaunchServices.setSchemeHandler(bundleID: bid, scheme: scheme) else { return }
        Thread.sleep(forTimeInterval: 0.3)
        let handler = LaunchServices.schemeDefaultHandler(scheme)
        handlers[scheme] = handler
        let name = handler?.name ?? bid
        state.refresh()
        state.overrideStatus(i18n.t(.schemeSetDone, "\(scheme):", name))
        await reloadCandidates()
    }

    @MainActor
    private func restore(scheme: String) async {
        busy = true
        defer { busy = false }
        guard LaunchServices.removeSchemeOverride(scheme) else { return }
        Thread.sleep(forTimeInterval: 0.3)
        handlers[scheme] = LaunchServices.schemeDefaultHandler(scheme)
        state.refresh()
        state.overrideStatus(i18n.t(.schemeRestoreDone, "\(scheme):"))
        await reloadCandidates()
    }
}

private struct SchemeRow: View {
    let scheme: String
    let handler: AppInfo?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 7)
                )
            Text("\(scheme):")
                .font(.body.monospaced())
            Spacer(minLength: 6)
            if let handler {
                if let icon = handler.icon {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 18, height: 18)
                }
                Text(handler.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
