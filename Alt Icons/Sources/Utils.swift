import Foundation
import SwiftUI
import CoreGraphics
import AppKit
import ImageIO

enum Tool {
    static let fm = FileManager.default
    
    // Paths / discovery
    static func locatePBXProj(xcodeprojPath: String) throws -> String {
        let pbxURL = URL(fileURLWithPath: xcodeprojPath)
            .appendingPathComponent("project.pbxproj")
        
        guard fm.fileExists(atPath: pbxURL.path) else {
            throw NSError(
                domain: "PBXProjNotFound",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Could not find project.pbxproj inside .xcodeproj"]
            )
        }
        return pbxURL.path
    }
    
    static func collectIconNames(iconsFolderPath: String) throws -> [String] {
        let files = try fm.contentsOfDirectory(atPath: iconsFolderPath).filter {
            let ext = URL(fileURLWithPath: $0).pathExtension.lowercased()
            return ext == "png" || ext == "jpg"
        }
        let names = files.map {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
        }
        return names.filter { $0.lowercased() != "appicon" }
    }
    
    // Remove existing alt icon sets (keep primary AppIcon)
    static func cleanupExistingAltIconSets(
        xcassetsFolderPath: String,
        logger: @Sendable (String) -> Void
    ) throws {
        let root = URL(fileURLWithPath: xcassetsFolderPath)
        let sets = try findAllAppIconSets(in: root)
        
        var removed = 0
        for url in sets where url.lastPathComponent != "AppIcon.appiconset" {
            try fm.removeItem(at: url)
            removed += 1
            logger("Removed alt icon set: \(url.lastPathComponent)")
        }
        logger("Cleanup done. Removed \(removed) alt icon set(s)")
    }
    
    // Add/Replace app icons (copy + initial Contents.json)
    static func addAppIcons(
        mode: UpdateMode,
        iconsFolderPath: String,
        xcassetsFolderPath: String,
        logger: @Sendable (String) -> Void
    ) throws {
        let files = try fm.contentsOfDirectory(atPath: iconsFolderPath).filter {
            let ext = URL(fileURLWithPath: $0).pathExtension.lowercased()
            return ext == "png" || ext == "jpg"
        }
        
        guard !files.isEmpty else {
            logger("No PNG or JPG files found in the icons folder")
            throw NSError(domain: "NoIconsFound", code: 0)
        }
        
        for file in files {
            let fileName = URL(fileURLWithPath: file)
                .deletingPathExtension()
                .lastPathComponent
            
            let source = URL(fileURLWithPath: iconsFolderPath)
                .appendingPathComponent(file)
            
            let setName = fileName + ".appiconset"
            let setFolder = URL(fileURLWithPath: xcassetsFolderPath)
                .appendingPathComponent(setName)
            
            var shouldCreate = true
            if fm.fileExists(atPath: setFolder.path) {
                if mode == .add {
                    shouldCreate = false
                    logger("Icon set exists, skip copying: \(setName)")
                } else {
                    try fm.removeItem(at: setFolder)
                    logger("Removed existing icon set: \(setName)")
                }
            }
            
            if shouldCreate {
                try fm.createDirectory(at: setFolder, withIntermediateDirectories: true)
                
                let destFile = setFolder.appendingPathComponent(file)
                try? fm.removeItem(at: destFile)
                try fm.copyItem(at: source, to: destFile)
                logger("Copied file: \(file)")
                
                let contents: [String: Any] = [
                    "images": [[
                        "filename": file,
                        "idiom": "universal",
                        "platform": "ios",
                        "size": "1024x1024"
                    ]],
                    "info": [
                        "author": "xcode",
                        "version": 1
                    ]
                ]
                
                let data = try JSONSerialization.data(withJSONObject: contents, options: .prettyPrinted)
                try data.write(to: setFolder.appendingPathComponent("Contents.json"))
                logger("Created Contents.json for \(setName)")
            }
        }
    }
    
    // Resize pipeline
    static func resizeAppIcons(
        xcassetsFolderPath: String,
        specs: [ImageSpec],
        logger: @Sendable (String) -> Void
    ) async throws {
        let sets = try findAllAppIconSets(in: URL(fileURLWithPath: xcassetsFolderPath))
        for setURL in sets {
            try await resizeAppIconSet(at: setURL, specs: specs, logger: logger)
        }
    }
    
