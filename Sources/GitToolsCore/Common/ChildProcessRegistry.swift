import Foundation
import Darwin

/// Every distinct pgid in the descendant tree rooted at `root`, including
/// `root`'s own pgid. Catches children that escape into their own session
/// via `setsid()`.
func descendantProcessGroupIDs(of root: pid_t) -> Set<pid_t> {
    var pgids: Set<pid_t> = []
    var toVisit: [pid_t] = [root]
    var visited: Set<pid_t> = []

    while let pid = toVisit.popLast() {
        if visited.contains(pid) { continue }
        visited.insert(pid)

        let pgid = getpgid(pid)
        if pgid > 0 { pgids.insert(pgid) }

        let bytesNeeded = proc_listchildpids(pid, nil, 0)
        if bytesNeeded <= 0 { continue }
        let count = Int(bytesNeeded) / MemoryLayout<pid_t>.size
        var buffer = [pid_t](repeating: 0, count: count)
        let actualBytes = buffer.withUnsafeMutableBufferPointer { ptr in
            proc_listchildpids(pid, ptr.baseAddress, Int32(bytesNeeded))
        }
        if actualBytes <= 0 { continue }
        let actualCount = Int(actualBytes) / MemoryLayout<pid_t>.size
        for child in buffer.prefix(actualCount) where child > 0 {
            toVisit.append(child)
        }
    }

    return pgids
}

/// Tracks live child pgids spawned by `ShellCommand` so the server shutdown
/// handler can reap them on signal or transport close. NSLock-guarded so it
/// is safe to read from a signal handler.
public enum ChildProcessRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pgids: [pid_t] = []

    public static func register(_ pgid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        if !pgids.contains(pgid) {
            pgids.append(pgid)
        }
    }

    public static func unregister(_ pgid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        pgids.removeAll { $0 == pgid }
    }

    public static func snapshot() -> [pid_t] {
        lock.lock()
        defer { lock.unlock() }
        return pgids
    }
}

/// SIGTERM every registered child and any escaped descendants, wait briefly,
/// then SIGKILL anything still alive. Synchronous; safe in shutdown paths
/// where Swift Concurrency may be unavailable.
public func terminateAllChildProcessGroups(graceSeconds: UInt32 = 1) {
    let roots = ChildProcessRegistry.snapshot()
    guard !roots.isEmpty else { return }

    var allGroups: Set<pid_t> = []
    for root in roots {
        allGroups.formUnion(descendantProcessGroupIDs(of: root))
    }

    for pgid in allGroups {
        _ = kill(-pgid, SIGTERM)
    }

    if graceSeconds > 0 {
        sleep(graceSeconds)
    }

    // Re-walk: descendants may have changed since SIGTERM.
    var remaining: Set<pid_t> = []
    for root in ChildProcessRegistry.snapshot() {
        remaining.formUnion(descendantProcessGroupIDs(of: root))
    }
    for pgid in remaining {
        _ = kill(-pgid, SIGKILL)
    }
}
