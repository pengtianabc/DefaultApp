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
                .frame(minWidth: 270, maxWidth: 400)
            detailArea
                .frame(minWidth: 560)
                .layoutPriority(1)
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

                if !app.owns.isEmpty {
                    section(title: i18n.t(.appOwnsTitle, app.info.name)) {
                        extChips(app.owns, highlighted: true)
                    }
                }

                if !app.supports.isEmpty {
                    section(title: i18n.t(.appSupportsTitle, app.info.name)) {
                        extChips(app.supports, highlighted: false)
                    }
                }

                let declared = state.declaredTypes(forBundleID: app.bundleID)
                if !declared.isEmpty {
                    section(title: i18n.t(.appDeclaredTypes)) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 6)], spacing: 6) {
                            ForEach(declared, id: \.self) { type in
                                Text(type)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.3)))
                            }
                        }
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

    private func extChips(_ exts: [String], highlighted: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
            ForEach(exts, id: \.self) { ext in
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
        }
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
