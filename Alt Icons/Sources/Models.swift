import Foundation

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
