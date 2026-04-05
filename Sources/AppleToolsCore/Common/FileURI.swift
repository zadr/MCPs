import Foundation

enum FileURI {
    static func fromPath(_ path: String) -> String {
        let absolutePath = path.hasPrefix("/") ? path : FileManager.default.currentDirectoryPath + "/" + path
        return "file://" + absolutePath
    }

    static func toPath(_ uri: String) -> String {
        if uri.hasPrefix("file://") {
            return String(uri.dropFirst("file://".count))
        }
        return uri
    }
}
