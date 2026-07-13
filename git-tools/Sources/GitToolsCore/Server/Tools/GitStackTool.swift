import Foundation
import MCP

enum GitStackTool {
    static let name = "git-stack"

    private static let gitPath = "/usr/bin/git"

    static var definition: Tool {
        Tool(
            name: name,
            description: "Stacked-branches workflow. Manages a tree of dependent branches whose parent/child topology is tracked in git config (branch.<name>.stackParent, stack.base). Read operations (stack_info, ancestors, children, log), topology edits (set_base, new, adopt, delete), current-stack mutations (track, split, remove), inter-stack moves (move, restack, reset), and remote sync (save, sync).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("stack_info"),
                            .string("ancestors"),
                            .string("children"),
                            .string("log"),
                            .string("set_base"),
                            .string("new"),
                            .string("adopt"),
                            .string("delete"),
                            .string("track"),
                            .string("split"),
                            .string("remove"),
                            .string("move"),
                            .string("restack"),
                            .string("reset"),
                            .string("save"),
                            .string("sync"),
                        ]),
                        "description": .string("The stack action to perform. One of: stack_info, ancestors, children, log, set_base, new, adopt, delete, track, split, remove, move, restack, reset, save, sync"),
                    ]),
                    "repoPath": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the git repository"),
                    ]),
                    "branch": .object([
                        "type": .string("string"),
                        "description": .string("Branch to operate on (for ancestors, children, log, set_base, delete, remove, restack, reset, save; defaults to current branch)"),
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("New branch name (required for new, adopt, split)"),
                    ]),
                    "count": .object([
                        "type": .string("integer"),
                        "description": .string("Number of commits to operate on (for split, remove, move; default 1)"),
                    ]),
                    "message": .object([
                        "type": .string("string"),
                        "description": .string("Commit message (required for track)"),
                    ]),
                    "onto": .object([
                        "type": .string("string"),
                        "description": .string("Target parent branch (required for adopt and move)"),
                    ]),
                    "remote": .object([
                        "type": .string("string"),
                        "description": .string("Remote name (for reset, save, sync; default 'origin')"),
                    ]),
                    "all": .object([
                        "type": .string("boolean"),
                        "description": .string("Stage all tracked changes before committing (for track, uses -a)"),
                    ]),
                    "push": .object([
                        "type": .string("boolean"),
                        "description": .string("After committing, push with --force-with-lease (for track)"),
                    ]),
                    "force": .object([
                        "type": .string("boolean"),
                        "description": .string("Allow destructive operations: force-delete branch (delete), gate hard reset (remove), use --force instead of --force-with-lease (save)"),
                    ]),
                ]),
                "required": .array([.string("action"), .string("repoPath")]),
            ]),
            annotations: .init(readOnlyHint: false, openWorldHint: false)
        )
    }

    static func handle(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let args = arguments,
              let action = args["action"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: action")
        }
        guard let repoPath = args["repoPath"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: repoPath")
        }

        switch action {
        case "stack_info":
            return try await handleStackInfo(args: args, repoPath: repoPath)
        case "ancestors":
            return try await handleAncestors(args: args, repoPath: repoPath)
        case "children":
            return try await handleChildren(args: args, repoPath: repoPath)
        case "log":
            return try await handleLog(args: args, repoPath: repoPath)
        case "set_base":
            return try await handleSetBase(args: args, repoPath: repoPath)
        case "new":
            return try await handleNew(args: args, repoPath: repoPath)
        case "adopt":
            return try await handleAdopt(args: args, repoPath: repoPath)
        case "delete":
            return try await handleDelete(args: args, repoPath: repoPath)
        case "track":
            return try await handleTrack(args: args, repoPath: repoPath)
        case "split":
            return try await handleSplit(args: args, repoPath: repoPath)
        case "remove":
            return try await handleRemove(args: args, repoPath: repoPath)
        case "move":
            return try await handleMove(args: args, repoPath: repoPath)
        case "restack":
            return try await handleRestack(args: args, repoPath: repoPath)
        case "reset":
            return try await handleReset(args: args, repoPath: repoPath)
        case "save":
            return try await handleSave(args: args, repoPath: repoPath)
        case "sync":
            return try await handleSync(args: args, repoPath: repoPath)
        default:
            throw MCPError.invalidParams(
                "Unknown action: \(action). Valid actions: stack_info, ancestors, children, log, set_base, new, adopt, delete, track, split, remove, move, restack, reset, save, sync"
            )
        }
    }

    // MARK: - Read-only

    private static func handleStackInfo(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let cur = try await currentBranch(repoPath: repoPath)
        let base = try await stackBase(repoPath: repoPath)
        let chain = try await ancestors(of: cur, repoPath: repoPath)
        let kids = try await children(of: cur, repoPath: repoPath)
        let p = try await parent(of: cur, repoPath: repoPath)
        let recorded = try await recordedParent(of: cur, repoPath: repoPath)

        var lines: [String] = []
        lines.append("Current branch: \(cur)")
        lines.append("Base: \(base)")
        if cur == base {
            lines.append("This is the base branch.")
        } else if let p, recorded == nil {
            lines.append("Parent: \(p) (inferred from git; use 'adopt' to pin it).")
        } else if p == nil {
            lines.append("Parent: none found below \(cur).")
        }
        if chain.isEmpty {
            lines.append("Ancestors: (none)")
        } else {
            lines.append("Ancestors (nearest first): \(chain.joined(separator: " -> "))")
        }
        if kids.isEmpty {
            lines.append("Children: (none)")
        } else {
            lines.append("Children: \(kids.joined(separator: ", "))")
        }
        return textResult(lines.joined(separator: "\n"))
    }

    private static func handleAncestors(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let branch = try await branchArg(args, repoPath: repoPath)
        let chain = try await ancestors(of: branch, repoPath: repoPath)
        if chain.isEmpty {
            return textResult("\(branch) has no recorded ancestors.")
        }
        return textResult("Ancestors of \(branch) (nearest first): \(chain.joined(separator: " -> "))")
    }

    private static func handleChildren(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let branch = try await branchArg(args, repoPath: repoPath)
        let kids = try await children(of: branch, repoPath: repoPath)
        if kids.isEmpty {
            return textResult("\(branch) has no children.")
        }
        return textResult("Children of \(branch): \(kids.joined(separator: ", "))")
    }

    private static func handleLog(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let branch = try await branchArg(args, repoPath: repoPath)
        let p = try await parent(of: branch, repoPath: repoPath)
        let base = try await stackBase(repoPath: repoPath)
        let upstream = p ?? base
        let result = try await git(["-C", repoPath, "log", "--oneline", "\(upstream)..\(branch)"])
        if result.exitCode != 0 {
            return errorResult("git log failed:\n\(result.output)")
        }
        let out = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty {
            return textResult("No commits unique to \(branch) over \(upstream).")
        }
        return textResult("Commits on \(branch) over \(upstream):\n\(out)")
    }

    // MARK: - Topology

    private static func handleSetBase(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let branch = args["branch"]?.stringValue ?? "main"
        let result = try await git(["-C", repoPath, "config", "stack.base", branch])
        if result.exitCode != 0 {
            return errorResult("failed to set stack.base:\n\(result.output)")
        }
        return textResult("Set stack base to \(branch).")
    }

    private static func handleNew(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let name = args["name"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: name (for new)")
        }
        let parentBranch = try await currentBranch(repoPath: repoPath)
        let checkout = try await git(["-C", repoPath, "checkout", "-b", name])
        if checkout.exitCode != 0 {
            return errorResult("git checkout -b failed:\n\(checkout.output)")
        }
        try await setParent(of: name, to: parentBranch, repoPath: repoPath)
        return textResult("Created \(name) with parent \(parentBranch).")
    }

    private static func handleAdopt(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let name = args["name"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: name (for adopt)")
        }
        guard let onto = args["onto"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: onto (for adopt)")
        }
        try await setParent(of: name, to: onto, repoPath: repoPath)
        return textResult("Set parent of \(name) to \(onto).")
    }

    private static func handleDelete(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let branch = try await branchArg(args, repoPath: repoPath)
        let force = args["force"]?.boolValue ?? false
        let branchParent = try await parent(of: branch, repoPath: repoPath)
        let kids = try await children(of: branch, repoPath: repoPath)

        // Reparent each child onto the deleted branch's parent, then restack it.
        var restacked: [String] = []
        for child in kids {
            if let branchParent {
                try await setParent(of: child, to: branchParent, repoPath: repoPath)
            } else {
                try await unsetParent(of: child, repoPath: repoPath)
            }
            if branchParent != nil {
                var visited = Set<String>()
                restacked += try await restack(branch: child, repoPath: repoPath, visited: &visited)
            }
        }

        let flag = force ? "-D" : "-d"
        let del = try await git(["-C", repoPath, "branch", flag, branch])
        if del.exitCode != 0 {
            return errorResult("git branch \(flag) failed:\n\(del.output)")
        }
        try await unsetParent(of: branch, repoPath: repoPath)

        var msg = "Deleted \(branch)."
        if !kids.isEmpty {
            let target = branchParent ?? "(none)"
            msg += " Reparented children [\(kids.joined(separator: ", "))] onto \(target)."
        }
        if !restacked.isEmpty {
            msg += " Restacked: \(restacked.joined(separator: ", "))."
        }
        return textResult(msg)
    }

    // MARK: - Current-stack mutations

    private static func handleTrack(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let message = args["message"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: message (for track)")
        }
        let all = args["all"]?.boolValue ?? false
        let push = args["push"]?.boolValue ?? false
        let cur = try await currentBranch(repoPath: repoPath)

        var commitArgs = ["-C", repoPath, "commit", "-m", message]
        if all { commitArgs.append("-a") }
        let commit = try await git(commitArgs)
        if commit.exitCode != 0 {
            return errorResult("git commit failed:\n\(commit.output)")
        }

        var restacked: [String] = []
        for child in try await children(of: cur, repoPath: repoPath) {
            var visited = Set<String>()
            do {
                restacked += try await restack(branch: child, repoPath: repoPath, visited: &visited)
            } catch {
                return errorResult("committed on \(cur), but restack failed:\n\(error)")
            }
        }

        var msg = "Committed on \(cur)."
        if !restacked.isEmpty {
            msg += " Restacked: \(restacked.joined(separator: ", "))."
        }
        if push {
            let pushResult = try await git(["-C", repoPath, "push", "--force-with-lease"])
            msg += "\nPush: \(pushResult.output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return textResult(msg)
    }

    private static func handleSplit(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let name = args["name"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: name (for split)")
        }
        let count = intArg(args, "count", default: 1)
        let cur = try await currentBranch(repoPath: repoPath)

        // Peel the top `count` commits of `cur` into a new branch `name` that
        // sits between `cur` and its children. After the operation:
        //   - `name` points at the current HEAD (holds all commits incl. top N)
        //   - `cur` is reset back N commits (keeps older history, loses top N)
        //   - `name`'s parent is `cur`; `cur`'s old children reparent to `name`
        //
        // Ordering matters: create `name` at HEAD first (so it captures the top
        // N commits), THEN rewind `cur`. The peeled commits then live on `name`,
        // stacked on top of the rewound `cur`.
        let kids = try await children(of: cur, repoPath: repoPath)

        let branch = try await git(["-C", repoPath, "branch", name])
        if branch.exitCode != 0 {
            return errorResult("git branch \(name) failed:\n\(branch.output)")
        }

        // Rewind cur back `count` commits, keeping the working tree intact.
        let reset = try await git(["-C", repoPath, "reset", "--keep", "HEAD~\(count)"])
        if reset.exitCode != 0 {
            // Roll back the branch we just created so state stays consistent.
            _ = try await git(["-C", repoPath, "branch", "-D", name])
            return errorResult("git reset --keep HEAD~\(count) failed:\n\(reset.output)")
        }

        try await setParent(of: name, to: cur, repoPath: repoPath)

        // Old children of cur now stack on top of `name` (the new tip).
        var restacked: [String] = []
        for child in kids {
            try await setParent(of: child, to: name, repoPath: repoPath)
            var visited = Set<String>()
            restacked += try await restack(branch: child, repoPath: repoPath, visited: &visited)
        }

        var msg = "Split top \(count) commit(s) of \(cur) into \(name) (parent: \(cur))."
        if !kids.isEmpty {
            msg += " Reparented [\(kids.joined(separator: ", "))] onto \(name)."
        }
        if !restacked.isEmpty {
            msg += " Restacked: \(restacked.joined(separator: ", "))."
        }
        return textResult(msg)
    }

    private static func handleRemove(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let branch = try await branchArg(args, repoPath: repoPath)
        let count = intArg(args, "count", default: 1)
        let force = args["force"]?.boolValue ?? false
        guard force else {
            return errorResult("remove performs a hard reset (destroys the top \(count) commit(s) of \(branch)). Re-run with force=true to proceed.")
        }

        let cur = try await currentBranch(repoPath: repoPath)
        // Reset the target branch. If it's the current branch, reset in place;
        // otherwise update the branch ref directly without checking it out.
        let reset: ShellCommand.Result
        if branch == cur {
            reset = try await git(["-C", repoPath, "reset", "--hard", "HEAD~\(count)"])
        } else {
            reset = try await git(["-C", repoPath, "branch", "-f", branch, "\(branch)~\(count)"])
        }
        if reset.exitCode != 0 {
            return errorResult("failed to drop commits from \(branch):\n\(reset.output)")
        }

        var restacked: [String] = []
        for child in try await children(of: branch, repoPath: repoPath) {
            var visited = Set<String>()
            do {
                restacked += try await restack(branch: child, repoPath: repoPath, visited: &visited)
            } catch {
                return errorResult("dropped commits from \(branch), but restack failed:\n\(error)")
            }
        }

        var msg = "Removed top \(count) commit(s) from \(branch)."
        if !restacked.isEmpty {
            msg += " Restacked: \(restacked.joined(separator: ", "))."
        }
        return textResult(msg)
    }

    // MARK: - Inter-stack

    private static func handleMove(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let onto = args["onto"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: onto (for move)")
        }
        let count = intArg(args, "count", default: 1)
        let cur = try await currentBranch(repoPath: repoPath)

        return try await withStashedWorktree(repoPath: repoPath) {
            // Capture the top `count` commit SHAs oldest-first so cherry-pick
            // replays them in the original order.
            let shaResult = try await git([
                "-C", repoPath, "log", "--reverse", "--format=%H", "-n", "\(count)", cur,
            ])
            if shaResult.exitCode != 0 {
                throw StackError("git log failed:\n\(shaResult.output)")
            }
            let shas = shaResult.output
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !shas.isEmpty else {
                throw StackError("no commits to move on \(cur)")
            }

            let checkoutOnto = try await git(["-C", repoPath, "checkout", onto])
            if checkoutOnto.exitCode != 0 {
                throw StackError("git checkout \(onto) failed:\n\(checkoutOnto.output)")
            }

            for sha in shas {
                let pick = try await git(["-C", repoPath, "cherry-pick", sha])
                if pick.exitCode != 0 {
                    _ = try await git(["-C", repoPath, "cherry-pick", "--abort"])
                    _ = try await git(["-C", repoPath, "checkout", cur])
                    throw StackError("cherry-pick of \(sha) onto \(onto) failed:\n\(pick.output)")
                }
            }

            let backToCur = try await git(["-C", repoPath, "checkout", cur])
            if backToCur.exitCode != 0 {
                throw StackError("git checkout \(cur) failed:\n\(backToCur.output)")
            }
            let drop = try await git(["-C", repoPath, "reset", "--hard", "HEAD~\(count)"])
            if drop.exitCode != 0 {
                throw StackError("git reset --hard HEAD~\(count) failed:\n\(drop.output)")
            }

            // Restack children of both the source and the destination.
            var restacked: [String] = []
            var visited = Set<String>()
            for child in try await children(of: cur, repoPath: repoPath) {
                restacked += try await restack(branch: child, repoPath: repoPath, visited: &visited)
            }
            for child in try await children(of: onto, repoPath: repoPath) {
                restacked += try await restack(branch: child, repoPath: repoPath, visited: &visited)
            }

            var msg = "Moved top \(count) commit(s) from \(cur) onto \(onto)."
            if !restacked.isEmpty {
                msg += " Restacked: \(restacked.joined(separator: ", "))."
            }
            return textResult(msg)
        }
    }

    private static func handleRestack(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let branch = try await branchArg(args, repoPath: repoPath)
        var visited = Set<String>()
        do {
            let restacked = try await restack(branch: branch, repoPath: repoPath, visited: &visited)
            if restacked.isEmpty {
                return textResult("Nothing to restack for \(branch).")
            }
            return textResult("Restacked: \(restacked.joined(separator: ", ")).")
        } catch {
            return errorResult("restack failed:\n\(error)")
        }
    }

    private static func handleReset(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let branch = try await branchArg(args, repoPath: repoPath)
        let remote = args["remote"]?.stringValue ?? "origin"
        let result = try await git(["-C", repoPath, "reset", "--hard", "\(remote)/\(branch)"])
        if result.exitCode != 0 {
            return errorResult("git reset --hard \(remote)/\(branch) failed:\n\(result.output)")
        }
        return textResult("Reset \(branch) to \(remote)/\(branch).\n\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    // MARK: - Manage / sync

    private static func handleSave(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let branch = try await branchArg(args, repoPath: repoPath)
        let remote = args["remote"]?.stringValue ?? "origin"
        let force = args["force"]?.boolValue ?? false
        let forceFlag = force ? "--force" : "--force-with-lease"
        let result = try await git(["-C", repoPath, "push", forceFlag, remote, branch])
        if result.exitCode != 0 {
            return errorResult("git push failed:\n\(result.output)")
        }
        return textResult("Pushed \(branch) to \(remote).\n\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    private static func handleSync(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let remote = args["remote"]?.stringValue ?? "origin"
        let cur = try await currentBranch(repoPath: repoPath)
        let base = try await stackBase(repoPath: repoPath)

        let fetch = try await git(["-C", repoPath, "fetch", remote])
        if fetch.exitCode != 0 {
            return errorResult("git fetch \(remote) failed:\n\(fetch.output)")
        }

        // Restack the whole stack containing `cur`: find the highest ancestor of
        // `cur` whose parent is the base (the top of the stack), then restack
        // from there so the rebase cascades down to every descendant.
        let chain = try await ancestors(of: cur, repoPath: repoPath)
        // chain is nearest-parent-first ... base last. The stack root is the
        // last chain entry that is not the base itself; if cur is directly on
        // base (or is the base), the root is cur.
        var root = cur
        for ancestor in chain where ancestor != base {
            root = ancestor
        }

        var visited = Set<String>()
        do {
            let restacked = try await restack(branch: root, repoPath: repoPath, visited: &visited)
            var msg = "Fetched \(remote)."
            if restacked.isEmpty {
                msg += " Nothing to restack."
            } else {
                msg += " Restacked from \(root): \(restacked.joined(separator: ", "))."
            }
            return textResult(msg)
        } catch {
            return errorResult("fetched \(remote), but restack failed:\n\(error)")
        }
    }

    // MARK: - Stack topology helpers

    private static func currentBranch(repoPath: String) async throws -> String {
        let result = try await git(["-C", repoPath, "rev-parse", "--abbrev-ref", "HEAD"])
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stackBase(repoPath: String) async throws -> String {
        let result = try await git(["-C", repoPath, "config", "--get", "stack.base"])
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "main" : value
    }

    /// The recorded parent of `branch` if config has one; otherwise the parent
    /// inferred from git topology (nearest ancestor branch). Returns nil only
    /// when `branch` is the base or nothing in git sits below it.
    ///
    /// Config is an explicit override, not the source of truth: a branch created
    /// outside the tool (no `stackParent`) is still placed in the stack by
    /// inference, so reads and restacks work with zero recorded state.
    private static func parent(of branch: String, repoPath: String) async throws -> String? {
        if let recorded = try await recordedParent(of: branch, repoPath: repoPath) {
            return recorded
        }
        let base = try await stackBase(repoPath: repoPath)
        if branch == base { return nil }
        let branches = try await localBranches(repoPath: repoPath)
        var cache = AncestryCache()
        return try await inferParent(
            of: branch, base: base, branches: branches, repoPath: repoPath, cache: &cache
        )
    }

    /// The parent explicitly recorded in config, or nil if unset.
    private static func recordedParent(of branch: String, repoPath: String) async throws -> String? {
        let result = try await git(["-C", repoPath, "config", "--get", "branch.\(branch).stackParent"])
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func setParent(of branch: String, to newParent: String, repoPath: String) async throws {
        let result = try await git(["-C", repoPath, "config", "branch.\(branch).stackParent", newParent])
        if result.exitCode != 0 {
            throw StackError("failed to set parent of \(branch):\n\(result.output)")
        }
    }

    private static func unsetParent(of branch: String, repoPath: String) async throws {
        // Ignore non-zero exit: the key is simply absent.
        _ = try await git(["-C", repoPath, "config", "--unset", "branch.\(branch).stackParent"])
    }

    /// Children of `branch`: the union of branches that explicitly record it as
    /// their `stackParent` (config overrides) and branches whose inferred parent
    /// is `branch`. Works even when no config exists.
    private static func children(of branch: String, repoPath: String) async throws -> [String] {
        var kids = Set(try await recordedChildren(of: branch, repoPath: repoPath))

        let base = try await stackBase(repoPath: repoPath)
        let branches = try await localBranches(repoPath: repoPath)
        var cache = AncestryCache()
        for candidate in branches where candidate != branch {
            // A candidate with an explicit parent is already covered by the
            // recorded scan above; only infer for the rest.
            if try await recordedParent(of: candidate, repoPath: repoPath) != nil { continue }
            let inferred = try await inferParent(
                of: candidate, base: base, branches: branches, repoPath: repoPath, cache: &cache
            )
            if inferred == branch { kids.insert(candidate) }
        }
        return kids.sorted()
    }

    /// Branches that explicitly record `branch` as their `stackParent` in config.
    private static func recordedChildren(of branch: String, repoPath: String) async throws -> [String] {
        let result = try await git([
            "-C", repoPath, "config", "--get-regexp", "^branch\\..*\\.stackParent$",
        ])
        // Non-zero exit when there are no matches; treat as empty.
        guard result.exitCode == 0 else { return [] }

        // git canonicalizes the trailing variable name to lowercase, so the
        // key comes back as "branch.<child>.stackparent" regardless of how it
        // was written. Match prefix/suffix case-insensitively; the branch
        // subsection between them preserves its original case.
        let prefix = "branch."
        let suffix = ".stackparent"
        var kids: [String] = []
        for line in result.output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Each line: "branch.<child>.stackParent <parent>". Split into key
            // and value on the FIRST space only, since branch names may not but
            // the value could contain unexpected characters.
            guard let spaceIdx = trimmed.firstIndex(of: " ") else { continue }
            let key = String(trimmed[trimmed.startIndex..<spaceIdx])
            let value = String(trimmed[trimmed.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
            guard value == branch else { continue }
            // Branch names can contain dots; strip the known prefix/suffix
            // rather than splitting on '.'.
            let lowerKey = key.lowercased()
            guard lowerKey.hasPrefix(prefix), lowerKey.hasSuffix(suffix) else { continue }
            let child = String(key.dropFirst(prefix.count).dropLast(suffix.count))
            if !child.isEmpty { kids.append(child) }
        }
        return kids
    }

    // MARK: - Git-derived topology inference

    /// Memoizes `isAncestor` results within a single topology computation so the
    /// pairwise `merge-base` calls stay bounded.
    private struct AncestryCache {
        var isAncestor: [String: Bool] = [:]
    }

    /// All local branch short-names.
    private static func localBranches(repoPath: String) async throws -> [String] {
        let result = try await git([
            "-C", repoPath, "for-each-ref", "--format=%(refname:short)", "refs/heads",
        ])
        guard result.exitCode == 0 else { return [] }
        return result.output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// True if `ancestor`'s tip is reachable from `branch`.
    private static func isAncestor(
        _ ancestor: String, of branch: String, repoPath: String, cache: inout AncestryCache
    ) async throws -> Bool {
        let key = "\(ancestor)\u{00}\(branch)"
        if let cached = cache.isAncestor[key] { return cached }
        let result = try await git([
            "-C", repoPath, "merge-base", "--is-ancestor", ancestor, branch,
        ])
        let value = result.exitCode == 0
        cache.isAncestor[key] = value
        return value
    }

    /// Number of commits in `from..to` (how far `to` is ahead of `from`).
    private static func commitDistance(
        from: String, to: String, repoPath: String
    ) async throws -> Int {
        let result = try await git(["-C", repoPath, "rev-list", "--count", "\(from)..\(to)"])
        return Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? Int.max
    }

    /// Infer `branch`'s parent from git topology: the nearest local branch whose
    /// tip is an ancestor of `branch` (smallest `<candidate>..branch` distance).
    ///
    /// This resolves the case topology CAN orient — a parent that is still at or
    /// behind the child. Once a parent advances past its child, both carry unique
    /// commits and git cannot distinguish parent from sibling; inference then
    /// returns nil and the deliberately recorded `stackParent` (written by `new`,
    /// `adopt`, `move`, `split`) is authoritative. `parent(of:)` checks the
    /// record first, so inference only fills the gap for branches created outside
    /// the tool.
    ///
    /// Returns nil when `branch` is the base or nothing below it qualifies.
    private static func inferParent(
        of branch: String,
        base: String,
        branches: [String],
        repoPath: String,
        cache: inout AncestryCache
    ) async throws -> String? {
        if branch == base { return nil }

        // Candidates: branches whose tip is an ancestor of `branch`.
        var distances: [String: Int] = [:]
        for candidate in branches where candidate != branch {
            guard try await isAncestor(candidate, of: branch, repoPath: repoPath, cache: &cache) else {
                continue
            }
            distances[candidate] = try await commitDistance(from: candidate, to: branch, repoPath: repoPath)
        }
        guard !distances.isEmpty else { return nil }

        let minDistance = distances.values.min() ?? Int.max
        var nearest = distances.filter { $0.value == minDistance }.map(\.key)

        if nearest.count > 1 {
            // Tie (candidates on the same commit): keep the most specific by
            // dropping any that is an ancestor of another tied one, then by name.
            var mostSpecific: [String] = []
            for a in nearest {
                var dominated = false
                for b in nearest where b != a {
                    if try await isAncestor(a, of: b, repoPath: repoPath, cache: &cache) {
                        dominated = true
                        break
                    }
                }
                if !dominated { mostSpecific.append(a) }
            }
            if !mostSpecific.isEmpty { nearest = mostSpecific }
        }
        return nearest.sorted().first
    }

    private static func ancestors(of branch: String, repoPath: String) async throws -> [String] {
        let base = try await stackBase(repoPath: repoPath)
        var chain: [String] = []
        var visited: Set<String> = [branch]
        var cursor = branch
        while let p = try await parent(of: cursor, repoPath: repoPath) {
            if visited.contains(p) { break } // cycle guard
            chain.append(p)
            visited.insert(p)
            if p == base { break }
            cursor = p
        }
        return chain
    }

    /// Rebase `branch` onto its recorded parent, then recursively restack its
    /// children. Returns the list of branches that were rebased. Throws on
    /// rebase conflict (after aborting) so the caller can surface an error.
    private static func restack(branch: String, repoPath: String, visited: inout Set<String>) async throws -> [String] {
        // Snapshot the whole subtree (parent + fork point per descendant) BEFORE
        // any rebase. Rebasing a mid-stack branch moves its tip, which would
        // otherwise (a) orphan not-yet-moved descendants from git-inference and
        // (b) shift the fork point used to select a child's own commits. Freezing
        // the plan up front keeps the cascade correct for topology derived purely
        // from git, with no recorded config.
        let plan = try await restackPlan(root: branch, repoPath: repoPath, visited: &visited)

        var restacked: [String] = []
        for step in plan {
            // Skip when the branch already sits on the parent's current tip: the
            // parent hasn't moved, so rebasing would needlessly rewrite commits
            // (new SHAs) and break anything referencing the old tip.
            let upToDate = try await git([
                "-C", repoPath, "merge-base", "--is-ancestor", step.parent, step.branch,
            ])
            if upToDate.exitCode == 0 { continue }

            // Replay only the branch's own commits (frozen fork point ..branch)
            // onto the parent's current tip via --onto.
            let onto = step.forkPoint.isEmpty
                ? ["-C", repoPath, "rebase", step.parent, step.branch]
                : ["-C", repoPath, "rebase", "--onto", step.parent, step.forkPoint, step.branch]
            let rebase = try await git(onto)
            if rebase.exitCode != 0 {
                _ = try await git(["-C", repoPath, "rebase", "--abort"])
                throw StackError("rebase of \(step.branch) onto \(step.parent) failed:\n\(rebase.output)")
            }
            restacked.append(step.branch)
        }
        return restacked
    }

    /// One branch to rebase and the inputs frozen at planning time.
    private struct RestackStep {
        let branch: String
        let parent: String
        /// Fork point (merge-base of parent and branch) captured before any
        /// rebase, so `--onto` replays exactly this branch's own commits.
        let forkPoint: String
    }

    /// BFS the descendant tree from `root`, recording each branch's parent and
    /// current fork point. Parents precede their children so rebasing in order
    /// lands each child on an already-updated parent. `visited` guards cycles.
    private static func restackPlan(
        root: String, repoPath: String, visited: inout Set<String>
    ) async throws -> [RestackStep] {
        var plan: [RestackStep] = []
        var queue = [root]
        while !queue.isEmpty {
            let branch = queue.removeFirst()
            if visited.contains(branch) { continue }
            visited.insert(branch)

            if let p = try await parent(of: branch, repoPath: repoPath) {
                let mb = try await git(["-C", repoPath, "merge-base", p, branch])
                let forkPoint = mb.output.trimmingCharacters(in: .whitespacesAndNewlines)
                plan.append(RestackStep(branch: branch, parent: p, forkPoint: forkPoint))
            }
            for child in try await children(of: branch, repoPath: repoPath) where !visited.contains(child) {
                queue.append(child)
            }
        }
        return plan
    }

    /// Stash the worktree (including untracked files), run `body`, then pop the
    /// stash only if something was actually stashed. Pops on both success and
    /// failure paths since Swift `defer` cannot be async.
    private static func withStashedWorktree<T>(
        repoPath: String,
        _ body: () async throws -> T
    ) async throws -> T {
        let stash = try await git(["-C", repoPath, "stash", "push", "--include-untracked"])
        // `stash push` exits 0 and prints "No local changes to save" when the
        // worktree is clean; detect that so we don't pop an unrelated stash.
        let didStash = stash.exitCode == 0
            && !stash.output.contains("No local changes to save")

        do {
            let result = try await body()
            if didStash {
                _ = try await git(["-C", repoPath, "stash", "pop"])
            }
            return result
        } catch {
            if didStash {
                _ = try await git(["-C", repoPath, "stash", "pop"])
            }
            throw error
        }
    }

    // MARK: - Argument helpers

    /// Resolve the `branch` argument, defaulting to the current branch.
    private static func branchArg(_ args: [String: Value], repoPath: String) async throws -> String {
        if let branch = args["branch"]?.stringValue, !branch.isEmpty {
            return branch
        }
        return try await currentBranch(repoPath: repoPath)
    }

    private static func intArg(_ args: [String: Value], _ key: String, default def: Int) -> Int {
        args[key]?.intValue ?? args[key]?.doubleValue.map { Int($0) } ?? def
    }

    // MARK: - Shell helpers

    private static func git(_ arguments: [String]) async throws -> ShellCommand.Result {
        try await ShellCommand.run(gitPath, arguments: arguments)
    }

    private static func textResult(_ text: String) -> CallTool.Result {
        .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    private static func errorResult(_ text: String) -> CallTool.Result {
        .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
    }
}

/// Descriptive error string wrapper so thrown restack/move failures render
/// cleanly when interpolated into an errorResult.
private struct StackError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
