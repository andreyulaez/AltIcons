import SwiftUI
import AppKit

// MARK: - Update Mode

enum UpdateMode: String, CaseIterable, Identifiable, Equatable {
    case add = "Add"
    case replace = "Replace"
    case removeAll = "Remove All"
    var id: String { rawValue }
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
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Project View

struct ProjectView: View {
    @ObservedObject var viewModel: ViewModel
    @State private var showEditSheet = false
    @State private var iconToDelete: AppIconEntry?
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
        .onChange(of: viewModel.selectedXcassetsIndex) {
            viewModel.loadIcons()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if let config = viewModel.projectConfig {
                Text(config.rootURL.lastPathComponent)
                    .font(.headline)
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
                    Label("Open Different Project\u{2026}", systemImage: "folder")
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
                        IconCard(icon: icon) {
                            iconToDelete = icon
                        }
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
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
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

                if isHovering && !icon.isPrimary {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.red)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
                }
            }

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
            return
        }
        let path = config.xcassetsPaths[selectedXcassetsIndex]
        icons = ProjectDiscovery.loadIconEntries(xcassetsPath: path)
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

    // MARK: - Logging

    func appendLog(_ message: String) {
        logs.append("\(message)\n")
    }
}
