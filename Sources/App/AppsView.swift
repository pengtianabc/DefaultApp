import AppKit
import SwiftUI

/// 「应用」视图：检查应用 ↔ 后缀关系。
/// 左侧：应用列表（来自当前后缀列表的候选与实际默认反查 + 手动选择任意应用）。
/// 右侧：选中应用的详情——是默认打开方式的后缀、可打开的后缀、声明的文档类型。
struct AppsView: View {
    @Environment(AppState.self) private var state
    @Environment(I18n.self) private var i18n

    @State private var selectedID: String?
    @State private var query = ""
    @State private var sort: AppSort = .name
    @State private var refreshSpin: Double = 0
    @State private var newExt = ""
    /// 「默认打开」区拖放悬停高亮。
    @State private var ownsTargeted = false
    /// 「可打开」区拖放悬停高亮。
    @State private var supportsTargeted = false

    /// 应用列表排序方式。
    enum AppSort: String, CaseIterable, Identifiable {
        case name, owns, supports
        var id: String { rawValue }
    }

    private var visibleApps: [AppRelation] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty ? state.appIndex : state.appIndex.filter {
            $0.info.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q)
        }
        switch sort {
        case .name:
            return filtered.sorted {
                $0.info.name.localizedCaseInsensitiveCompare($1.info.name) == .orderedAscending
            }
        case .owns:
            return filtered.sorted {
                ($0.owns.count != $1.owns.count)
                    ? $0.owns.count > $1.owns.count
                    : $0.info.name.localizedCaseInsensitiveCompare($1.info.name) == .orderedAscending
            }
        case .supports:
            return filtered.sorted {
                ($0.supports.count != $1.supports.count)
                    ? $0.supports.count > $1.supports.count
                    : $0.info.name.localizedCaseInsensitiveCompare($1.info.name) == .orderedAscending
            }
        }
    }

    var body: some View {
        HSplitView {
            appList
                .frame(minWidth: 230, maxWidth: 380)
            detailArea
                .frame(minWidth: 520)
                .layoutPriority(1)
        }
        .onChange(of: state.pendingAppFocus, initial: true) { _, bundleID in
            // initial: true——从后缀页双击跳过来时，本视图是挂载后才出现的新值，
            // 普通 onChange 不会触发，必须随挂载立即检查一次。
            guard let bundleID else { return }
            state.addInspectedApp(bundleID)
            selectedID = bundleID
            state.pendingAppFocus = nil
        }
    }

    // MARK: - 应用列表

    private var appList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(i18n.t(.appsSearchPlaceholder), text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                sortPicker
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

            List(selection: $selectedID) {
                Section(i18n.t(.tabApps)) {
                    ForEach(visibleApps) { app in
                        AppRow(relation: app)
                            .tag(app.id)
                    }
                }
            }
            .listStyle(.sidebar)

            Button { chooseApp() } label: {
                Label(i18n.t(.chooseAppInspect), systemImage: "app.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .overlay {
            if state.appIndex.isEmpty {
                Text(i18n.t(.appsEmpty))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var sortPicker: some View {
        Picker("", selection: $sort) {
            ForEach(AppSort.allCases) { option in
                Text(sortTitle(option)).tag(option)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help(sortTitle(sort))
    }

    private func sortTitle(_ option: AppSort) -> String {
        switch option {
        case .name: return i18n.t(.sortName)
        case .owns: return i18n.t(.sortOwns)
        case .supports: return i18n.t(.sortSupports)
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = i18n.t(.chooseAppInspect)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let bid = Bundle(url: url)?.bundleIdentifier else { return }
        state.addInspectedApp(bid)
        selectedID = bid
    }

    /// 在当前应用下直接添加后缀：加入文件后缀列表，并立即设为由该应用打开。
    private func confirmAdd(for app: AppRelation) {
        let raw = newExt
        newExt = ""
        let cleaned = AppState.sanitize(raw)
        state.addExtension(raw)
        guard !cleaned.isEmpty else { return }
        state.setDefault(bundleID: app.bundleID, for: cleaned, role: .all)
    }

    // MARK: - 详情

    private var selectedApp: AppRelation? {
        state.appIndex.first(where: { $0.id == selectedID })
            ?? visibleApps.first
    }

    private var detailArea: some View {
        Group {
            if let app = selectedApp {
                appDetail(app)
            } else {
                ContentUnavailableView {
                    Label(i18n.t(.noSelectionTitle), systemImage: "app")
                }
            }
        }
    }

    private func appDetail(_ app: AppRelation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    if let icon = app.info.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.info.name).font(.title3.bold())
                        Text(app.bundleID)
                            .textSelection(.enabled)
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Label(i18n.t(.appCountOwns, "\(app.owns.count)"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Label(i18n.t(.appCountSupports, "\(app.supports.count)"), systemImage: "doc.on.doc")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                    Spacer()
                    VStack(spacing: 8) {
                        if let url = app.info.url {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } label: {
                                Label(i18n.t(.showInFinder), systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(16)
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.5))
                }

                // 内联添加后缀：就地输入回车即生效，不再弹框
                HStack(spacing: 10) {
                    Text(i18n.t(.addExtInlineLabel, app.info.name))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField(i18n.t(.addExtInlinePlaceholder), text: $newExt)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onSubmit { confirmAdd(for: app) }
                    Button(i18n.t(.add)) { confirmAdd(for: app) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(newExt.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                }
                .padding(.horizontal, 4)

                if !app.owns.isEmpty || !app.supports.isEmpty {
                    ownsSection(app)
                }

                if !app.supports.isEmpty {
                    supportsSection(app)
                }

                // URL 协议维度：该应用声明能处理的协议，双击跳到协议页
                let schemes = LaunchServices.urlSchemes(forBundleID: app.bundleID)
                if !schemes.isEmpty {
                    section(title: i18n.t(.appSchemesTitle, app.info.name)) {
                        schemeChips(schemes)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    // MARK: - 三个后缀区块（默认打开 / 可打开 / 声明的类型）

    /// 「默认打开」区：恒显示虚线投放框（空时显示提示文字），
    /// 接收「可打开」「声明的类型」拖来的胶囊，设为该应用默认打开。
    private func ownsSection(_ app: AppRelation) -> some View {
        section(title: i18n.t(.appOwnsTitle, app.info.name)) {
            Group {
                if app.owns.isEmpty {
                    Text(i18n.t(.ownsEmptyHint))
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    extChips(app.owns, highlighted: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.15)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: ownsTargeted ? 2.5 : 1.5, dash: [6, 4]))
                    .foregroundStyle(ownsTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.5)))
            )
            .animation(.snappy(duration: 0.15), value: ownsTargeted)
        }
        .dropDestination(for: String.self, action: { items, _ in
            dropSetDefault(items, app: app)
            return true
        }, isTargeted: { ownsTargeted = $0 })
    }

    /// 「可打开」区：接收从「默认打开」拖来的胶囊 = 取消默认，交还系统。
    private func supportsSection(_ app: AppRelation) -> some View {
        section(title: i18n.t(.appSupportsTitle, app.info.name)) {
            VStack(alignment: .leading, spacing: 6) {
                extChips(app.supports, highlighted: false)
                Text(i18n.t(.supportsDropHint))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: supportsTargeted ? 2.5 : 1, dash: supportsTargeted ? [6, 4] : []))
                    .foregroundStyle(supportsTargeted ? AnyShapeStyle(.orange) : AnyShapeStyle(.clear))
            )
            .animation(.snappy(duration: 0.15), value: supportsTargeted)
        }
        .dropDestination(for: String.self, action: { items, _ in
            dropUnsetDefault(items, app: app)
            return true
        }, isTargeted: { supportsTargeted = $0 })
    }

    private func extChips(_ exts: [String], highlighted: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
            ForEach(exts, id: \.self) { ext in
                chipContent(ext, highlighted: highlighted)
                    .overlay(DoubleClickRecognizer { focusExtension(ext) })
                    .linkCursorOnHover()
                    .help(i18n.t(.chipJumpTip))
                    // 两个方向的胶囊都可拖：默认打开 ⇄ 可打开
                    .draggable(ext)
            }
        }
    }

    /// URL 协议胶囊：与协议页同一视觉语言（teal/blue 链接徽标），双击跳转。
    /// 协议数量少，流式布局按自然宽度单行完整显示；悬停提示附完整协议名。
    private func schemeChips(_ schemes: [String]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(schemes, id: \.self) { scheme in
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(
                            LinearGradient(colors: [.teal, .blue],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                    Text("\(scheme):")
                        .font(.callout.monospaced())
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .fixedSize(horizontal: true, vertical: false)
                .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.25)))
                .overlay(DoubleClickRecognizer { state.pendingSchemeFocus = scheme })
                .linkCursorOnHover()
                .help(Text("\(scheme)\n\(i18n.t(.schemeJumpTip))"))
            }
        }
    }

    private func chipContent(_ ext: String, highlighted: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AnyShapeStyle(highlighted ? Color.green : Color.secondary.opacity(0.4)))
                .frame(width: 6, height: 6)
            Text(".\(ext)")
                .font(.callout.monospaced())
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(highlighted ? AnyShapeStyle(.green.opacity(0.08)) : AnyShapeStyle(.quaternary.opacity(0.25)))
        )
    }

    /// 双击胶囊：跳到「文件后缀」页并选中该后缀（不在列表时静默补入）。
    private func focusExtension(_ ext: String) {
        state.ensureExtension(ext)
        state.pendingExtFocus = ext
    }

    /// 投放到「默认打开」：把拖来的后缀逐个设为该应用默认打开（已是默认的跳过）。
    private func dropSetDefault(_ items: [String], app: AppRelation) {
        var done: [String] = []
        for raw in items {
            let ext = AppState.sanitize(raw)
            guard !ext.isEmpty, !app.owns.contains(ext) else { continue }
            state.ensureExtension(ext)
            let outcome = state.setDefault(bundleID: app.bundleID, for: ext, role: .all)
            switch outcome {
            case .verified, .unconfirmed:
                done.append(".\(ext)")
            case .failed:
                state.overrideStatus(i18n.t(.toastSetFail, app.info.name, ext), success: false)
            }
        }
        if !done.isEmpty {
            state.overrideStatus(i18n.t(.ownsDropDone, done.joined(separator: " "), app.info.name), success: true)
        }
        state.refresh()
    }

    /// 投放到「可打开」：把从「默认打开」拖来的后缀取消默认，交还系统。
    private func dropUnsetDefault(_ items: [String], app: AppRelation) {
        var done: [String] = []
        for raw in items {
            let ext = AppState.sanitize(raw)
            guard !ext.isEmpty, app.owns.contains(ext) else { continue }
            if state.removeDefault(for: ext) {
                done.append(".\(ext)")
            } else {
                state.overrideStatus(i18n.t(.toastSetFail, app.info.name, ext), success: false)
            }
        }
        if !done.isEmpty {
            state.overrideStatus(i18n.t(.ownsDropUnset, done.joined(separator: " ")), success: true)
        }
        state.refresh()
    }
}

private struct AppRow: View {
    let relation: AppRelation

    var body: some View {
        HStack(spacing: 10) {
            if let icon = relation.info.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(relation.info.name)
                    .font(.body)
                    .lineLimit(1)
                Text(relation.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if !relation.owns.isEmpty {
                Text("\(relation.owns.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.green))
            }
        }
    }
}
