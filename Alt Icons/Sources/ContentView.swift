import SwiftUI
import AppKit

// MARK: - Update Mode

enum UpdateMode: String, CaseIterable, Identifiable, Equatable {
    case add = "Add"
    case replace = "Replace"
    case removeAll = "Remove All"
    var id: String { rawValue }
}

enum PrimarySwapAction: Hashable {
    case swap
    case removeOldPrimary
    case demoteToAlternate
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var viewModel = ViewModel()

    var body: some View {
        Group {
            if viewModel.projectConfig != nil {
                ProjectView(viewModel: viewModel)
            } else {
                WelcomeView(onOpen: { viewModel.openProject() })
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.projectConfig != nil)
        .alert(
            "Cannot Open Project",
            isPresented: Binding(
                get: { viewModel.discoveryError != nil },
                set: { if !$0 { viewModel.discoveryError = nil } }
            )
        ) {
            Button("OK") { viewModel.discoveryError = nil }
        } message: {
            Text(viewModel.discoveryError?.message ?? "")
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 52))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Alt Icons")
                    .font(.largeTitle.weight(.bold))
                Text("Manage alternate app icons for your iOS project")
                    .foregroundStyle(.secondary)
            }

            Button(action: onOpen) {
                Label("Open Project\u{2026}", systemImage: "folder")
                    .padding(.horizontal, 6)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(minWidth: 480, minHeight: 360)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Project View

struct ProjectView: View {
    @ObservedObject var viewModel: ViewModel
    @State private var showEditSheet = false
    @State private var iconToDelete: AppIconEntry?
    @State private var iconForMakePrimary: AppIconEntry?
    @State private var logPanelHeight: CGFloat = 160
    @State private var dragStartHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            iconGrid
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if viewModel.isLogPanelVisible {
                panelDivider
                logPanel
                    .frame(height: logPanelHeight)
            }
        }
        .frame(minWidth: 560, minHeight: 460)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar { toolbarContent }
        .sheet(isPresented: $showEditSheet, onDismiss: {
            viewModel.loadIcons()
        }) {
            EditSheet(viewModel: viewModel)
        }
        .alert("Delete Icon", isPresented: Binding(
            get: { iconToDelete != nil },
            set: { if !$0 { iconToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { iconToDelete = nil }
            Button("Delete", role: .destructive) {
                if let icon = iconToDelete {
                    viewModel.removeIcon(icon)
                    iconToDelete = nil
                }
            }
        } message: {
            if let icon = iconToDelete {
                Text("Remove \"\(icon.name)\" from the project? This will delete the icon set and update project files.")
            }
        }
        .sheet(isPresented: Binding(
            get: { iconForMakePrimary != nil },
            set: { if !$0 { iconForMakePrimary = nil } }
        )) {
            if let icon = iconForMakePrimary {
                MakePrimarySheet(alternateIcon: icon) { action, customName in
                    viewModel.makePrimary(icon, action: action, customName: customName)
                    iconForMakePrimary = nil
                }
            }
        }
        .onChange(of: viewModel.selectedXcassetsIndex) {
            viewModel.loadIcons()
        }
        .sheet(isPresented: $viewModel.showValidationReport) {
            ValidationReportSheet(viewModel: viewModel)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if let config = viewModel.projectConfig {
                Button {
                    viewModel.openProject()
                } label: {
                    Text(config.rootURL.lastPathComponent)
                        .font(.headline)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
        }

        ToolbarItem(placement: .principal) {
            if let config = viewModel.projectConfig, config.xcassetsPaths.count > 1 {
                Picker("Catalog", selection: $viewModel.selectedXcassetsIndex) {
                    ForEach(Array(config.xcassetsPaths.enumerated()), id: \.offset) { index, path in
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .tag(index)
                    }
                }
                .frame(maxWidth: 200)
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if let report = viewModel.validationReport, !report.isValid {
                Button {
                    viewModel.showValidationReport = true
                } label: {
                    Label("\(report.totalErrors)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                .help("\(report.totalErrors) icon validation error(s)")
            }

            Button {
                showEditSheet = true
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }

            Button {
                withAnimation {
                    viewModel.isLogPanelVisible.toggle()
                }
            } label: {
                Label("Console", systemImage: viewModel.isLogPanelVisible ? "terminal.fill" : "terminal")
            }

            Menu {
                Button {
                    viewModel.openProject()
                } label: {
                    Label("Open Project\u{2026}", systemImage: "folder")
                }

                Divider()

                if let config = viewModel.projectConfig {
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: config.rootURL.path)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder.badge.questionmark")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Icon Grid

    @ViewBuilder
    private var iconGrid: some View {
        if viewModel.icons.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "app.dashed")
                    .font(.system(size: 40))
                    .foregroundStyle(.quaternary)
                Text("No App Icons")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Click Edit to add alternate icons to your project")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)

                Button("Edit Icons\u{2026}") {
                    showEditSheet = true
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(viewModel.icons) { icon in
                        IconCard(icon: icon, onDelete: {
                            iconToDelete = icon
                        }, onMakePrimary: {
                            iconForMakePrimary = icon
                        })
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - Log Panel

    private var panelDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .center) {
                Color.clear
                    .frame(height: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            NSCursor.resizeUpDown.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                if dragStartHeight == nil {
                                    dragStartHeight = logPanelHeight
                                }
                                logPanelHeight = max(80, min(400, (dragStartHeight ?? 160) - value.translation.height))
                            }
                            .onEnded { _ in
                                dragStartHeight = nil
                            }
                    )
            }
    }

    private var logPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Output", systemImage: "terminal")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if !viewModel.logs.isEmpty {
                    Button {
                        viewModel.logs.removeAll()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation {
                        viewModel.isLogPanelVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.logs.isEmpty ? "No output yet." : viewModel.logs)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(viewModel.logs.isEmpty ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .id("logEnd")
                }
                .onChange(of: viewModel.logs) {
                    proxy.scrollTo("logEnd", anchor: .bottom)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Icon Card

struct IconCard: View {
    let icon: AppIconEntry
    let onDelete: () -> Void
    let onMakePrimary: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let image = icon.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Image(systemName: "app.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.quaternary)
                        )
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 3, y: 2)

            VStack(spacing: 2) {
                Text(icon.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if icon.isPrimary {
                    Text("Primary")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovering ? Color(nsColor: .controlBackgroundColor).opacity(0.6) : .clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            if !icon.isPrimary {
                Button("Make Primary\u{2026}") { onMakePrimary() }
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
    }
}

// MARK: - Edit Sheet

struct EditSheet: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Icons")
                .font(.headline)

            Picker("Mode", selection: $viewModel.mode) {
                ForEach(UpdateMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isRunning)

            if viewModel.mode != .removeAll {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Icons Folder")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("Folder with PNG/JPG icons", text: $viewModel.iconsFolderPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse\u{2026}") {
                            viewModel.selectIconsFolder()
                        }
                    }
                    .disabled(viewModel.isRunning)
                }
            }

            modeHint

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(viewModel.isRunning)

                Spacer()

                Button {
                    Task {
                        await viewModel.run()
                        dismiss()
                    }
                } label: {
                    if viewModel.isRunning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Processing\u{2026}")
                        }
                    } else {
                        Text("Apply")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isRunning || (viewModel.mode != .removeAll && viewModel.iconsFolderPath.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 460, height: viewModel.mode == .removeAll ? 200 : 260)
        .animation(.easeInOut(duration: 0.2), value: viewModel.mode)
    }

    @ViewBuilder
    private var modeHint: some View {
        switch viewModel.mode {
        case .add:
            Label("Add new icons without removing existing ones", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .replace:
            Label("Replace all existing alternate icons", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .removeAll:
            Label("Remove all alternate icons from the project", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Make Primary Sheet

struct MakePrimarySheet: View {
    let alternateIcon: AppIconEntry
    let onApply: (PrimarySwapAction, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAction: PrimarySwapAction = .swap
    @State private var customAlternateName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Make \"\(alternateIcon.name)\" Primary")
                .font(.headline)

            Text("What should happen to the current primary icon?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Action", selection: $selectedAction) {
                Text("Swap (current primary becomes \"\(alternateIcon.name)\")")
                    .tag(PrimarySwapAction.swap)
                Text("Remove (delete current primary from project)")
                    .tag(PrimarySwapAction.removeOldPrimary)
                Text("Keep as alternate icon")
                    .tag(PrimarySwapAction.demoteToAlternate)
            }
            .pickerStyle(.radioGroup)

            if selectedAction == .demoteToAlternate {
                TextField("Name for current primary icon", text: $customAlternateName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.leading, 20)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") {
                    onApply(selectedAction, customAlternateName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedAction == .demoteToAlternate && customAlternateName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420, height: selectedAction == .demoteToAlternate ? 300 : 260)
        .animation(.easeInOut(duration: 0.15), value: selectedAction)
    }
}

// MARK: - Validation Report Sheet

struct ValidationReportSheet: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            issueList
            Divider()
            footer
        }
        .frame(width: 520, height: 420)
    }

    private var header: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Icon Validation Report")
                    .font(.headline)
                if let report = viewModel.validationReport {
                    Text("\(report.totalErrors) error(s), \(report.totalWarnings) warning(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let report = viewModel.validationReport, report.isValid {
                Label("App Store Safe", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
        .padding(16)
    }

    private var issueList: some View {
        ScrollView {
            if let report = viewModel.validationReport {
                if report.isValid {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.green)
                        Text("All icons passed validation")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(report.iconSetReports.filter { !$0.isValid }) { setReport in
                            Section {
                                ForEach(setReport.issues) { issue in
                                    issueRow(issue, setName: setReport.setName)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: "app.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(setReport.setName)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(setReport.errorCount) error(s)")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func issueRow(_ issue: ValidationIssue, setName: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: issue.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(issue.severity == .error ? .red : .orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(issue.file)
                    .font(.caption.monospaced().weight(.medium))
                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        HStack {
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Spacer()

            if let report = viewModel.validationReport, !report.isValid {
                Button {
                    Task {
                        await viewModel.fixIcons()
                    }
                } label: {
                    if viewModel.isFixing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Fixing\u{2026}")
                        }
                    } else {
                        Label("Fix Icons", systemImage: "wrench.and.screwdriver")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isFixing)
            }
        }
        .padding(16)
    }
}

// MARK: - ViewModel

@MainActor
final class ViewModel: ObservableObject {
    // Project
    @Published var projectConfig: ProjectConfig?
    @Published var selectedXcassetsIndex: Int = 0
    @Published var icons: [AppIconEntry] = []
    @Published var discoveryError: DiscoveryError?

    // Edit
    @Published var iconsFolderPath: String = ""
    @Published var mode: UpdateMode = .add

    // Log
    @Published var logs: String = ""
    @Published var isLogPanelVisible: Bool = false
    @Published var isRunning: Bool = false

    // Validation
    @Published var validationReport: FullValidationReport?
    @Published var isValidating: Bool = false
    @Published var isFixing: Bool = false
    @Published var showValidationReport: Bool = false

    private let specs: [ImageSpec] = [
        .init(idiom: "universal", platform: "ios", size: "20x20", scale: "2x"),
        .init(idiom: "universal", platform: "ios", size: "20x20", scale: "3x"),
        .init(idiom: "universal", platform: "ios", size: "29x29", scale: "2x"),
        .init(idiom: "universal", platform: "ios", size: "29x29", scale: "3x"),
        .init(idiom: "universal", platform: "ios", size: "38x38", scale: "2x"),
        .init(idiom: "universal", platform: "ios", size: "38x38", scale: "3x"),
        .init(idiom: "universal", platform: "ios", size: "40x40", scale: "2x"),
        .init(idiom: "universal", platform: "ios", size: "40x40", scale: "3x"),
        .init(idiom: "universal", platform: "ios", size: "60x60", scale: "2x"),
        .init(idiom: "universal", platform: "ios", size: "60x60", scale: "3x"),
        .init(idiom: "universal", platform: "ios", size: "64x64", scale: "2x"),
        .init(idiom: "universal", platform: "ios", size: "64x64", scale: "3x"),
        .init(idiom: "universal", platform: "ios", size: "68x68", scale: "2x"),
        .init(idiom: "universal", platform: "ios", size: "76x76", scale: "2x"),
        .init(idiom: "universal", platform: "ios", size: "83.5x83.5", scale: "2x"),
        .init(idiom: "universal", platform: "ios", size: "1024x1024", scale: nil)
    ]

    // MARK: - Open Project

    func openProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your iOS project directory"
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.urls.first else { return }

        switch ProjectDiscovery.discover(at: url) {
        case .success(let config):
            projectConfig = config
            selectedXcassetsIndex = config.defaultXcassetsIndex
            loadIcons()
        case .failure(let error):
            discoveryError = error
        }
    }

    func loadIcons() {
        guard let config = projectConfig,
              selectedXcassetsIndex < config.xcassetsPaths.count
        else {
            icons = []
            validationReport = nil
            return
        }
        let path = config.xcassetsPaths[selectedXcassetsIndex]
        icons = ProjectDiscovery.loadIconEntries(xcassetsPath: path)
        validateIcons()
    }

    // MARK: - Edit helpers

    func selectIconsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select folder containing icon images (PNG/JPG)"

        if panel.runModal() == .OK, let url = panel.urls.first {
            iconsFolderPath = url.path
        }
    }

    // MARK: - Run

    func run() async {
        guard let config = projectConfig else { return }

        logs.removeAll()
        isRunning = true
        isLogPanelVisible = true
        defer {
            isRunning = false
            loadIcons()
        }

        let assetsPath = config.xcassetsPaths[selectedXcassetsIndex]
        let plistPath = config.infoPlistPath
        let projPath = config.xcodeprojPath
        let iconsPath = iconsFolderPath
        let mode = self.mode
        let specs = self.specs

        if mode != .removeAll {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: iconsPath, isDirectory: &isDir),
                  isDir.boolValue else {
                appendLog("Icons folder does not exist or is not a directory")
                return
            }
        }

        let logger: @Sendable (String) -> Void = { [weak self] msg in
            Task { @MainActor in
                self?.appendLog(msg)
            }
        }

        appendLog("Started (\(mode.rawValue))")

        await Task.detached(priority: .userInitiated) {
            do {
                let pbxprojPath = try Tool.locatePBXProj(xcodeprojPath: projPath)

                switch mode {
                case .removeAll:
                    try Tool.cleanupExistingAltIconSets(
                        xcassetsFolderPath: assetsPath,
                        logger: logger
                    )
                    _ = try Tool.updateInfoPlist(
                        withNewAltIcons: [],
                        mode: .replace,
                        infoPlistPath: plistPath,
                        logger: logger
                    )
                    try Tool.updatePBXProj(
                        withAltIcons: [],
                        pbxprojPath: pbxprojPath,
                        logger: logger
                    )

                case .replace, .add:
                    if mode == .replace {
                        try Tool.cleanupExistingAltIconSets(
                            xcassetsFolderPath: assetsPath,
                            logger: logger
                        )
                    }

                    try Tool.addAppIcons(
                        mode: mode,
                        iconsFolderPath: iconsPath,
                        xcassetsFolderPath: assetsPath,
                        logger: logger
                    )

                    try await Tool.resizeAppIcons(
                        xcassetsFolderPath: assetsPath,
                        specs: specs,
                        logger: logger
                    )

                    let newAltIconNames = try Tool.collectIconNames(
                        iconsFolderPath: iconsPath
                    )
                    let finalAlt = try Tool.updateInfoPlist(
                        withNewAltIcons: newAltIconNames,
                        mode: mode,
                        infoPlistPath: plistPath,
                        logger: logger
                    )
                    try Tool.updatePBXProj(
                        withAltIcons: finalAlt,
                        pbxprojPath: pbxprojPath,
                        logger: logger
                    )
                }

                logger("Process completed")
            } catch {
                logger("Error: \(error.localizedDescription)")
            }
        }.value
    }

    // MARK: - Remove Single Icon

    func removeIcon(_ icon: AppIconEntry) {
        guard !icon.isPrimary, let config = projectConfig else { return }

        let logger: @Sendable (String) -> Void = { [weak self] msg in
            Task { @MainActor in
                self?.appendLog(msg)
            }
        }

        do {
            try FileManager.default.removeItem(at: icon.setURL)
            appendLog("Removed: \(icon.name).appiconset")

            let remaining = icons
                .filter { !$0.isPrimary && $0.name != icon.name }
                .map(\.name)

            _ = try Tool.updateInfoPlist(
                withNewAltIcons: remaining,
                mode: .replace,
                infoPlistPath: config.infoPlistPath,
                logger: logger
            )

            let pbxprojPath = try Tool.locatePBXProj(xcodeprojPath: config.xcodeprojPath)
            try Tool.updatePBXProj(
                withAltIcons: remaining,
                pbxprojPath: pbxprojPath,
                logger: logger
            )

            isLogPanelVisible = true
            loadIcons()
        } catch {
            appendLog("Error: \(error.localizedDescription)")
            isLogPanelVisible = true
        }
    }

    // MARK: - Make Primary

    func makePrimary(_ icon: AppIconEntry, action: PrimarySwapAction, customName: String) {
        guard !icon.isPrimary, let config = projectConfig else { return }
        guard let primaryIcon = icons.first(where: { $0.isPrimary }) else {
            appendLog("No primary icon found in the project")
            isLogPanelVisible = true
            return
        }

        let fm = FileManager.default
        let logger: @Sendable (String) -> Void = { [weak self] msg in
            Task { @MainActor in self?.appendLog(msg) }
        }

        do {
            let primaryParent = primaryIcon.setURL.deletingLastPathComponent()
            let altParent = icon.setURL.deletingLastPathComponent()

            switch action {
            case .swap:
                let tempURL = primaryParent.appendingPathComponent("_swap_temp_.appiconset")
                try fm.moveItem(at: primaryIcon.setURL, to: tempURL)
                try fm.moveItem(at: icon.setURL, to: primaryParent.appendingPathComponent("AppIcon.appiconset"))
                try fm.moveItem(at: tempURL, to: altParent.appendingPathComponent("\(icon.name).appiconset"))
                appendLog("Swapped \"\(icon.name)\" with primary icon")

            case .removeOldPrimary:
                try fm.removeItem(at: primaryIcon.setURL)
                try fm.moveItem(at: icon.setURL, to: primaryParent.appendingPathComponent("AppIcon.appiconset"))
                appendLog("Removed old primary, promoted \"\(icon.name)\"")

                let remaining = icons.filter { !$0.isPrimary && $0.name != icon.name }.map(\.name)
                _ = try Tool.updateInfoPlist(
                    withNewAltIcons: remaining, mode: .replace,
                    infoPlistPath: config.infoPlistPath, logger: logger
                )
                let pbxprojPath = try Tool.locatePBXProj(xcodeprojPath: config.xcodeprojPath)
                try Tool.updatePBXProj(withAltIcons: remaining, pbxprojPath: pbxprojPath, logger: logger)

            case .demoteToAlternate:
                let name = customName.trimmingCharacters(in: .whitespaces)
                let newAltURL = altParent.appendingPathComponent("\(name).appiconset")
                try fm.moveItem(at: primaryIcon.setURL, to: newAltURL)
                try fm.moveItem(at: icon.setURL, to: primaryParent.appendingPathComponent("AppIcon.appiconset"))
                appendLog("Demoted primary to \"\(name)\", promoted \"\(icon.name)\"")

                var remaining = icons.filter { !$0.isPrimary && $0.name != icon.name }.map(\.name)
                remaining.append(name)
                _ = try Tool.updateInfoPlist(
                    withNewAltIcons: remaining, mode: .replace,
                    infoPlistPath: config.infoPlistPath, logger: logger
                )
                let pbxprojPath = try Tool.locatePBXProj(xcodeprojPath: config.xcodeprojPath)
                try Tool.updatePBXProj(withAltIcons: remaining, pbxprojPath: pbxprojPath, logger: logger)
            }

            isLogPanelVisible = true
            loadIcons()
        } catch {
            appendLog("Error: \(error.localizedDescription)")
            isLogPanelVisible = true
        }
    }

    // MARK: - Validation

    func validateIcons() {
        guard let config = projectConfig,
              selectedXcassetsIndex < config.xcassetsPaths.count else {
            validationReport = nil
            return
        }
        isValidating = true
        let path = config.xcassetsPaths[selectedXcassetsIndex]
        validationReport = IconValidator.validateAllIconSets(xcassetsPath: path)
        isValidating = false
    }

    func fixIcons() async {
        guard let config = projectConfig,
              selectedXcassetsIndex < config.xcassetsPaths.count else { return }

        isFixing = true
        isLogPanelVisible = true
        let path = config.xcassetsPaths[selectedXcassetsIndex]

        let logger: @Sendable (String) -> Void = { [weak self] msg in
            Task { @MainActor in
                self?.appendLog(msg)
            }
        }

        appendLog("Fixing icon issues...")

        let report = await Task.detached(priority: .userInitiated) {
            IconValidator.fixAllIcons(xcassetsPath: path, logger: logger)
        }.value

        validationReport = report
        loadIcons()
        isFixing = false

        if report.isValid {
            appendLog("All icons are now App Store Connect safe")
        } else {
            appendLog("Some issues could not be auto-fixed (\(report.totalErrors) error(s) remaining)")
        }
    }

    // MARK: - Logging

    func appendLog(_ message: String) {
        logs.append("\(message)\n")
    }
}
