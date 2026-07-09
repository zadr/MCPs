import Foundation
import Darwin

/// Process-wide, best-effort trace logger. OFF by default and effectively
/// free when off: every public call loads a single bool and returns before
/// allocating or formatting. Enabled by a tool passing a file path through
/// its arguments, after which exhaustive JSONL trace lines are appended to
/// that path. Modeled on EventLog's file-open/lock/JSONL-write pattern.
public enum TraceLog {
    // Fast disabled gate. A racy read is fine: tracing is best-effort, so the
    // worst case is dropping a line at the exact enable boundary.
    nonisolated(unsafe) private static var enabled = false

    private static let lock = NSLock()
    nonisolated(unsafe) private static var fd: Int32 = -1
    nonisolated(unsafe) private static var currentPath: String?

    /// Turns tracing on and points it at `path`. Idempotent for the same
    /// path; switches the destination fd when given a different path.
    public static func enable(path: String) {
        guard !path.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if enabled, currentPath == path, fd >= 0 { return }
        if fd >= 0 {
            close(fd)
            fd = -1
        }
        let flags = O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC
        let mode: mode_t = 0o644
        let opened = open(path, flags, mode)
        if opened < 0 { return }
        fd = opened
        currentPath = path
        enabled = true
    }

    public static func isEnabled() -> Bool {
        return enabled
    }

    /// Function entry. `fields` carries the parameter values.
    public static func enter(
        _ fields: [(String, Any?)] = [],
        function: String = #function,
        file: String = #fileID,
        line: Int = #line
    ) {
        if !enabled { return }
        writeLine(kind: "enter", function: function, file: file, line: line, extra: fields)
    }

    /// Function exit. `fields` carries the return value or outcome.
    public static func exit(
        _ fields: [(String, Any?)] = [],
        function: String = #function,
        file: String = #fileID,
        line: Int = #line
    ) {
        if !enabled { return }
        writeLine(kind: "exit", function: function, file: file, line: line, extra: fields)
    }

    /// Branch/decision point. `label` names the path taken; `fields` carry the
    /// deciding values.
    public static func point(
        _ label: String,
        _ fields: [(String, Any?)] = [],
        function: String = #function,
        file: String = #fileID,
        line: Int = #line
    ) {
        if !enabled { return }
        var extra: [(String, Any?)] = [("label", label)]
        extra.append(contentsOf: fields)
        writeLine(kind: "point", function: function, file: file, line: line, extra: extra)
    }

    private static func writeLine(
        kind: String,
        function: String,
        file: String,
        line: Int,
        extra: [(String, Any?)]
    ) {
        var obj: [String: Any] = [
            "ts": Date().timeIntervalSince1970,
            "pid": Int(getpid()),
            "thread": threadID(),
            "kind": kind,
            "function": function,
            "file": file,
            "line": line,
        ]
        for (k, v) in extra {
            obj[k] = jsonEncodable(v)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else {
            return
        }
        var out = data
        out.append(0x0a)

        lock.lock()
        defer { lock.unlock() }
        guard fd >= 0 else { return }
        _ = out.withUnsafeBytes { ptr -> ssize_t in
            guard let base = ptr.baseAddress else { return 0 }
            return Darwin.write(fd, base, out.count)
        }
    }

    private static func threadID() -> UInt64 {
        var tid: UInt64 = 0
        pthread_threadid_np(nil, &tid)
        return tid
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
