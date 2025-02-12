import SwiftUI
import CoreGraphics

struct ContentView: View {
    @StateObject private var viewModel = ViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Icons Folder Path", text: $viewModel.iconsFolderPath)
                Button("Browse") {
                    viewModel.selectFolder(forIcons: true)
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
                Task {
                    await viewModel.run()
                }
            }
            ScrollView {
                Text(viewModel.logs)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.05))
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }
}

@MainActor
final class ViewModel: ObservableObject {
    @Published var iconsFolderPath = ""
    @Published var xcassetsFolderPath = ""
    @Published var infoPlistPath = ""
    @Published var xcodeprojPath = ""
    @Published var logs = ""
    
    private var fileManager: FileManager { .default }
    private var pbxprojPath: String = ""
    
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
    
    func run() async {
        logs.removeAll()
        guard validatePaths() else { return }
        
        do {
            try locatePBXProj()
        } catch {
            appendLog("Error locating pbxproj: \(error.localizedDescription)")
            return
        }
        
        do {
            try addAppIcons()
            try await resizeAppIcons()
            let altIconNames = try collectIconNames()
            try updateInfoPlist(withAltIcons: altIconNames)
            try updatePBXProj(withAltIcons: altIconNames)
            appendLog("Process completed")
        } catch {
            appendLog("Error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Validation
    
    func validatePaths() -> Bool {
        var isDir: ObjCBool = false
        
        guard fileManager.fileExists(atPath: iconsFolderPath, isDirectory: &isDir), isDir.boolValue else {
            appendLog("Icons folder path does not exist or is not a directory")
            return false
        }
        
        guard fileManager.fileExists(atPath: xcassetsFolderPath, isDirectory: &isDir), isDir.boolValue else {
            appendLog(".xcassets path does not exist or is not a directory")
            return false
        }
        
        guard fileManager.fileExists(atPath: infoPlistPath, isDirectory: &isDir), !isDir.boolValue else {
            appendLog("Info.plist path does not exist or is a directory")
            return false
        }
        
        guard fileManager.fileExists(atPath: xcodeprojPath, isDirectory: &isDir), isDir.boolValue,
              xcodeprojPath.hasSuffix(".xcodeproj") else {
            appendLog(".xcodeproj path is invalid or not a directory")
            return false
        }
        
        return true
    }
    
    func locatePBXProj() throws {
        let xcodeprojURL = URL(fileURLWithPath: xcodeprojPath)
        let pbxURL = xcodeprojURL.appendingPathComponent("project.pbxproj")
        
        if !fileManager.fileExists(atPath: pbxURL.path) {
            throw NSError(domain: "PBXProjNotFound", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not find project.pbxproj inside .xcodeproj"])
        }
        pbxprojPath = pbxURL.path
    }
    
    // MARK: - Gathering icon names
    
    func collectIconNames() throws -> [String] {
        let files = try fileManager.contentsOfDirectory(atPath: iconsFolderPath).filter {
            let ext = URL(fileURLWithPath: $0).pathExtension.lowercased()
            return ext == "png" || ext == "jpg"
        }
        let names = files.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
        return names.filter { $0.lowercased() != "appicon" }
    }
    
    // MARK: - Add app icons
    
    func addAppIcons() throws {
        let files = try fileManager.contentsOfDirectory(atPath: iconsFolderPath).filter {
            let ext = URL(fileURLWithPath: $0).pathExtension.lowercased()
            return ext == "png" || ext == "jpg"
        }
        if files.isEmpty {
            appendLog("No PNG or JPG files found in the icons folder")
            throw NSError(domain: "NoIconsFound", code: 0)
        }
        for file in files {
            let fileName = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
            let sourceFilePath = URL(fileURLWithPath: iconsFolderPath).appendingPathComponent(file)
            let appIconSetName = fileName + ".appiconset"
            let appIconSetFolder = URL(fileURLWithPath: xcassetsFolderPath).appendingPathComponent(appIconSetName)
            
            if !fileManager.fileExists(atPath: appIconSetFolder.path) {
                try fileManager.createDirectory(at: appIconSetFolder, withIntermediateDirectories: true)
                appendLog("Created folder: \(appIconSetFolder.lastPathComponent)")
            } else {
                appendLog("Folder already exists: \(appIconSetFolder.lastPathComponent)")
            }
            let destFile = appIconSetFolder.appendingPathComponent(file)
            if fileManager.fileExists(atPath: destFile.path) {
                try fileManager.removeItem(at: destFile)
            }
            try fileManager.copyItem(at: sourceFilePath, to: destFile)
            appendLog("Copied file: \(file)")
            
            let contents: [String: Any] = [
                "images": [
                    [
                        "filename": file,
                        "idiom": "universal",
                        "platform": "ios",
                        "size": "1024x1024"
                    ]
                ],
                "info": [
                    "author": "xcode",
                    "version": 1
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: contents, options: .prettyPrinted)
            let contentsURL = appIconSetFolder.appendingPathComponent("Contents.json")
            try data.write(to: contentsURL)
            appendLog("Created Contents.json for \(fileName).appiconset")
        }
    }
    
    // MARK: - Resize icons
    
    func resizeAppIcons() async throws {
        let sets = try findAllAppIconSets(in: URL(fileURLWithPath: xcassetsFolderPath))
        for setURL in sets {
            try await resizeAppIconSet(at: setURL)
        }
    }
    
    func findAllAppIconSets(in folder: URL) throws -> [URL] {
        var results = [URL]()
        let items = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        for item in items {
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: item.path, isDirectory: &isDir)
            if isDir.boolValue {
                if item.pathExtension == "appiconset" {
                    let contentsPath = item.appendingPathComponent("Contents.json")
                    if fileManager.fileExists(atPath: contentsPath.path) {
                        results.append(item)
                    }
                } else {
                    let subResults = try findAllAppIconSets(in: item)
                    results.append(contentsOf: subResults)
                }
            }
        }
        return results
    }
    
    func resizeAppIconSet(at appIconSetURL: URL) async throws {
        let contentsURL = appIconSetURL.appendingPathComponent("Contents.json")
        let data = try Data(contentsOf: contentsURL)
        guard let originalJSON = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let images = originalJSON["images"] as? [[String: Any]] else {
            throw NSError(domain: "InvalidContents", code: 0)
        }
        guard let originalEntry = images.first(where: { ($0["size"] as? String) == "1024x1024" }),
              let originalFileName = originalEntry["filename"] as? String, !originalFileName.isEmpty else {
            throw NSError(domain: "No1024Entry", code: 0)
        }
        let originalFile = appIconSetURL.appendingPathComponent(originalFileName)
        if !fileManager.fileExists(atPath: originalFile.path) {
            throw NSError(domain: "OriginalFileMissing", code: 0)
        }
        let newImages = try await generateAllSizes(from: originalFile)
        let finalImages = newImages.map { $0.jsonEntry }
        
        let finalJSON: [String: Any] = [
            "images": finalImages,
            "info": [
                "author": "xcode",
                "version": 1
            ]
        ]
        let finalData = try JSONSerialization.data(withJSONObject: finalJSON, options: .prettyPrinted)
        try finalData.write(to: contentsURL)
        
        let allFiles = try fileManager.contentsOfDirectory(atPath: appIconSetURL.path)
        let usedFileNames = Set(newImages.map { $0.fileName })
        for f in allFiles where f != "Contents.json" && !usedFileNames.contains(f) {
            let delPath = appIconSetURL.appendingPathComponent(f)
            try fileManager.removeItem(at: delPath)
        }
        appendLog("Updated .appiconset => \(appIconSetURL.lastPathComponent)")
    }
    
    func generateAllSizes(from originalFile: URL) async throws -> [ResizedImage] {
        var result = [ResizedImage]()
        for spec in specs {
            if spec.size == "1024x1024" && spec.scale == nil {
                let fileName = originalFile.lastPathComponent
                result.append(ResizedImage(fileName: fileName, idiom: spec.idiom, platform: spec.platform, size: spec.size, scale: spec.scale))
            } else {
                let newURL = try await resizeImage(originalFile, spec: spec)
                result.append(ResizedImage(fileName: newURL.lastPathComponent, idiom: spec.idiom, platform: spec.platform, size: spec.size, scale: spec.scale))
            }
        }
        return result
    }
    
    func resizeImage(_ file: URL, spec: ImageSpec) async throws -> URL {
        let imageName = "icon-\(spec.size.replacingOccurrences(of: ".", with: "_"))\(spec.scale.map{"@\($0)"} ?? "").png"
        let targetURL = file.deletingLastPathComponent().appendingPathComponent(imageName)
        
        let sizeVals = spec.size.split(separator: "x").compactMap { Double($0) }
        guard sizeVals.count == 2 else { throw NSError(domain: "SizeError", code: 0) }
        let scaleVal = spec.scale?.replacingOccurrences(of: "x", with: "") ?? "1"
        guard let scaleNumber = Double(scaleVal) else { throw NSError(domain: "ScaleError", code: 0) }
        
        let width = Int(sizeVals[0] * scaleNumber)
        let height = Int(sizeVals[1] * scaleNumber)
        
        guard let cgImage = loadCGImage(file) else {
            throw NSError(domain: "CGImageLoadError", code: 0)
        }
        guard let resizedCG = resizeCGImage(cgImage, width: width, height: height) else {
            throw NSError(domain: "CGImageResizeError", code: 0)
        }
        let bitmapRep = NSBitmapImageRep(cgImage: resizedCG)
        bitmapRep.size = NSSize(width: width, height: height)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PNGWriteError", code: 0)
        }
        try pngData.write(to: targetURL)
        return targetURL
    }
    
    func loadCGImage(_ url: URL) -> CGImage? {
        guard let dataProvider = CGDataProvider(url: url as CFURL),
              let imageSource = CGImageSourceCreateWithDataProvider(dataProvider, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }
        return image
    }
    
    func resizeCGImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let colorSpace = image.colorSpace,
              let context = CGContext(data: nil,
                                     width: width,
                                     height: height,
                                     bitsPerComponent: image.bitsPerComponent,
                                     bytesPerRow: 0,
                                     space: colorSpace,
                                     bitmapInfo: image.bitmapInfo.rawValue)
        else { return nil }
        
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return context.makeImage()
    }
    
    // MARK: - Update Info.plist (text method)
    
    func updateInfoPlist(withAltIcons altIcons: [String]) throws {
        let plistURL = URL(fileURLWithPath: infoPlistPath)
        var text = try String(contentsOf: plistURL, encoding: .utf8)
        text = removeCFBundleIconsBlock(from: text)
        
        let altIconsXML = altIcons.map { altName -> String in
            """
            <key>\(altName)</key>
            <dict>
                <key>CFBundleIconFiles</key>
                <array>
                    <string>\(altName)</string>
                </array>
                <key>UIPrerenderedIcon</key>
                <false/>
            </dict>
            """
        }.joined(separator: "\n")
        
        let bundleIconsXML = """
        <key>CFBundleIcons</key>
        <dict>
            <key>CFBundlePrimaryIcon</key>
            <dict>
                <key>CFBundleIconFiles</key>
                <array>
                    <string>AppIcon</string>
                </array>
                <key>UIPrerenderedIcon</key>
                <false/>
            </dict>
            <key>CFBundleAlternateIcons</key>
            <dict>
        \(altIconsXML)
            </dict>
        </dict>
        """
        
        if let range = text.range(of: "</dict>", options: [.backwards]) {
            let insertIndex = range.lowerBound
            text.insert(contentsOf: bundleIconsXML + "\n", at: insertIndex)
        }
        
        try text.write(to: plistURL, atomically: true, encoding: .utf8)
        appendLog("Updated Info.plist with CFBundleIcons in desired order")
    }
    
    private func removeCFBundleIconsBlock(from plistText: String) -> String {
        var text = plistText
        while let startRange = text.range(of: "<key>CFBundleIcons</key>"),
              let dictOpenRange = text.range(of: "<dict>", range: startRange.upperBound..<text.endIndex),
              let endRange = text.range(of: "</dict>", range: dictOpenRange.upperBound..<text.endIndex) {
            let removeRange = startRange.lowerBound..<endRange.upperBound
            text.removeSubrange(removeRange)
        }
        return text
    }
    
    // MARK: - Update .pbxproj for all configurations
    
    func updatePBXProj(withAltIcons altIcons: [String]) throws {
        let pbxprojURL = URL(fileURLWithPath: pbxprojPath)
        var content = try String(contentsOf: pbxprojURL, encoding: .utf8)
        let joinedAltIcons = altIcons.joined(separator: " ")
        
        var lines = content.components(separatedBy: .newlines)
        var inBuildSettingsBlock = false
        var blockIndent = 0
        var i = 0
        
        while i < lines.count {
            let line = lines[i]
            
            if line.contains("buildSettings = {") {
                inBuildSettingsBlock = true
                blockIndent = line.prefix(while: { $0 == "\t" || $0 == " " }).count + 1
            }
            
            if inBuildSettingsBlock, line.contains("};") {
                let indentStr = String(repeating: "\t", count: (blockIndent / 4))
                
                var j = i - 1
                while j >= 0 {
                    if lines[j].contains("ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS")
                        || lines[j].contains("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES") {
                        lines.remove(at: j)
                        i -= 1
                    } else if lines[j].contains("buildSettings = {") {
                        break
                    }
                    j -= 1
                }
                
                lines.insert("\(indentStr)ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES;", at: i)
                i += 1
                lines.insert("\(indentStr)ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = \"\(joinedAltIcons)\";", at: i)
                i += 1
                
                inBuildSettingsBlock = false
                i += 1
                continue
            }
            
            i += 1
        }
        
        content = lines.joined(separator: "\n")
        try content.write(to: pbxprojURL, atomically: true, encoding: .utf8)
        
        appendLog("Updated .pbxproj for ALL configurations (ASSETCATALOG_COMPILER_* settings)")
    }
    
    // MARK: - Logging
    
    func appendLog(_ message: String) {
        DispatchQueue.main.async {
            self.logs.append("\(message)\n")
        }
    }
}
