import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(I18n.self) private var i18n

    @State private var newExt = ""
    @State private var query = ""
    @State private var sourceFilter: SourceFilter = .all
    @State private var refreshSpin: Double = 0
    @State private var showQuickAdd = false
    @State private var mode: ViewMode = .extensions

    private enum SourceFilter: String, CaseIterable, Identifiable {
        case all, user, system
        var id: String { rawValue }
    }

    private enum ViewMode: String {
        case extensions, apps, schemes
    }

    var body: some View {
        @Bindable var state = state
        @Bindable var i18n = i18n
        VStack(spacing: 0) {
            // 自定义胶囊分段控件：激活高亮 + 悬停反馈（原生 segmented 悬停效果太弱）
            HStack(spacing: 4) {
                ModeTabButton(title: i18n.t(.tabExtensions), isActive: mode == .extensions) { mode = .extensions }
                ModeTabButton(title: i18n.t(.tabApps), isActive: mode == .apps) { mode = .apps }
                ModeTabButton(title: i18n.t(.tabSchemes), isActive: mode == .schemes) { mode = .schemes }
            }
            .padding(4)
            .frame(width: 340)
            .background(Capsule().fill(.quaternary.opacity(0.3)))
            .padding(.vertical, 8)

            switch mode {
            case .extensions:
                extensionsSplit
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .apps:
                AppsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .schemes:
                SchemesView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            statusBar
        }
        .frame(minWidth: 940, minHeight: 620)
        .tint(.indigo)
        .task {
            if Snapshotter.isActive {
                state.selectedID = state.entries.first(where: { $0.ext == "md" })?.id
                Snapshotter.stage()
                try? await Task.sleep(for: .milliseconds(1600))
                Snapshotter.captureAndExit()
            } else {
                GitHubRelease.shared.check()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                githubButton
            }
            ToolbarItem(placement: .primaryAction) {
                Picker(selection: $i18n.lang) {
                    Label(i18n.t(.followSystem), systemImage: "macbook").tag(I18n.Lang.system)
                    Text("English").tag(I18n.Lang.en)
                    Text("简体中文").tag(I18n.Lang.zh)
                } label: {
                    Image(systemName: "globe")
                }
                .pickerStyle(.menu)
                .help(i18n.t(.languageLabel))
                .frame(width: 42)
            }
        }
    }

    // MARK: - GitHub 版本入口

    private var githubButton: some View {
        Button {
            GitHubRelease.shared.visit()
        } label: {
            if let tag = GitHubRelease.shared.latestTag {
                Label("v\(tag)", systemImage: GitHubRelease.shared.isNewer ? "arrow.up.circle.fill" : "tag")
                    .foregroundStyle(GitHubRelease.shared.isNewer ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .font(.callout.weight(.medium))
            } else {
                Label(i18n.t(.ghButton), systemImage: "link")
            }
        }
        .buttonStyle(.plain)
        .help(githubTooltip)
    }

    private var githubTooltip: String {
        if let tag = GitHubRelease.shared.latestTag {
            if GitHubRelease.shared.isNewer {
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
                return i18n.t(.ghTipNew, tag, current)
            }
            return i18n.t(.ghTip, tag)
        }
        return i18n.t(.ghTipUnknown)
    }

    private var extensionsSplit: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 280, maxWidth: 400)
            detailArea
                .frame(minWidth: 600)
                .layoutPriority(1)
        }
    }

    // MARK: - 侧边栏

    private var sidebar: some View {
        @Bindable var state = state
        return VStack(spacing: 0) {
            searchBar
            filterPicker
            List(selection: $state.selectedID) {
                Section(i18n.t(.sidebarTitle)) {
                    ForEach(visibleEntries) { entry in
                        SidebarRow(entry: entry)
                            .tag(entry.id)
                            .contextMenu {
                                Button("\(i18n.t(.remove)) .\(entry.ext)", role: .destructive) {
                                    state.remove(entry)
                                }
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            .animation(.snappy, value: visibleEntries.count)
            .overlay {
                if state.entries.isEmpty {
                    emptySidebar
                } else if visibleEntries.isEmpty {
                    noMatchView
                }
            }

            Divider()
            quickAddButton
            addBar
        }
    }

    private var visibleEntries: [AppState.Entry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return state.entries.filter { entry in
            if !q.isEmpty {
                let appName = state.currentDefault(for: entry.ext)?.name.lowercased() ?? ""
                guard entry.ext.contains(q) || appName.contains(q) else { return false }
            }
            switch sourceFilter {
            case .all: return true
            case .user: return state.source(for: entry.ext) == .user
            case .system: return state.source(for: entry.ext) == .system
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(i18n.t(.searchPlaceholder), text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    private var filterPicker: some View {
        Picker("source filter", selection: $sourceFilter) {
            ForEach(SourceFilter.allCases) { filter in
                switch filter {
                case .all: Text(i18n.t(.filterAll)).tag(filter)
                case .user: Text(i18n.t(.filterUser)).tag(filter)
                case .system: Text(i18n.t(.filterSystem)).tag(filter)
                }
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var emptySidebar: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(
                    LinearGradient(
                        colors: [.indigo, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .shadow(color: .indigo.opacity(0.35), radius: 10, y: 4)
            Text(i18n.t(.emptyExtTitle))
                .font(.headline)
            Text(i18n.t(.emptyExtDesc))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.secondary)
            Text(i18n.t(.noMatch))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var quickAddButton: some View {
        Button {
            showQuickAdd = true
        } label: {
            Label(i18n.t(.quickAddButton), systemImage: "square.grid.2x2")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .popover(isPresented: $showQuickAdd, arrowEdge: .bottom) {
            QuickAddPanel(isPresented: $showQuickAdd)
                .environment(state)
                .environment(i18n)
                .frame(width: 470)
                .padding(14)
        }
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            TextField(i18n.t(.addPlaceholder), text: $newExt)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addFromField)
            Button(i18n.t(.add), action: addFromField)
                .keyboardShortcut(.defaultAction)
                .disabled(newExt.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
    }

    private func addFromField() {
        state.addExtension(newExt)
        newExt = ""
    }

    // MARK: - 详情

    private var selectedEntry: AppState.Entry? {
        state.entries.first(where: { $0.id == state.selectedID })
    }

    private var detailArea: some View {
        VStack(spacing: 0) {
            if let entry = selectedEntry {
                DetailView(entry: entry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(entry.id)
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "arrow.left.circle")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(
                            LinearGradient(
                                colors: [.teal, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                        .shadow(color: .teal.opacity(0.35), radius: 8, y: 3)
                    Text(i18n.t(.noSelectionTitle))
                        .font(.headline)
                    Text(i18n.t(.noSelectionDesc))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                Spacer()
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Image(systemName: I18n.shared.statusIsSuccess ? "checkmark.circle.fill" : "info.circle")
                .foregroundStyle(I18n.shared.statusIsSuccess ? Color.green : Color.secondary)
            Text(state.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if selectedEntry != nil {
                Button(i18n.t(.refresh)) {
                    refreshSpin += 360
                    state.refresh()
                }
                .controlSize(.small)
                .rotationEffect(.degrees(refreshSpin))
                .animation(.snappy(duration: 0.5), value: refreshSpin)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - 常用后缀批量添加面板

struct QuickAddPanel: View {
    @Binding var isPresented: Bool
    @Environment(AppState.self) private var state
    @Environment(I18n.self) private var i18n

    @State private var category: ExtCategory = .all
    @State private var selected: Set<String> = []

    private var exts: [String] {
        ExtensionCatalog.extensions(for: category)
    }

    private var addable: [String] {
        selected
            .filter { ext in !state.entries.contains(where: { $0.ext == ext }) }
            .sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            categoryBar
            Divider().padding(.vertical, 10)
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(exts, id: \.self) { ext in
                        chip(ext)
                    }
                }
            }
            .frame(height: 240)
            Divider().padding(.vertical, 10)
            footer
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ExtCategory.allCases) { cat in
                    let active = category == cat
                    Button {
                        category = cat
                    } label: {
                        Text(i18n.categoryTitle(cat))
                            .font(.callout.weight(active ? .semibold : .regular))
                            .foregroundStyle(active ? .white : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary.opacity(0.4)))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chip(_ ext: String) -> some View {
        let already = state.entries.contains(where: { $0.ext == ext })
        let isSelected = selected.contains(ext)
        return Button {
            if isSelected {
                selected.remove(ext)
            } else {
                selected.insert(ext)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: already || isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(already || isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .imageScale(.small)
                Text(".\(ext)")
                    .font(.callout.monospaced())
                if already {
                    Text("· \(i18n.t(.alreadyAdded))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.25)))
            )
        }
        .buttonStyle(.plain)
        .disabled(already)
        .opacity(already ? 0.55 : 1)
    }

    private var footer: some View {
        HStack {
            Text(i18n.t(.selectedCount, "\(selected.count)"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button(i18n.t(.clearSelection)) { selected.removeAll() }
                .disabled(selected.isEmpty)
            Button(i18n.t(.addSelected, "\(addable.count)")) {
                state.addExtensions(Array(selected))
                isPresented = false
            }
            .keyboardShortcut(.defaultAction)
            .disabled(addable.isEmpty)
        }
    }
}

// MARK: - 行与图标

private struct SidebarRow: View {
    let entry: AppState.Entry
    @Environment(AppState.self) private var state
    @Environment(I18n.self) private var i18n
    @State private var current: AppInfo?
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            ExtBadge(ext: entry.ext)
            Text(".\(entry.ext)")
                .font(.body.monospaced())
            Spacer(minLength: 6)
            sourceDot
            Text(current?.name ?? "—")
                .textSelection(.enabled)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(hovered ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onHover { hovered = $0 }
        .task(id: "\(entry.id.uuidString)-\(state.refreshToken.uuidString)") {
            current = state.currentDefault(for: entry.ext)
        }
    }

    @ViewBuilder
    private var sourceDot: some View {
        let source = state.source(for: entry.ext)
        if source != .none {
            Circle()
                .fill(source == .user ? AnyShapeStyle(.blue) : AnyShapeStyle(.secondary.opacity(0.45)))
                .frame(width: 7, height: 7)
                .help(source == .user ? i18n.t(.sourceUserTip) : i18n.t(.sourceSystemTip))
        }
    }
}

/// 按后缀名生成稳定的渐变色，用于侧边栏图标与详情页标题。
enum ExtPalette {
    static let palette: [(Color, Color)] = [
        (.blue, .cyan), (.indigo, .purple), (.orange, .red),
        (.green, .mint), (.pink, .orange), (.teal, .blue),
    ]

    static func gradient(for ext: String) -> [Color] {
        var index = ext.hashValue % palette.count
        if index < 0 { index += palette.count }
        let pair = palette[index]
        return [pair.0, pair.1]
    }
}

private struct ExtBadge: View {
    let ext: String

    var body: some View {
        Image(systemName: "doc.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(
                LinearGradient(
                    colors: ExtPalette.gradient(for: ext),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 8)
            )
    }
}

// MARK: - 顶部模式切换（自定义胶囊分段，带悬停反馈）

private struct ModeTabButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        isActive ? AnyShapeStyle(.tint)
                                 : (hovered ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear))
                    )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.snappy(duration: 0.15), value: hovered)
        .animation(.snappy(duration: 0.2), value: isActive)
    }
}
