import SwiftUI
import CoreGraphics

enum UpdateMode: String, CaseIterable, Identifiable, Equatable {
    case add = "Add"
    case replace = "Replace"
    case removeAll = "Remove All"
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var viewModel = ViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Mode", selection: $viewModel.mode) {
                ForEach(UpdateMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            
            if viewModel.mode != .removeAll {
                HStack {
                    TextField("Icons Folder Path", text: $viewModel.iconsFolderPath)
                    Button("Browse") {
                        viewModel.selectFolder(forIcons: true)
                    }
                }
            }
            
            HStack {
                TextField(".xcassets Path", text: $viewModel.xcassetsFolderPath)
                Button("Browse") {
                    viewModel.selectFolder(forIcons: false)
                }
            }
            
            HStack {
                TextField("Info.plist Path", text: $viewModel.infoPlistPath)
                Button("Browse") {
                    viewModel.selectSingleFile(forPlist: true)
                }
            }
            
            HStack {
                TextField(".xcodeproj Path", text: $viewModel.xcodeprojPath)
                Button("Browse") {
                    viewModel.selectSingleFile(forPlist: false)
                }
            }
            
            Button("Run") {
                Task { await viewModel.run() }
            }
            
            ScrollView {
                Text(viewModel.logs)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.05))
        }
        .padding()
        .frame(minWidth: 600, minHeight: 460)
        .animation(.spring(duration: 0.25), value: viewModel.mode)
    }
}

@MainActor
final class ViewModel: ObservableObject {
    @Published var iconsFolderPath = ""
    @Published var xcassetsFolderPath = ""
    @Published var infoPlistPath = ""
    @Published var xcodeprojPath = ""
    @Published var logs = ""
    @Published var mode: UpdateMode = .add
    
    private let fileManager = FileManager.default
    
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
    
    // MARK: - UI pickers
    func selectFolder(forIcons: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.urls.first {
            if forIcons {
                iconsFolderPath = url.path
            } else {
                xcassetsFolderPath = url.path
            }
        }
    }
    
    func selectSingleFile(forPlist: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.urls.first {
            if forPlist {
                infoPlistPath = url.path
            } else {
                xcodeprojPath = url.path
            }
        }
    }
    
    // MARK: - Run
    func run() async {
        logs.removeAll()
        guard validatePaths() else { return }
        
        // Capture inputs for background work
        let iconsPath = iconsFolderPath
        let assetsPath = xcassetsFolderPath
        let plistPath = infoPlistPath
        let projPath = xcodeprojPath
        let mode = self.mode
        let specs = self.specs
        
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
    
    // MARK: - Validation
    func validatePaths() -> Bool {
        var isDir: ObjCBool = false
        
        if mode != .removeAll {
            guard fileManager.fileExists(atPath: iconsFolderPath, isDirectory: &isDir),
                  isDir.boolValue else {
                appendLog("Icons folder path does not exist or is not a directory")
                return false
            }
        }
        
        guard fileManager.fileExists(atPath: xcassetsFolderPath, isDirectory: &isDir),
              isDir.boolValue else {
            appendLog(".xcassets path does not exist or is not a directory")
            return false
        }
        
        guard fileManager.fileExists(atPath: infoPlistPath, isDirectory: &isDir),
              !isDir.boolValue else {
            appendLog("Info.plist path does not exist or is a directory")
            return false
        }
        
        guard fileManager.fileExists(atPath: xcodeprojPath, isDirectory: &isDir),
              isDir.boolValue,
              xcodeprojPath.hasSuffix(".xcodeproj") else {
            appendLog(".xcodeproj path is invalid or not a directory")
            return false
        }
        
        return true
    }
    
    // MARK: - Logging
    func appendLog(_ message: String) {
        logs.append("\(message)\n")
    }
}
