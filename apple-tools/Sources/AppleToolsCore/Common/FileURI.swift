import Foundation

enum FileURI {
    static func fromPath(_ path: String) -> String {
        TraceLog.enter([("path", path)])
        if path.hasPrefix("/") {
            TraceLog.point("absolute")
        } else {
            TraceLog.point("relative")
        }
        let absolutePath = path.hasPrefix("/") ? path : FileManager.default.currentDirectoryPath + "/" + path
        let uri = "file://" + absolutePath
        TraceLog.exit([("uri", uri)])
        return uri
    }

    static func toPath(_ uri: String) -> String {
        TraceLog.enter([("uri", uri)])
        if uri.hasPrefix("file://") {
            let path = String(uri.dropFirst("file://".count))
            TraceLog.exit([("path", path)])
            return path
        }
        TraceLog.exit([("path", uri)])
        return uri
    }
}
