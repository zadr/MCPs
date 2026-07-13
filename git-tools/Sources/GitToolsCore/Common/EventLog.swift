import Foundation
import Darwin

/// Append-only JSONL event log for external monitors. One line per event,
/// written with a single write(2). Best-effort; errors are silently dropped.
public enum EventLog {
    public static let path = "/tmp/apple-tools-mcp.jsonl"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var fd: Int32 = -1

    private static func openIfNeeded() -> Int32 {
        if fd >= 0 { return fd }
        let flags = O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC
        let mode: mode_t = 0o644
        let opened = open(path, flags, mode)
        if opened < 0 { return -1 }
        fd = opened
        return fd
    }

    /// Write a single JSON line. `fields` keys must produce JSON-encodable
    /// values; we encode Strings, Ints, Doubles, Bools, and nil. Everything
    /// else is stringified.
    public static func write(event: String, _ fields: [(String, Any?)] = []) {
        lock.lock()
        defer { lock.unlock() }
        let descriptor = openIfNeeded()
        if descriptor < 0 { return }

        var obj: [String: Any] = [
            "ts": Date().timeIntervalSince1970,
            "event": event,
            "pid": Int(getpid()),
        ]
        for (k, v) in fields {
            obj[k] = jsonEncodable(v)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else {
            return
        }
        var line = data
        line.append(0x0a) // newline
        _ = line.withUnsafeBytes { ptr -> ssize_t in
            guard let base = ptr.baseAddress else { return 0 }
            return Darwin.write(descriptor, base, line.count)
        }
    }

    private static func jsonEncodable(_ v: Any?) -> Any {
        guard let v else { return NSNull() }
        switch v {
        case is String, is Int, is Int32, is Int64, is UInt, is UInt32, is UInt64,
             is Double, is Float, is Bool, is NSNull:
            return v
        default:
            return String(describing: v)
        }
    }
}
