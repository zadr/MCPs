import Foundation
import MCP

enum GitHubTool {
    static let name = "github-tools"

    /// posix_spawn with an absolute path does no PATH search, so resolve `gh`
    /// against $PATH ourselves. nil when $PATH is unset/empty or holds no
    /// executable `gh`; the tool is then withheld from the registry entirely.
    private static let ghPath: String? = {
        guard let path = ProcessInfo.processInfo.environment["PATH"], !path.isEmpty else {
            return nil
        }
        let fm = FileManager.default
        return path.split(separator: ":", omittingEmptySubsequences: true)
            .map { "\($0)/gh" }
            .first { fm.isExecutableFile(atPath: $0) }
    }()

    /// Whether `gh` was found on $PATH. The registry only advertises this tool
    /// and routes calls to it when true.
    static var isAvailable: Bool { ghPath != nil }

    private static let listLimit = 100

    static var definition: Tool {
        Tool(
            name: name,
            description: "GitHub operations via the gh CLI. Supports list-active-prs (open and draft pull requests with per-PR check health and merge state, including conflicts).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("list-active-prs"),
                        ]),
                        "description": .string("The GitHub action to perform. One of: list-active-prs"),
                    ]),
                    "repoPath": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to a local clone; gh infers the repository from its remote"),
                    ]),
                ]),
                "required": .array([.string("action"), .string("repoPath")]),
            ]),
            annotations: .init(readOnlyHint: true, openWorldHint: true)
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
        // Normally unreachable: the registry withholds this tool when gh is
        // absent. Guard anyway so a direct call can't reach the spawner with a
        // nil path.
        guard let ghPath else {
            throw MCPError.invalidParams("gh not found on $PATH. Install the GitHub CLI and ensure it is on PATH.")
        }

        switch action {
        case "list-active-prs":
            return try await handleListActivePRs(ghPath: ghPath, repoPath: repoPath)
        default:
            throw MCPError.invalidParams("Unknown action: \(action). Valid actions: list-active-prs")
        }
    }

    // MARK: - List Active PRs

    private static func handleListActivePRs(ghPath: String, repoPath: String) async throws -> CallTool.Result {
        // gh has no -C flag; it infers the repo from the cwd's git remote.
        let result = try await gh(ghPath, [
            "pr", "list",
            "--state", "open",
            "--limit", "\(listLimit)",
            "--json", "number,title,isDraft,state,baseRefName,statusCheckRollup,mergeStateStatus",
        ], workingDirectory: repoPath)

        if result.exitCode != 0 {
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.contains("gh auth login") || output.contains("authentication") {
                return errorResult("gh is not authenticated. Run `gh auth login`.\n\n\(output)")
            }
            return errorResult("gh pr list failed:\n\(output)")
        }

        let prs: [PullRequest]
        do {
            prs = try JSONDecoder().decode([PullRequest].self, from: Data(result.output.utf8))
        } catch {
            return errorResult("Could not parse gh output: \(error)\n\n\(result.output)")
        }

        if prs.isEmpty {
            return textResult("No open PRs.")
        }

        var blocks = prs.map(format(pr:))
        if prs.count >= listLimit {
            blocks.append("(showing first \(listLimit); more may exist)")
        }
        return textResult(blocks.joined(separator: "\n\n"))
    }

    static func format(pr: PullRequest) -> String {
        var lines = [
            "#\(pr.number)  \(pr.title)",
            "  state: \(pr.isDraft ? "draft" : "open")",
            "  target: \(pr.baseRefName)",
            "  merge: \(pr.mergeState.description)",
        ]

        let rollup = pr.statusCheckRollup ?? []
        let failing = rollup.filter { $0.outcome == .failing }
        let pending = rollup.filter { $0.outcome == .pending }
        if rollup.isEmpty {
            lines.append("  checks: none")
        } else if !failing.isEmpty {
            // Failing dominates: a real failure is never masked by in-flight checks.
            lines.append("  failing checks:")
            for check in failing {
                let suffix = check.url.map { "  (\($0))" } ?? ""
                lines.append("    - \(check.displayName)\(suffix)")
            }
        } else if !pending.isEmpty {
            lines.append("  checks: pending (\(pending.count) running)")
        } else {
            lines.append("  checks: passing")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Decoding

    struct PullRequest: Decodable {
        let number: Int
        let title: String
        let isDraft: Bool
        let state: String
        let baseRefName: String
        let statusCheckRollup: [Check]?
        let mergeStateStatus: String?

        var mergeState: MergeState {
            MergeState(mergeStateStatus)
        }
    }

    /// Distilled from GitHub's mergeStateStatus. `conflicting` (DIRTY) means the
    /// merge itself fails and the author must resolve conflicts; `behind` means
    /// base moved ahead but merges cleanly, needing only a rebase/update.
    /// Everything else collapses to `clean` — mergeable as far as this tool
    /// reports. `unknown` covers gh omitting the field (permissions) or GitHub
    /// still computing mergeability.
    enum MergeState: Equatable {
        case conflicting, behind, clean, unknown

        init(_ status: String?) {
            switch status {
            case "DIRTY": self = .conflicting
            case "BEHIND": self = .behind
            case .some: self = .clean
            case nil: self = .unknown
            }
        }

        var description: String {
            switch self {
            case .conflicting: return "conflicting"
            case .behind: return "behind base (needs rebase)"
            case .clean: return "clean"
            case .unknown: return "unknown"
            }
        }
    }

    enum CheckOutcome {
        case passing, pending, failing
    }

    /// A statusCheckRollup entry. gh emits two node shapes discriminated by
    /// `__typename`: CheckRun (Actions/apps) with status+conclusion+detailsUrl,
    /// and StatusContext (legacy commit statuses) with state+targetUrl. All
    /// fields are optional so either shape decodes and gh adding fields is
    /// tolerated.
    struct Check: Decodable {
        let typename: String?
        let name: String?
        let status: String?
        let conclusion: String?
        let detailsUrl: String?
        let context: String?
        let state: String?
        let targetUrl: String?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case name, status, conclusion, detailsUrl, context, state, targetUrl
        }

        /// gh emits `conclusion: ""` for a CheckRun that has not concluded, so an
        /// empty string must read as "no value", not as a concluded result.
        private static func normalized(_ value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        var outcome: CheckOutcome {
            let checkRunFailures: Set<String> = [
                "FAILURE", "TIMED_OUT", "CANCELLED", "STARTUP_FAILURE", "ACTION_REQUIRED",
            ]
            let statusFailures: Set<String> = ["FAILURE", "ERROR"]
            let inProgress: Set<String> = [
                "QUEUED", "IN_PROGRESS", "PENDING", "WAITING", "REQUESTED",
            ]
            let statusPending: Set<String> = ["PENDING", "EXPECTED"]

            let conclusion = Self.normalized(conclusion)
            let status = Self.normalized(status)
            let state = Self.normalized(state)

            if let conclusion, checkRunFailures.contains(conclusion) { return .failing }
            if let state, statusFailures.contains(state) { return .failing }

            // CheckRun: unconcluded when status is in-flight or conclusion absent.
            if let status, inProgress.contains(status) { return .pending }
            if status != nil, conclusion == nil { return .pending }
            // StatusContext: pending state, or (legacy) no terminal signal at all.
            if let state, statusPending.contains(state) { return .pending }
            if status == nil, conclusion == nil, state == nil { return .pending }

            return .passing
        }

        var displayName: String {
            name ?? context ?? "unknown check"
        }

        var url: String? {
            detailsUrl ?? targetUrl
        }
    }

    // MARK: - Helpers

    private static func gh(_ executable: String, _ arguments: [String], workingDirectory: String) async throws -> ShellCommand.Result {
        try await ShellCommand.run(executable, arguments: arguments, workingDirectory: workingDirectory)
    }

    private static func textResult(_ text: String) -> CallTool.Result {
        .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    private static func errorResult(_ text: String) -> CallTool.Result {
        .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
    }
}
