import Foundation
import Darwin

/// Every distinct pgid in the descendant tree rooted at `root`, including
/// `root`'s own pgid. Catches children that escape into their own session
/// via `setsid()`.
func descendantProcessGroupIDs(of root: pid_t) -> Set<pid_t> {
    TraceLog.enter([("root", Int(root))])
    var pgids: Set<pid_t> = []
    var toVisit: [pid_t] = [root]
    var visited: Set<pid_t> = []

    while let pid = toVisit.popLast() {
        TraceLog.point("popLast", [("pid", Int(pid)), ("toVisitRemaining", toVisit.count)])
        if visited.contains(pid) {
            TraceLog.point("already-visited", [("pid", Int(pid))])
            continue
        }
        visited.insert(pid)

        let pgid = getpgid(pid)
        if pgid > 0 {
            TraceLog.point("pgid>0", [("pid", Int(pid)), ("pgid", Int(pgid))])
            pgids.insert(pgid)
        }

        let bytesNeeded = proc_listchildpids(pid, nil, 0)
        if bytesNeeded <= 0 {
            TraceLog.point("bytesNeeded<=0", [("pid", Int(pid)), ("bytesNeeded", Int(bytesNeeded))])
            continue
        }
        let count = Int(bytesNeeded) / MemoryLayout<pid_t>.size
        var buffer = [pid_t](repeating: 0, count: count)
        let actualBytes = buffer.withUnsafeMutableBufferPointer { ptr in
            proc_listchildpids(pid, ptr.baseAddress, Int32(bytesNeeded))
        }
        if actualBytes <= 0 {
            TraceLog.point("actualBytes<=0", [("pid", Int(pid)), ("actualBytes", Int(actualBytes))])
            continue
        }
        let actualCount = Int(actualBytes) / MemoryLayout<pid_t>.size
        TraceLog.point("children", [("pid", Int(pid)), ("childCount", actualCount)])
        for child in buffer.prefix(actualCount) where child > 0 {
            TraceLog.point("enqueue-child", [("parent", Int(pid)), ("child", Int(child))])
            toVisit.append(child)
        }
    }

    TraceLog.exit([("pgidCount", pgids.count)])
    return pgids
}

/// Tracks live child pgids spawned by `ShellCommand` so the server shutdown
/// handler can reap them on signal or transport close. NSLock-guarded so it
/// is safe to read from a signal handler.
public enum ChildProcessRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pgids: [pid_t] = []

    public static func register(_ pgid: pid_t) {
        TraceLog.enter([("pgid", Int(pgid))])
        lock.lock()
        defer { lock.unlock() }
        if !pgids.contains(pgid) {
            TraceLog.point("appending", [("pgid", Int(pgid)), ("count", pgids.count)])
            pgids.append(pgid)
        } else {
            TraceLog.point("already-contains", [("pgid", Int(pgid))])
        }
        TraceLog.exit([("count", pgids.count)])
    }

    public static func unregister(_ pgid: pid_t) {
        TraceLog.enter([("pgid", Int(pgid))])
        lock.lock()
        defer { lock.unlock() }
        pgids.removeAll { $0 == pgid }
        TraceLog.exit([("count", pgids.count)])
    }

    public static func snapshot() -> [pid_t] {
        TraceLog.enter()
        lock.lock()
        defer { lock.unlock() }
        TraceLog.exit([("count", pgids.count)])
        return pgids
    }
}

/// SIGTERM every registered child and any escaped descendants, wait briefly,
/// then SIGKILL anything still alive. Synchronous; safe in shutdown paths
/// where Swift Concurrency may be unavailable.
public func terminateAllChildProcessGroups(graceSeconds: UInt32 = 1) {
    TraceLog.enter([("graceSeconds", Int(graceSeconds))])
    let roots = ChildProcessRegistry.snapshot()
    guard !roots.isEmpty else {
        TraceLog.point("roots-empty")
        TraceLog.exit()
        return
    }
    TraceLog.point("roots", [("rootCount", roots.count)])

    var allGroups: Set<pid_t> = []
    for root in roots {
        allGroups.formUnion(descendantProcessGroupIDs(of: root))
    }

    TraceLog.point("sigterm-loop", [("pgroupCount", allGroups.count)])
    for pgid in allGroups {
        TraceLog.point("sigterm", [("pgid", Int(pgid))])
        _ = kill(-pgid, SIGTERM)
    }

    if graceSeconds > 0 {
        TraceLog.point("grace-sleep", [("graceSeconds", Int(graceSeconds))])
        sleep(graceSeconds)
    }

    // Re-walk: descendants may have changed since SIGTERM.
    var remaining: Set<pid_t> = []
    for root in ChildProcessRegistry.snapshot() {
        remaining.formUnion(descendantProcessGroupIDs(of: root))
    }
    TraceLog.point("sigkill-loop", [("pgroupCount", remaining.count)])
    for pgid in remaining {
        TraceLog.point("sigkill", [("pgid", Int(pgid))])
        _ = kill(-pgid, SIGKILL)
    }
    TraceLog.exit()
}
