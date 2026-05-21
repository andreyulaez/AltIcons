import Foundation
import AppKit

struct ImageSpec {
    let idiom: String
    let platform: String?
    let size: String
    let scale: String?
}

struct ResizedImage {
    let fileName: String
    let idiom: String
    let platform: String?
    let size: String
    let scale: String?

    var jsonEntry: [String: String] {
        var result: [String: String] = [
            "idiom": idiom,
            "size": size,
            "filename": fileName
        ]
        if let platform = platform { result["platform"] = platform }
        if let scale = scale { result["scale"] = scale }
        return result
    }
}

struct ProjectConfig {
    let rootURL: URL
    let xcodeprojPath: String
    let infoPlistPath: String
    let xcassetsPaths: [String]
    let defaultXcassetsIndex: Int
}

struct AppIconEntry: Identifiable {
    var id: String { name }
    let name: String
    let setURL: URL
    let previewImage: NSImage?
    let isPrimary: Bool
}

enum ValidationSeverity: String {
    case error
    case warning
}

enum ValidationIssueKind: String {
    case missingFile
    case notPNG
    case corruptedImage
    case hasAlpha
    case invalidJSON
    case missingRequiredField
    case jpegReference
}

struct ValidationIssue: Identifiable {
    let id = UUID()
    let severity: ValidationSeverity
    let kind: ValidationIssueKind
    let file: String
    let message: String
}

struct IconSetValidationReport: Identifiable {
    let id = UUID()
    let setName: String
    let setURL: URL
    let issues: [ValidationIssue]
    var isValid: Bool { issues.isEmpty }
    var errorCount: Int { issues.filter { $0.severity == .error }.count }
    var warningCount: Int { issues.filter { $0.severity == .warning }.count }
}

struct FullValidationReport {
    let iconSetReports: [IconSetValidationReport]
    var isValid: Bool { iconSetReports.allSatisfy(\.isValid) }
    var totalErrors: Int { iconSetReports.reduce(0) { $0 + $1.errorCount } }
    var totalWarnings: Int { iconSetReports.reduce(0) { $0 + $1.warningCount } }
    var allIssues: [ValidationIssue] { iconSetReports.flatMap(\.issues) }
}
