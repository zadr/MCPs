import Foundation
import MCP

enum GitTool {
    static let name = "git-core"

    private static let gitPath = "/usr/bin/git"

    static var definition: Tool {
        Tool(
            name: name,
            description: "Git version control. Comprehensive git frontend supporting init, read operations (status, log, diff, blame, branch_info, merge_analysis, show, tag, remote) and write operations (add, mv, commit, push, pull, checkout, reset, stash, merge, rebase, cherry_pick). Branch management (branch_create, branch_delete, branch_rename) and worktree support (worktree_list, worktree_find_by_branch_name, worktree_add, worktree_remove).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("init"),
                            .string("status"),
                            .string("log"),
                            .string("diff"),
                            .string("blame"),
                            .string("branch_info"),
                            .string("merge_analysis"),
                            .string("show"),
                            .string("tag"),
                            .string("remote"),
                            .string("add"),
                            .string("mv"),
                            .string("commit"),
                            .string("push"),
                            .string("pull"),
                            .string("checkout"),
                            .string("reset"),
                            .string("stash"),
                            .string("merge"),
                            .string("rebase"),
                            .string("cherry_pick"),
                            .string("branch_create"),
                            .string("branch_delete"),
                            .string("branch_rename"),
                            .string("worktree_list"),
                            .string("worktree_find_by_branch_name"),
                            .string("worktree_add"),
                            .string("worktree_remove"),
                            .string("worktree_prune"),
                            .string("branch_prune"),
                            .string("branch_find_duplicates"),
                        ]),
                        "description": .string("The git action to perform. One of: init, status, log, diff, blame, branch_info, merge_analysis, show, tag, remote, add, mv, commit, push, pull, checkout, reset, stash, merge, rebase, cherry_pick, branch_create, branch_delete, branch_rename, worktree_list, worktree_find_by_branch_name, worktree_add, worktree_remove, worktree_prune, branch_prune, branch_find_duplicates"),
                    ]),
                    "repoPath": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the git repository"),
                    ]),
                    "maxCount": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of commits to show (for log, default 20)"),
                    ]),
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Filter to a specific file path relative to the repo (for log, diff)"),
                    ]),
                    "since": .object([
                        "type": .string("string"),
                        "description": .string("Show commits after this date, e.g. '2025-01-01' (for log)"),
                    ]),
                    "author": .object([
                        "type": .string("string"),
                        "description": .string("Filter commits by author (for log)"),
                    ]),
                    "staged": .object([
                        "type": .string("boolean"),
                        "description": .string("Diff staged changes instead of unstaged (for diff)"),
                    ]),
                    "commitRange": .object([
                        "type": .string("string"),
                        "description": .string("Commit range like 'main..HEAD' (for diff)"),
                    ]),
                    "filePath": .object([
                        "type": .string("string"),
                        "description": .string("File path relative to the repo (for blame)"),
                    ]),
                    "startLine": .object([
                        "type": .string("integer"),
                        "description": .string("Start line number (for blame)"),
                    ]),
                    "endLine": .object([
                        "type": .string("integer"),
                        "description": .string("End line number (for blame)"),
                    ]),
                    "source": .object([
                        "type": .string("string"),
                        "description": .string("Source branch to merge (for merge_analysis); source path to move (for mv)"),
                    ]),
                    "destination": .object([
                        "type": .string("string"),
                        "description": .string("Destination path to move to (for mv)"),
                    ]),
                    "target": .object([
                        "type": .string("string"),
                        "description": .string("Target branch/commit for merge_analysis (default HEAD), checkout target (branch name, commit hash, or file path)"),
                    ]),
                    // show params
                    "ref": .object([
                        "type": .string("string"),
                        "description": .string("Commit reference (for show, default HEAD; for tag, what to tag, default HEAD)"),
                    ]),
                    "stat": .object([
                        "type": .string("boolean"),
                        "description": .string("Show diffstat only (for show)"),
                    ]),
                    // tag params
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Tag name to create (for tag), branch name (for branch_create, branch_delete)"),
                    ]),
                    "list": .object([
                        "type": .string("boolean"),
                        "description": .string("List tags (for tag, default true if no name provided)"),
                    ]),
                    // add params
                    "files": .object([
                        "type": .string("string"),
                        "description": .string("Space-separated file paths, or '.' for all (for add, reset)"),
                    ]),
                    // commit params
                    "message": .object([
                        "type": .string("string"),
                        "description": .string("Commit message (for commit), stash message (for stash push), annotated tag message (for tag)"),
                    ]),
                    "amend": .object([
                        "type": .string("boolean"),
                        "description": .string("Amend the last commit (for commit)"),
                    ]),
                    // push params
                    "remote": .object([
                        "type": .string("string"),
                        "description": .string("Remote name (for push, pull; default 'origin')"),
                    ]),
                    "branch": .object([
                        "type": .string("string"),
                        "description": .string("Branch name (for push, pull, merge, worktree_add, worktree_find_by_branch_name)"),
                    ]),
                    "force": .object([
                        "type": .string("boolean"),
                        "description": .string("Force push (for push), force delete with -D (for branch_delete), force remove (for worktree_remove), overwrite destination with -f (for mv)"),
                    ]),
                    "setUpstream": .object([
                        "type": .string("boolean"),
                        "description": .string("Set upstream tracking reference (for push, uses -u flag)"),
                    ]),
                    // pull params
                    "rebase": .object([
                        "type": .string("boolean"),
                        "description": .string("Pull with rebase instead of merge (for pull)"),
                    ]),
                    // checkout params
                    "createBranch": .object([
                        "type": .string("boolean"),
                        "description": .string("Create a new branch (for checkout, uses -b flag; for worktree_add, create new branch with -b)"),
                    ]),
                    // reset params
                    "mode": .object([
                        "type": .string("string"),
                        "description": .string("Reset mode: 'soft', 'mixed', or 'hard' (for reset, default 'mixed')"),
                    ]),
                    // stash params
                    "subcommand": .object([
                        "type": .string("string"),
                        "description": .string("Stash subcommand: 'push', 'pop', 'list', 'drop', 'show' (for stash, default 'push')"),
                    ]),
                    // merge params
                    "noFf": .object([
                        "type": .string("boolean"),
                        "description": .string("No fast-forward merge (for merge)"),
                    ]),
                    "squash": .object([
                        "type": .string("boolean"),
                        "description": .string("Squash merge (for merge)"),
                    ]),
                    // rebase params
                    "onto": .object([
                        "type": .string("string"),
                        "description": .string("Target branch to rebase onto (for rebase)"),
                    ]),
                    "abort": .object([
                        "type": .string("boolean"),
                        "description": .string("Abort in-progress rebase (for rebase)"),
                    ]),
                    "continue": .object([
                        "type": .string("boolean"),
                        "description": .string("Continue rebase after conflict resolution (for rebase)"),
                    ]),
                    // cherry_pick params
                    "commit": .object([
                        "type": .string("string"),
                        "description": .string("Commit hash to cherry-pick (for cherry_pick)"),
                    ]),
                    "noCommit": .object([
                        "type": .string("boolean"),
                        "description": .string("Apply changes without committing (for cherry_pick)"),
                    ]),
                    // branch management params
                    "startPoint": .object([
                        "type": .string("string"),
                        "description": .string("Commit or branch to start from (for branch_create, default HEAD)"),
                    ]),
                    "oldName": .object([
                        "type": .string("string"),
                        "description": .string("Current branch name to rename (for branch_rename)"),
                    ]),
                    "newName": .object([
                        "type": .string("string"),
                        "description": .string("New branch name (for branch_rename)"),
                    ]),
                    // worktree params
                    "worktreePath": .object([
                        "type": .string("string"),
                        "description": .string("Path for the worktree directory (for worktree_add, worktree_remove)"),
                    ]),
                    // cleanup params
                    "baseBranch": .object([
                        "type": .string("string"),
                        "description": .string("Base branch for merge checks (for worktree_prune, branch_prune; default 'main')"),
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
        case "init":
            return try await handleInit(repoPath: repoPath)
        case "status":
            return try await handleStatus(repoPath: repoPath)
        case "log":
            return try await handleLog(args: args, repoPath: repoPath)
        case "diff":
            return try await handleDiff(args: args, repoPath: repoPath)
        case "blame":
            return try await handleBlame(args: args, repoPath: repoPath)
        case "branch_info":
            return try await handleBranchInfo(repoPath: repoPath)
        case "merge_analysis":
            return try await handleMergeAnalysis(args: args, repoPath: repoPath)
        case "show":
            return try await handleShow(args: args, repoPath: repoPath)
        case "tag":
            return try await handleTag(args: args, repoPath: repoPath)
        case "remote":
            return try await handleRemote(repoPath: repoPath)
        case "add":
            return try await handleAdd(args: args, repoPath: repoPath)
        case "mv":
            return try await handleMv(args: args, repoPath: repoPath)
        case "commit":
            return try await handleCommit(args: args, repoPath: repoPath)
        case "push":
            return try await handlePush(args: args, repoPath: repoPath)
        case "pull":
            return try await handlePull(args: args, repoPath: repoPath)
        case "checkout":
            return try await handleCheckout(args: args, repoPath: repoPath)
        case "reset":
            return try await handleReset(args: args, repoPath: repoPath)
        case "stash":
            return try await handleStash(args: args, repoPath: repoPath)
        case "merge":
            return try await handleMerge(args: args, repoPath: repoPath)
        case "rebase":
            return try await handleRebase(args: args, repoPath: repoPath)
        case "cherry_pick":
            return try await handleCherryPick(args: args, repoPath: repoPath)
        case "branch_create":
            return try await handleBranchCreate(args: args, repoPath: repoPath)
        case "branch_delete":
            return try await handleBranchDelete(args: args, repoPath: repoPath)
        case "branch_rename":
            return try await handleBranchRename(args: args, repoPath: repoPath)
        case "worktree_list":
            return try await handleWorktreeList(repoPath: repoPath)
        case "worktree_find_by_branch_name":
            return try await handleWorktreeFindByBranchName(args: args, repoPath: repoPath)
        case "worktree_add":
            return try await handleWorktreeAdd(args: args, repoPath: repoPath)
        case "worktree_remove":
            return try await handleWorktreeRemove(args: args, repoPath: repoPath)
        case "worktree_prune":
            return try await handleWorktreePrune(args: args, repoPath: repoPath)
        case "branch_prune":
            return try await handleBranchPrune(args: args, repoPath: repoPath)
        case "branch_find_duplicates":
            return try await handleBranchFindDuplicates(args: args, repoPath: repoPath)
        default:
            throw MCPError.invalidParams(
                "Unknown action: \(action). Valid actions: init, status, log, diff, blame, branch_info, merge_analysis, show, tag, remote, add, mv, commit, push, pull, checkout, reset, stash, merge, rebase, cherry_pick, branch_create, branch_delete, branch_rename, worktree_list, worktree_find_by_branch_name, worktree_add, worktree_remove, worktree_prune, branch_prune, branch_find_duplicates"
            )
        }
    }

    // MARK: - Init

    private static func handleInit(repoPath: String) async throws -> CallTool.Result {
        let result = try await git(["init", repoPath])
        if result.exitCode != 0 {
            return errorResult("git init failed:\n\(result.output)")
        }
        return textResult("Initialized repository at \(repoPath).")
    }

    // MARK: - Status

    private static func handleStatus(repoPath: String) async throws -> CallTool.Result {
        let result = try await git(["-C", repoPath, "status", "--porcelain=v2", "--branch"])
        if result.exitCode != 0 {
            return errorResult("git status failed:\n\(result.output)")
        }
        let parsed = parseStatusOutput(result.output)
        return textResult(parsed)
    }

    private static func parseStatusOutput(_ output: String) -> String {
        var branch = "unknown"
        var upstream = ""
        var ahead = 0
        var behind = 0
        var staged: [String] = []
        var unstaged: [String] = []
        var untracked: [String] = []
        var conflicted: [String] = []

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("# branch.head ") {
                branch = String(line.dropFirst("# branch.head ".count))
            } else if line.hasPrefix("# branch.upstream ") {
                upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                let parts = line.dropFirst("# branch.ab ".count).components(separatedBy: " ")
                for part in parts {
                    if part.hasPrefix("+") { ahead = Int(part.dropFirst()) ?? 0 }
                    if part.hasPrefix("-") { behind = Int(part.dropFirst()) ?? 0 }
                }
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") {
                // Changed entries: "1 XY sub mH mI mW hH hO path" or "2 XY sub mH mI mW hH hO X\tscore path\torigPath"
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 9 else { continue }
                let xy = parts[1]
                let indexStatus = xy.first ?? Character(" ")
                let worktreeStatus = xy.count > 1 ? xy[xy.index(after: xy.startIndex)] : Character(" ")

                // For renamed entries (prefix "2"), the path is after the last tab
                let path: String
                if line.hasPrefix("2 ") {
                    let tabParts = line.components(separatedBy: "\t")
                    path = tabParts.count >= 2 ? tabParts[1] : parts.last ?? ""
                } else {
                    path = parts.dropFirst(8).joined(separator: " ")
                }

                if indexStatus == "U" || worktreeStatus == "U"
                    || (indexStatus == "A" && worktreeStatus == "A")
                    || (indexStatus == "D" && worktreeStatus == "D")
                {
                    conflicted.append(path)
                } else {
                    if indexStatus != "." && indexStatus != " " {
                        let label = statusLabel(indexStatus)
                        staged.append("\(label): \(path)")
                    }
                    if worktreeStatus != "." && worktreeStatus != " " {
                        let label = statusLabel(worktreeStatus)
                        unstaged.append("\(label): \(path)")
                    }
                }
            } else if line.hasPrefix("u ") {
                // Unmerged entry
                let parts = line.components(separatedBy: " ")
                let path = parts.dropFirst(10).joined(separator: " ")
                conflicted.append(path)
            } else if line.hasPrefix("? ") {
                untracked.append(String(line.dropFirst(2)))
            }
        }

        var lines: [String] = []
        lines.append("Branch: \(branch)")
        if !upstream.isEmpty {
            lines.append("Upstream: \(upstream)")
        }
        if ahead > 0 || behind > 0 {
            var tracking: [String] = []
            if ahead > 0 { tracking.append("ahead \(ahead)") }
            if behind > 0 { tracking.append("behind \(behind)") }
            lines.append("Tracking: \(tracking.joined(separator: ", "))")
        }

        if staged.isEmpty && unstaged.isEmpty && untracked.isEmpty && conflicted.isEmpty {
            lines.append("\nWorking tree clean.")
        } else {
            if !staged.isEmpty {
                lines.append("\nStaged changes:")
                staged.forEach { lines.append("  \($0)") }
            }
            if !unstaged.isEmpty {
                lines.append("\nUnstaged changes:")
                unstaged.forEach { lines.append("  \($0)") }
            }
            if !untracked.isEmpty {
                lines.append("\nUntracked files:")
                untracked.forEach { lines.append("  \($0)") }
            }
            if !conflicted.isEmpty {
                lines.append("\nConflicted files:")
                conflicted.forEach { lines.append("  \($0)") }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func statusLabel(_ code: Character) -> String {
        switch code {
        case "M": return "modified"
        case "T": return "type changed"
        case "A": return "added"
        case "D": return "deleted"
        case "R": return "renamed"
        case "C": return "copied"
        default: return "changed"
        }
    }

    // MARK: - Log

    private static func handleLog(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let maxCount = args["maxCount"]?.intValue
            ?? args["maxCount"]?.doubleValue.map({ Int($0) })
            ?? 20
        let filterPath = args["path"]?.stringValue
        let since = args["since"]?.stringValue
        let author = args["author"]?.stringValue

        var gitArgs = [
            "-C", repoPath, "log",
            "--format=%x00%H%x01%an%x01%aI%x01%s%x01%b",
            "--stat",
            "-\(maxCount)",
        ]
        if let since {
            gitArgs.append("--since=\(since)")
        }
        if let author {
            gitArgs.append("--author=\(author)")
        }
        if let filterPath {
            gitArgs.append("--")
            gitArgs.append(filterPath)
        }

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git log failed:\n\(result.output)")
        }

        let parsed = parseLogOutput(result.output)
        if parsed.isEmpty {
            return textResult("No commits found.")
        }
        return textResult(parsed)
    }

    private static func parseLogOutput(_ output: String) -> String {
        // Format: \0<hash>\x01<author>\x01<date>\x01<subject>\x01<body>\n<stat lines>
        // Split on \0 to get per-commit blocks.
        let commits = output.components(separatedBy: "\0")
        var results: [String] = []

        for commit in commits {
            let trimmed = commit.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // First line has fields separated by \x01, remaining lines are stat
            let lines = trimmed.components(separatedBy: "\n")
            let fields = lines[0].components(separatedBy: "\u{01}")
            guard fields.count >= 4 else { continue }

            let hash = String(fields[0].prefix(10))
            let authorName = fields[1]
            let date = fields[2]
            let subject = fields[3]
            let body = fields.count >= 5
                ? fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""

            let stat = lines.dropFirst()
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            var entry = "\(hash) \(subject)\n  \(authorName), \(date)"
            if !body.isEmpty {
                entry += "\n  \(body)"
            }
            if !stat.isEmpty {
                entry += "\n  \(stat.joined(separator: "\n  "))"
            }
            results.append(entry)
        }

        return results.joined(separator: "\n\n")
    }

    // MARK: - Diff

    private static func handleDiff(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let isStaged = args["staged"]?.boolValue ?? false
        let commitRange = args["commitRange"]?.stringValue
        let path = args["path"]?.stringValue

        // First get stat summary
        var statArgs = ["-C", repoPath, "diff", "--stat"]
        var diffArgs = ["-C", repoPath, "diff"]

        if isStaged {
            statArgs.append("--cached")
            diffArgs.append("--cached")
        }
        if let commitRange {
            statArgs.append(commitRange)
            diffArgs.append(commitRange)
        }
        if let path {
            statArgs.append("--")
            statArgs.append(path)
            diffArgs.append("--")
            diffArgs.append(path)
        }

        let statResult = try await git(statArgs)
        let diffResult = try await git(diffArgs)

        if diffResult.exitCode != 0 {
            return errorResult("git diff failed:\n\(diffResult.output)")
        }

        var output = ""
        if !statResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output += "Summary:\n\(statResult.output)\n"
        }

        let diffOutput = diffResult.output
        if diffOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if output.isEmpty {
                return textResult("No differences found.")
            }
            return textResult(output)
        }

        // Cap diff output at ~300 lines
        let diffLines = diffOutput.components(separatedBy: "\n")
        let maxLines = 300
        if diffLines.count > maxLines {
            let truncated = diffLines.prefix(maxLines).joined(separator: "\n")
            output += "\nDiff (truncated to \(maxLines) of \(diffLines.count) lines):\n\(truncated)\n... (\(diffLines.count - maxLines) more lines)"
        } else {
            output += "\nDiff:\n\(diffOutput)"
        }

        return textResult(output)
    }

    // MARK: - Blame

    private static func handleBlame(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let filePath = args["filePath"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: filePath (for blame)")
        }

        let startLine = args["startLine"]?.intValue ?? args["startLine"]?.doubleValue.map({ Int($0) })
        let endLine = args["endLine"]?.intValue ?? args["endLine"]?.doubleValue.map({ Int($0) })

        var gitArgs = ["-C", repoPath, "blame", "--porcelain"]
        if let startLine, let endLine {
            gitArgs.append("-L")
            gitArgs.append("\(startLine),\(endLine)")
        } else if let startLine {
            gitArgs.append("-L")
            gitArgs.append("\(startLine),+1")
        }
        gitArgs.append(filePath)

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git blame failed:\n\(result.output)")
        }

        let parsed = parseBlameOutput(result.output)
        return textResult(parsed)
    }

    private static func parseBlameOutput(_ output: String) -> String {
        let lines = output.components(separatedBy: "\n")
        var results: [String] = []

        var currentHash = ""
        var currentAuthor = ""
        var currentDate = ""
        var currentLineNo = 0

        for line in lines {
            if line.isEmpty { continue }

            // A porcelain blame entry starts with a 40-char hex hash
            let parts = line.components(separatedBy: " ")
            if parts.count >= 3, parts[0].count == 40, parts[0].allSatisfy({ $0.isHexDigit }) {
                currentHash = String(parts[0].prefix(8))
                // The third part is the result line number
                currentLineNo = Int(parts[2]) ?? 0
            } else if line.hasPrefix("author ") {
                currentAuthor = String(line.dropFirst("author ".count))
            } else if line.hasPrefix("author-time ") {
                let timestamp = Int(line.dropFirst("author-time ".count)) ?? 0
                let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                currentDate = formatter.string(from: date)
            } else if line.hasPrefix("\t") {
                // This is the actual code line
                let code = String(line.dropFirst(1))
                results.append(
                    String(format: "%4d  %@  %-16@  %@  %@",
                           currentLineNo, currentHash, currentAuthor, currentDate, code)
                )
            }
        }

        if results.isEmpty {
            return "No blame information available."
        }

        return "Line  Hash      Author            Date        Code\n"
            + results.joined(separator: "\n")
    }

    // MARK: - Branch Info

    private static func handleBranchInfo(repoPath: String) async throws -> CallTool.Result {
        let currentResult = try await git(["-C", repoPath, "rev-parse", "--abbrev-ref", "HEAD"])
        let branchResult = try await git(["-C", repoPath, "branch", "-vv", "--list"])

        if branchResult.exitCode != 0 {
            return errorResult("git branch failed:\n\(branchResult.output)")
        }

        let currentBranch = currentResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        var output = "Current branch: \(currentBranch)\n\nBranches:\n"
        output += branchResult.output
        return textResult(output)
    }

    // MARK: - Merge Analysis

    private static func handleMergeAnalysis(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let source = args["source"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: source (for merge_analysis)")
        }
        let target = args["target"]?.stringValue ?? "HEAD"

        // Show commits that would be merged
        let logResult = try await git([
            "-C", repoPath, "log", "--oneline", "\(target)..\(source)",
        ])

        // Show file diff summary
        let diffStatResult = try await git([
            "-C", repoPath, "diff", "\(target)...\(source)", "--stat",
        ])

        // Try merge-tree to check for conflicts (available in git 2.38+)
        let mergeTreeResult = try await git([
            "-C", repoPath, "merge-tree", "--write-tree", target, source,
        ])

        var output = "Merge analysis: \(source) -> \(target)\n\n"

        // Commits to be merged
        let commits = logResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if commits.isEmpty {
            output += "Commits: None (already up to date)\n"
        } else {
            let commitCount = commits.components(separatedBy: "\n").count
            output += "Commits to merge (\(commitCount)):\n\(commits)\n"
        }

        // Files changed
        let stat = diffStatResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stat.isEmpty {
            output += "\nFiles changed:\n\(stat)\n"
        }

        // Conflict detection
        if mergeTreeResult.exitCode == 0 {
            output += "\nConflicts: None detected (clean merge expected)"
        } else {
            // merge-tree returns non-zero if there are conflicts or if the command is not supported
            let mergeOutput = mergeTreeResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if mergeOutput.contains("CONFLICT") {
                output += "\nConflicts detected:\n\(mergeOutput)"
            } else if mergeOutput.isEmpty {
                // merge-tree might not be available; fall back to a note
                output += "\nConflict detection: Could not determine (git merge-tree may not be available)"
            } else {
                output += "\nMerge tree output:\n\(mergeOutput)"
            }
        }

        return textResult(output)
    }

    // MARK: - Show

    private static func handleShow(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let ref = args["ref"]?.stringValue ?? "HEAD"
        let statOnly = args["stat"]?.boolValue ?? false

        var gitArgs = ["-C", repoPath, "show"]
        if statOnly {
            gitArgs.append("--stat")
        }
        gitArgs.append(ref)

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git show failed:\n\(result.output)")
        }

        let lines = result.output.components(separatedBy: "\n")
        let maxLines = 300
        if lines.count > maxLines {
            let truncated = lines.prefix(maxLines).joined(separator: "\n")
            return textResult("\(truncated)\n... (truncated to \(maxLines) of \(lines.count) lines)")
        }
        return textResult(result.output)
    }

    // MARK: - Tag

    private static func handleTag(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let name = args["name"]?.stringValue
        let ref = args["ref"]?.stringValue ?? "HEAD"
        let message = args["message"]?.stringValue
        let listTags = args["list"]?.boolValue

        // If no name is given, or list is explicitly true, list tags
        if name == nil || listTags == true {
            let result = try await git(["-C", repoPath, "tag", "--list"])
            if result.exitCode != 0 {
                return errorResult("git tag --list failed:\n\(result.output)")
            }
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.isEmpty {
                return textResult("No tags found.")
            }
            return textResult("Tags:\n\(output)")
        }

        // Create a tag
        var gitArgs = ["-C", repoPath, "tag"]
        if let message {
            gitArgs.append("-a")
            gitArgs.append("-m")
            gitArgs.append(message)
        }
        gitArgs.append(name!)
        gitArgs.append(ref)

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git tag failed:\n\(result.output)")
        }
        return textResult("Tagged \(ref) as \(name!).")
    }

    // MARK: - Remote

    private static func handleRemote(repoPath: String) async throws -> CallTool.Result {
        let result = try await git(["-C", repoPath, "remote", "-v"])
        if result.exitCode != 0 {
            return errorResult("git remote failed:\n\(result.output)")
        }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty {
            return textResult("No remotes configured.")
        }
        return textResult("Remotes:\n\(output)")
    }

    // MARK: - Add

    private static func handleAdd(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let files = args["files"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: files (for add)")
        }

        var gitArgs = ["-C", repoPath, "add"]
        let fileParts = files.components(separatedBy: " ").filter { !$0.isEmpty }
        gitArgs.append(contentsOf: fileParts)

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git add failed:\n\(result.output)")
        }
        return textResult("Staged: \(fileParts.joined(separator: ", "))")
    }

    // MARK: - Mv

    private static func handleMv(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let source = args["source"]?.stringValue, !source.isEmpty else {
            throw MCPError.invalidParams("Missing required argument: source (for mv)")
        }
        guard let destination = args["destination"]?.stringValue, !destination.isEmpty else {
            throw MCPError.invalidParams("Missing required argument: destination (for mv)")
        }
        let force = args["force"]?.boolValue ?? false

        var gitArgs = ["-C", repoPath, "mv"]
        if force {
            gitArgs.append("-f")
        }
        gitArgs.append(source)
        gitArgs.append(destination)

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git mv failed:\n\(result.output)")
        }
        return textResult("Moved \(source) -> \(destination).")
    }

    // MARK: - Commit

    private static func handleCommit(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let message = args["message"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: message (for commit)")
        }
        let amend = args["amend"]?.boolValue ?? false

        var gitArgs = ["-C", repoPath, "commit", "-m", message]
        if amend {
            gitArgs.append("--amend")
        }

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git commit failed:\n\(result.output)")
        }
        return textResult("Committed.")
    }

    // MARK: - Push

    private static func handlePush(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let remote = args["remote"]?.stringValue ?? "origin"
        let branch = args["branch"]?.stringValue
        let force = args["force"]?.boolValue ?? false
        let setUpstream = args["setUpstream"]?.boolValue ?? false

        // --porcelain emits one tab-delimited status line per ref and drops the
        // remote-side hint banner ("Create a pull request..."); --no-progress
        // drops the counting/compressing chatter. Together they collapse a push
        // to its essential per-ref result.
        var gitArgs = ["-C", repoPath, "push", "--porcelain", "--no-progress"]
        if force {
            gitArgs.append("--force")
        }
        if setUpstream {
            gitArgs.append("-u")
        }
        gitArgs.append(remote)
        if let branch {
            gitArgs.append(branch)
        }

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git push failed:\n\(summarizePush(result.output))")
        }
        return textResult(summarizePush(result.output))
    }

    /// Distills `git push --porcelain` output to its per-ref result lines.
    /// Porcelain emits `<flag>\t<from>:<to>\t<summary>` per ref plus bookkeeping
    /// lines ("To <url>", a trailing "Done"); keep only refs, rendered as
    /// `<summary>  <ref>`. Falls back to the trimmed raw output if nothing
    /// parses (e.g. "Everything up-to-date" on stderr).
    static func summarizePush(_ output: String) -> String {
        let refLines = output.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { return nil }
            let ref = fields[1].split(separator: ":").last.map(String.init) ?? String(fields[1])
            return "\(fields[2])  \(ref)"
        }
        if refLines.isEmpty {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return refLines.joined(separator: "\n")
    }

    // MARK: - Pull

    private static func handlePull(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let remote = args["remote"]?.stringValue
        let branch = args["branch"]?.stringValue
        let useRebase = args["rebase"]?.boolValue ?? false

        var gitArgs = ["-C", repoPath, "pull"]
        if useRebase {
            gitArgs.append("--rebase")
        }
        if let remote {
            gitArgs.append(remote)
            if let branch {
                gitArgs.append(branch)
            }
        }

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git pull failed:\n\(result.output)")
        }
        return textResult(result.output)
    }

    // MARK: - Checkout

    private static func handleCheckout(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let target = args["target"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: target (for checkout)")
        }
        let createBranch = args["createBranch"]?.boolValue ?? false

        var gitArgs = ["-C", repoPath, "checkout"]
        if createBranch {
            gitArgs.append("-b")
        }
        gitArgs.append(target)

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git checkout failed:\n\(result.output)")
        }

        let branch = try? await git(["-C", repoPath, "rev-parse", "--abbrev-ref", "HEAD"])
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let branch, !branch.isEmpty, branch != "HEAD" {
            let prefix = createBranch ? "Created and checked out" : "Checked out"
            return textResult("\(prefix) branch \(branch).")
        }
        return textResult("Checked out \(target).")
    }

    // MARK: - Reset

    private static func handleReset(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let target = args["target"]?.stringValue ?? "HEAD"
        let mode = args["mode"]?.stringValue ?? "mixed"
        let files = args["files"]?.stringValue

        var gitArgs = ["-C", repoPath, "reset"]

        if let files {
            // Unstage specific files: git reset <target> -- <files>
            gitArgs.append(target)
            gitArgs.append("--")
            let fileParts = files.components(separatedBy: " ").filter { !$0.isEmpty }
            gitArgs.append(contentsOf: fileParts)
        } else {
            // Full reset: git reset --<mode> <target>
            switch mode {
            case "soft":
                gitArgs.append("--soft")
            case "hard":
                gitArgs.append("--hard")
            default:
                gitArgs.append("--mixed")
            }
            gitArgs.append(target)
        }

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git reset failed:\n\(result.output)")
        }
        if files != nil {
            return textResult("Unstaged files (reset to \(target)).")
        }
        return textResult("Reset --\(mode) to \(target).")
    }

    // MARK: - Stash

    private static func handleStash(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let subcommand = args["subcommand"]?.stringValue ?? "push"
        let message = args["message"]?.stringValue

        var gitArgs = ["-C", repoPath, "stash"]
        gitArgs.append(subcommand)

        if subcommand == "push", let message {
            gitArgs.append("-m")
            gitArgs.append(message)
        }

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git stash \(subcommand) failed:\n\(result.output)")
        }
        return textResult(result.output)
    }

    // MARK: - Merge

    private static func handleMerge(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let branch = args["branch"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: branch (for merge)")
        }
        let noFf = args["noFf"]?.boolValue ?? false
        let squash = args["squash"]?.boolValue ?? false

        var gitArgs = ["-C", repoPath, "merge"]
        if noFf {
            gitArgs.append("--no-ff")
        }
        if squash {
            gitArgs.append("--squash")
        }
        gitArgs.append(branch)

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git merge failed:\n\(result.output)")
        }
        return textResult(result.output)
    }

    // MARK: - Rebase

    private static func handleRebase(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let abortRebase = args["abort"]?.boolValue ?? false
        let continueRebase = args["continue"]?.boolValue ?? false

        var gitArgs = ["-C", repoPath, "rebase"]

        if abortRebase {
            gitArgs.append("--abort")
        } else if continueRebase {
            gitArgs.append("--continue")
        } else {
            guard let onto = args["onto"]?.stringValue else {
                throw MCPError.invalidParams("Missing required argument: onto (for rebase)")
            }
            gitArgs.append(onto)
        }

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git rebase failed:\n\(result.output)")
        }
        return textResult(result.output)
    }

    // MARK: - Cherry Pick

    private static func handleCherryPick(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let commit = args["commit"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: commit (for cherry_pick)")
        }
        let noCommit = args["noCommit"]?.boolValue ?? false

        var gitArgs = ["-C", repoPath, "cherry-pick"]
        if noCommit {
            gitArgs.append("--no-commit")
        }
        gitArgs.append(commit)

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git cherry-pick failed:\n\(result.output)")
        }
        return textResult(result.output)
    }

    // MARK: - Branch Create

    private static func handleBranchCreate(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let name = args["name"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: name (for branch_create)")
        }
        let startPoint = args["startPoint"]?.stringValue

        var gitArgs = ["-C", repoPath, "branch", name]
        if let startPoint {
            gitArgs.append(startPoint)
        }

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git branch failed:\n\(result.output)")
        }
        return textResult("Created branch \(name).")
    }

    // MARK: - Branch Delete

    private static func handleBranchDelete(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let name = args["name"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: name (for branch_delete)")
        }
        let force = args["force"]?.boolValue ?? false

        let flag = force ? "-D" : "-d"
        let result = try await git(["-C", repoPath, "branch", flag, name])
        if result.exitCode != 0 {
            return errorResult("git branch \(flag) failed:\n\(result.output)")
        }
        return textResult("Deleted branch \(name).")
    }

    // MARK: - Branch Rename

    private static func handleBranchRename(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let oldName = args["oldName"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: oldName (for branch_rename)")
        }
        guard let newName = args["newName"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: newName (for branch_rename)")
        }

        let result = try await git(["-C", repoPath, "branch", "-m", oldName, newName])
        if result.exitCode != 0 {
            return errorResult("git branch -m failed:\n\(result.output)")
        }
        return textResult("Renamed \(oldName) to \(newName).")
    }

    // MARK: - Worktree List

    private static func handleWorktreeList(repoPath: String) async throws -> CallTool.Result {
        let result = try await git(["-C", repoPath, "worktree", "list"])
        if result.exitCode != 0 {
            return errorResult("git worktree list failed:\n\(result.output)")
        }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty {
            return textResult("No worktrees found.")
        }
        return textResult("Worktrees:\n\(output)")
    }

    // MARK: - Worktree Find By Branch Name

    private static func handleWorktreeFindByBranchName(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let branch = args["branch"]?.stringValue, !branch.isEmpty else {
            throw MCPError.invalidParams("Missing required argument: branch (for worktree_find_by_branch_name)")
        }

        let result = try await git(["-C", repoPath, "worktree", "list", "--porcelain"])
        if result.exitCode != 0 {
            return errorResult("git worktree list failed:\n\(result.output)")
        }

        // Match against the bare name and the fully-qualified ref, so callers may pass either.
        let target = branch.hasPrefix("refs/heads/")
            ? String(branch.dropFirst("refs/heads/".count))
            : branch
        let matches = parseWorktreeBranchRefs(result.output)
            .filter { $0.branch == target }
            .map { $0.path }

        guard let path = matches.first else {
            return textResult("No worktree found for branch \(target).")
        }
        return textResult(path)
    }

    /// Every worktree paired with its checked-out branch (main and linked, excluding detached HEADs).
    private static func parseWorktreeBranchRefs(_ output: String) -> [(path: String, branch: String)] {
        var refs: [(path: String, branch: String)] = []
        var path: String?
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch "), let currentPath = path {
                let refPath = String(line.dropFirst("branch ".count))
                let name = refPath.hasPrefix("refs/heads/")
                    ? String(refPath.dropFirst("refs/heads/".count))
                    : refPath
                refs.append((path: currentPath, branch: name))
            }
        }
        return refs
    }

    // MARK: - Worktree Add

    private static func handleWorktreeAdd(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let worktreePath = args["worktreePath"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: worktreePath (for worktree_add)")
        }
        let branch = args["branch"]?.stringValue
        let createBranch = args["createBranch"]?.boolValue ?? false

        var gitArgs = ["-C", repoPath, "worktree", "add"]
        if createBranch, let branch {
            gitArgs.append("-b")
            gitArgs.append(branch)
        }
        gitArgs.append(worktreePath)
        if !createBranch, let branch {
            gitArgs.append(branch)
        }

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git worktree add failed:\n\(result.output)")
        }

        let checkedOut = try? await git(["-C", worktreePath, "rev-parse", "--abbrev-ref", "HEAD"])
            .output.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines = ["Worktree added: \(worktreePath)"]
        if createBranch, let branch {
            lines.append("Branch created: \(branch)")
        }
        if let checkedOut, !checkedOut.isEmpty {
            lines.append("Checked out branch: \(checkedOut)")
        }
        return textResult(lines.joined(separator: "\n"))
    }

    // MARK: - Worktree Remove

    private static func handleWorktreeRemove(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        guard let worktreePath = args["worktreePath"]?.stringValue else {
            throw MCPError.invalidParams("Missing required argument: worktreePath (for worktree_remove)")
        }
        let force = args["force"]?.boolValue ?? false

        var gitArgs = ["-C", repoPath, "worktree", "remove"]
        if force {
            gitArgs.append("--force")
        }
        gitArgs.append(worktreePath)

        let result = try await git(gitArgs)
        if result.exitCode != 0 {
            return errorResult("git worktree remove failed:\n\(result.output)")
        }
        return textResult("Worktree removed: \(worktreePath)")
    }

    // MARK: - Worktree Prune

    private static func handleWorktreePrune(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let baseBranch = args["baseBranch"]?.stringValue ?? "main"
        let force = args["force"]?.boolValue ?? false

        // Get worktree list in porcelain format
        let listResult = try await git(["-C", repoPath, "worktree", "list", "--porcelain"])
        if listResult.exitCode != 0 {
            return errorResult("git worktree list failed:\n\(listResult.output)")
        }

        let worktrees = parseWorktreePorcelain(listResult.output)
        var removed: [String] = []
        var skipped: [String] = []
        var errors: [String] = []

        for worktree in worktrees {
            guard let branch = worktree.branch else { continue }
            guard !worktree.isMain else { continue }

            // Check if branch is merged into baseBranch
            let mergedResult = try await git(["-C", repoPath, "branch", "--merged", baseBranch])
            let mergedBranches = mergedResult.output
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if mergedBranches.contains(branch) {
                let removeFlag = force ? "--force" : ""
                let removeArgs = removeFlag.isEmpty
                    ? ["-C", repoPath, "worktree", "remove", worktree.path]
                    : ["-C", repoPath, "worktree", "remove", removeFlag, worktree.path]
                let removeResult = try await git(removeArgs)
                if removeResult.exitCode == 0 {
                    removed.append("\(branch) (\(worktree.path))")
                } else {
                    errors.append("\(branch): \(removeResult.output)")
                }
            } else {
                skipped.append(branch)
            }
        }

        var output = ""
        if !removed.isEmpty {
            output += "Worktrees removed: \(removed.joined(separator: ", "))\n"
        }
        if !skipped.isEmpty {
            output += "Worktrees skipped (not merged): \(skipped.joined(separator: ", "))\n"
        }
        if !errors.isEmpty {
            output += "Errors: \(errors.joined(separator: "; "))"
        }
        if output.isEmpty {
            output = "No worktrees to prune."
        }
        return textResult(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parseWorktreePorcelain(_ output: String) -> [(path: String, branch: String?, isMain: Bool)] {
        var worktrees: [(path: String, branch: String?, isMain: Bool)] = []
        let lines = output.components(separatedBy: "\n")
        var i = 0
        var isFirstWorktree = true

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("worktree ") {
                let path = String(line.dropFirst("worktree ".count))
                var branch: String?
                var isBranch = true

                i += 1
                while i < lines.count {
                    let nextLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if nextLine.hasPrefix("branch ") {
                        let refPath = String(nextLine.dropFirst("branch ".count))
                        branch = refPath.hasPrefix("refs/heads/")
                            ? String(refPath.dropFirst("refs/heads/".count))
                            : refPath
                        i += 1
                        break
                    } else if nextLine == "detached" {
                        isBranch = false
                        i += 1
                        break
                    } else if nextLine.hasPrefix("worktree ") || nextLine.isEmpty {
                        break
                    } else {
                        i += 1
                    }
                }

                if isBranch && !isFirstWorktree {
                    worktrees.append((path: path, branch: branch, isMain: false))
                } else if isFirstWorktree {
                    isFirstWorktree = false
                }
            } else {
                i += 1
            }
        }

        return worktrees
    }

    // MARK: - Branch Prune

    private static func handleBranchPrune(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        let baseBranch = args["baseBranch"]?.stringValue ?? "main"
        let force = args["force"]?.boolValue ?? false

        // Get current branch
        let currentResult = try await git(["-C", repoPath, "rev-parse", "--abbrev-ref", "HEAD"])
        let currentBranch = currentResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Get branches checked out in worktrees
        let worktreeListResult = try await git(["-C", repoPath, "worktree", "list", "--porcelain"])
        let worktreeBranches = parseWorktreePorcelain(worktreeListResult.output)
            .compactMap { $0.branch }

        // Get all merged branches
        let mergedResult = try await git(["-C", repoPath, "branch", "--merged", baseBranch])
        let mergedBranches = mergedResult.output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let protected = Set(["main", "master", "develop", currentBranch] + worktreeBranches)
        var removed: [String] = []
        var skipped: [String] = []

        for branch in mergedBranches {
            if protected.contains(branch) {
                skipped.append(branch)
            } else {
                let flag = force ? "-D" : "-d"
                let deleteResult = try await git(["-C", repoPath, "branch", flag, branch])
                if deleteResult.exitCode == 0 {
                    removed.append(branch)
                } else {
                    skipped.append(branch)
                }
            }
        }

        var output = ""
        if !removed.isEmpty {
            output += "Branches removed: \(removed.joined(separator: ", "))\n"
        }
        if !skipped.isEmpty {
            output += "Branches protected/kept: \(skipped.joined(separator: ", "))"
        }
        if output.isEmpty {
            output = "No branches to prune."
        }
        return textResult(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Branch Find Duplicates

    private static func handleBranchFindDuplicates(args: [String: Value], repoPath: String) async throws -> CallTool.Result {
        // Get all branches
        let branchResult = try await git(["-C", repoPath, "branch", "--list"])
        if branchResult.exitCode != 0 {
            return errorResult("git branch failed:\n\(branchResult.output)")
        }

        let branches = branchResult.output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard branches.count > 1 else {
            return textResult("Only one or no branches found. No duplicates to detect.")
        }

        var duplicates: [String: [String]] = [:]

        for i in 0..<branches.count {
            for j in (i+1)..<branches.count {
                let branchA = branches[i]
                let branchB = branches[j]

                let cherryResult = try await git(["-C", repoPath, "cherry", "-v", branchB, branchA])
                let duplicateShas = cherryResult.output
                    .components(separatedBy: "\n")
                    .filter { $0.hasPrefix("-") }
                    .compactMap { line -> String? in
                        let parts = line.dropFirst().trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
                        return parts.first
                    }

                for sha in duplicateShas {
                    if duplicates[sha] == nil {
                        duplicates[sha] = []
                    }
                    duplicates[sha]?.append(contentsOf: [branchA, branchB])
                }
            }
        }

        guard !duplicates.isEmpty else {
            return textResult("No duplicate commits found.")
        }

        var output = "Duplicate commits:\n"
        for (sha, branchList) in duplicates.sorted(by: { $0.key < $1.key }) {
            let uniqueBranches = Array(Set(branchList)).sorted()
            let shortSha = String(sha.prefix(8))

            // Get commit subject
            let logResult = try await git(["-C", repoPath, "log", "-1", "--format=%s", sha])
            let subject = logResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

            output += "  \(shortSha) \"\(subject)\" — on: \(uniqueBranches.joined(separator: ", "))\n"
        }

        return textResult(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Helpers

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
