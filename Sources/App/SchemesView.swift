import AppKit
import SwiftUI

/// 「URL 协议」视图：默认浏览器（https）、邮件客户端（mailto）等系统级协议的处理应用。
struct SchemesView: View {
    @Environment(AppState.self) private var state
    @Environment(I18n.self) private var i18n

    /// 常见协议目录（https/http 分离，mailto 等）。
    static let schemes = [
        "https", "http", "mailto", "ftp", "ssh", "tel", "sms",
        "facetime", "facetime-audio", "webcal", "xmpp", "zoommtg", "slack",
    ]

    @State private var selected: String?
    @State private var handlers: [String: AppInfo] = [:]
    @State private var candidates: [AppInfo] = []
    @State private var pickedID: String?
    @State private var busy = false

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
        .task { await reloadAll() }
    }

    // MARK: - 协议列表

    private var schemeList: some View {
        VStack(spacing: 0) {
            List(selection: $selected) {
                Section(i18n.t(.tabSchemes)) {
                    ForEach(Self.schemes, id: \.self) { scheme in
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
                        Text(current.bundleID).font(.caption).foregroundStyle(.secondary)
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
        var map: [String: AppInfo] = [:]
        for scheme in Self.schemes {
            if let handler = LaunchServices.schemeDefaultHandler(scheme) {
                map[scheme] = handler
            }
        }
        handlers = map
        if selected == nil { selected = Self.schemes.first }
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