    static func findAllAppIconSets(in folder: URL) throws -> [URL] {
        var results = [URL]()
        let items = try fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        
        for item in items {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDir)
            if isDir.boolValue {
                if item.pathExtension == "appiconset" {
                    let contentsPath = item.appendingPathComponent("Contents.json")
                    if fm.fileExists(atPath: contentsPath.path) {
                        results.append(item)
                    }
                } else {
                    let sub = try findAllAppIconSets(in: item)
                    results.append(contentsOf: sub)
                }
            }
        }
        return results
    }
    
    static func resizeAppIconSet(
        at appIconSetURL: URL,
        specs: [ImageSpec],
        logger: @Sendable (String) -> Void
    ) async throws {
        let contentsURL = appIconSetURL.appendingPathComponent("Contents.json")
        let data = try Data(contentsOf: contentsURL)
        
        guard let originalJSON = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let images = originalJSON["images"] as? [[String: Any]] else {
            throw NSError(domain: "InvalidContents", code: 0)
        }
        
        guard let originalEntry = images.first(where: { ($0["size"] as? String) == "1024x1024" }),
              let originalFileName = originalEntry["filename"] as? String,
              !originalFileName.isEmpty else {
            throw NSError(domain: "No1024Entry", code: 0)
        }
        
        let originalFile = appIconSetURL.appendingPathComponent(originalFileName)
        guard fm.fileExists(atPath: originalFile.path) else {
            throw NSError(domain: "OriginalFileMissing", code: 0)
        }
        
        let newImages = try await generateAllSizes(from: originalFile, specs: specs)
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
        
        let allFiles = try fm.contentsOfDirectory(atPath: appIconSetURL.path)
        let used = Set(newImages.map { $0.fileName })
        for f in allFiles where f != "Contents.json" && !used.contains(f) {
            try fm.removeItem(at: appIconSetURL.appendingPathComponent(f))
        }
        
        logger("Updated .appiconset => \(appIconSetURL.lastPathComponent)")
    }
    
    static func generateAllSizes(from originalFile: URL, specs: [ImageSpec]) async throws -> [ResizedImage] {
        var result = [ResizedImage]()
        for spec in specs {
            if spec.size == "1024x1024", spec.scale == nil {
                result.append(
                    ResizedImage(
                        fileName: originalFile.lastPathComponent,
                        idiom: spec.idiom,
                        platform: spec.platform,
                        size: spec.size,
                        scale: spec.scale
                    )
                )
            } else {
                let newURL = try await resizeImage(originalFile, spec: spec)
                result.append(
                    ResizedImage(
                        fileName: newURL.lastPathComponent,
                        idiom: spec.idiom,
                        platform: spec.platform,
                        size: spec.size,
                        scale: spec.scale
                    )
                )
            }
        }
        return result
    }
    
    static func resizeImage(_ file: URL, spec: ImageSpec) async throws -> URL {
        let sizeToken = spec.size.replacingOccurrences(of: ".", with: "_")
        let scaleToken = spec.scale.map { "@\($0)" } ?? ""
        let imageName = "icon-\(sizeToken)\(scaleToken).png"
        
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
    
    static func loadCGImage(_ url: URL) -> CGImage? {
        guard let dataProvider = CGDataProvider(url: url as CFURL),
              let imageSource = CGImageSourceCreateWithDataProvider(dataProvider, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }
        return image
    }
    
    static func resizeCGImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
    
    // Info.plist (merge/replace/remove)
    static func updateInfoPlist(
        withNewAltIcons newAltIcons: [String],
        mode: UpdateMode,
        infoPlistPath: String,
        logger: @Sendable (String) -> Void
    ) throws -> [String] {
        let url = URL(fileURLWithPath: infoPlistPath)
        let data = try Data(contentsOf: url)
        
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard var root = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        ) as? [String: Any] else {
            throw NSError(domain: "PlistReadError", code: 0)
        }
        
        var icons = (root["CFBundleIcons"] as? [String: Any]) ?? [:]
        
        var primary = (icons["CFBundlePrimaryIcon"] as? [String: Any]) ?? [:]
        primary["CFBundleIconFiles"] = ["AppIcon"]
        primary["UIPrerenderedIcon"] = false
        icons["CFBundlePrimaryIcon"] = primary
        
        var alt = (icons["CFBundleAlternateIcons"] as? [String: Any]) ?? [:]
        
        switch mode {
        case .replace:
            alt.removeAll()
            for name in newAltIcons {
                alt[name] = [
                    "CFBundleIconFiles": [name],
                    "UIPrerenderedIcon": false
                ]
            }
            logger("Info.plist: replaced alternate icons with \(newAltIcons.count) item(s)")
            
        case .add:
            var added = 0
            for name in newAltIcons {
                if alt.keys.contains(name) {
                    logger("Alternate icon \"\(name)\" already exists, skipped")
                } else {
                    alt[name] = [
                        "CFBundleIconFiles": [name],
                        "UIPrerenderedIcon": false
                    ]
                    added += 1
                }
            }
            logger("Info.plist: added \(added) new alternate icon(s)")
            
        case .removeAll:
            alt.removeAll()
            logger("Info.plist: removed all alternate icons")
        }
        
        icons["CFBundleAlternateIcons"] = alt.isEmpty ? [:] : alt
        root["CFBundleIcons"] = icons
        
        let out = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: format,
            options: 0
        )
        try out.write(to: url)
        logger("Updated Info.plist with CFBundleIcons")
        
        return Array(alt.keys).sorted()
    }
    
    // .pbxproj update
    static func updatePBXProj(
        withAltIcons altIcons: [String],
        pbxprojPath: String,
        logger: @Sendable (String) -> Void
    ) throws {
        var content = try String(
            contentsOf: URL(fileURLWithPath: pbxprojPath),
            encoding: .utf8
        )
        let joined = altIcons.joined(separator: " ")
        
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
                lines.insert("\(indentStr)ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = \"\(joined)\";", at: i)
                i += 1
                
                inBuildSettingsBlock = false
                i += 1
                continue
            }
            
            i += 1
        }
        
        content = lines.joined(separator: "\n")
        try content.write(
            to: URL(fileURLWithPath: pbxprojPath),
            atomically: true,
            encoding: .utf8
        )
        logger("Updated .pbxproj for ALL configurations (ASSETCATALOG_COMPILER_* settings)")
    }
}
