import Foundation
import MCP

enum GitHubTool {
    static let name = "github-tools"

    /// `gh` is not on a spawned process's default PATH. Resolve to the first
    /// executable among the common install locations, falling back to a bare
    /// name so PATH lookup still has a chance if the user installed elsewhere.
    private static let ghPath: String = {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "\(NSHomeDirectory())/.local/bin/gh",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "gh"
    }()

    private static let listLimit = 100

    static var definition: Tool {
        Tool(
            name: name,
            description: "GitHub operations via the gh CLI. Supports list-active-prs (open and draft pull requests with per-PR check health).",
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

        switch action {
        case "list-active-prs":
            return try await handleListActivePRs(repoPath: repoPath)
        default:
            throw MCPError.invalidParams("Unknown action: \(action). Valid actions: list-active-prs")
        }
    }

    // MARK: - List Active PRs

    private static func handleListActivePRs(repoPath: String) async throws -> CallTool.Result {
        // gh has no -C flag; it infers the repo from the cwd's git remote.
        let result = try await gh([
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

    private static func format(pr: PullRequest) -> String {
        var lines = [
            "#\(pr.number)  \(pr.title)",
            "  state: \(pr.isDraft ? "draft" : "open")",
            "  target: \(pr.baseRefName)",
            "  needs-rebase: \(pr.needsRebase ? "yes" : "no")",
        ]

        let rollup = pr.statusCheckRollup ?? []
        let failing = rollup.filter(\.isFailing)
        if rollup.isEmpty {
            lines.append("  checks: none")
        } else if failing.isEmpty {
            lines.append("  checks: passing")
        } else {
            lines.append("  failing checks:")
            for check in failing {
                let suffix = check.url.map { "  (\($0))" } ?? ""
                lines.append("    - \(check.displayName)\(suffix)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Decoding

    private struct PullRequest: Decodable {
        let number: Int
        let title: String
        let isDraft: Bool
        let state: String
        let baseRefName: String
        let statusCheckRollup: [Check]?
        let mergeStateStatus: String?

        /// BEHIND: base advanced past the PR's merge-base. DIRTY: the merge has
        /// conflicts. Both require the author to rebase (or merge) onto base.
        /// nil when gh omits the field (e.g. permissions) — reported as no.
        var needsRebase: Bool {
            mergeStateStatus == "BEHIND" || mergeStateStatus == "DIRTY"
        }
    }

    /// A statusCheckRollup entry. gh emits two node shapes discriminated by
    /// `__typename`: CheckRun (Actions/apps) with conclusion+detailsUrl, and
    /// StatusContext (legacy commit statuses) with state+targetUrl. All fields
    /// are optional so either shape decodes and gh adding fields is tolerated.
    private struct Check: Decodable {
        let typename: String?
        let name: String?
        let conclusion: String?
        let detailsUrl: String?
        let context: String?
        let state: String?
        let targetUrl: String?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case name, conclusion, detailsUrl, context, state, targetUrl
        }

        var isFailing: Bool {
            let checkRunFailures: Set<String> = [
                "FAILURE", "TIMED_OUT", "CANCELLED", "STARTUP_FAILURE", "ACTION_REQUIRED",
            ]
            let statusFailures: Set<String> = ["FAILURE", "ERROR"]
            if let conclusion, checkRunFailures.contains(conclusion) { return true }
            if let state, statusFailures.contains(state) { return true }
            return false
        }

        var displayName: String {
            name ?? context ?? "unknown check"
        }

        var url: String? {
            detailsUrl ?? targetUrl
        }
    }

    // MARK: - Helpers

    private static func gh(_ arguments: [String], workingDirectory: String) async throws -> ShellCommand.Result {
        try await ShellCommand.run(ghPath, arguments: arguments, workingDirectory: workingDirectory)
    }

    private static func textResult(_ text: String) -> CallTool.Result {
        .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    private static func errorResult(_ text: String) -> CallTool.Result {
        .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
    }
}
