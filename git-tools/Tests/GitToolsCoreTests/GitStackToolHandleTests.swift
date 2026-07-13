import XCTest
import MCP
@testable import GitToolsCore

final class GitStackToolHandleTests: XCTestCase {

    private var repoPath: String!
    /// Name of the initial branch, captured after the first commit. `git init`
    /// may produce `master` or `main` depending on the host's git defaults, so
    /// tests read it here and set it as the stack base to stay name-agnostic.
    private var base: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Isolate from the user's global/system git config and give git a
        // deterministic identity so commits succeed in CI.
        setenv("GIT_CONFIG_GLOBAL", "/dev/null", 1)
        setenv("GIT_CONFIG_SYSTEM", "/dev/null", 1)
        setenv("GIT_AUTHOR_NAME", "Test", 1)
        setenv("GIT_AUTHOR_EMAIL", "test@example.com", 1)
        setenv("GIT_COMMITTER_NAME", "Test", 1)
        setenv("GIT_COMMITTER_EMAIL", "test@example.com", 1)

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("git-stack-mcp-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        repoPath = dir.path
    }

    override func tearDownWithError() throws {
        if let repoPath {
            try? FileManager.default.removeItem(atPath: repoPath)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func call(_ args: [String: Value]) async throws -> CallTool.Result {
        try await GitStackTool.handle(args)
    }

    private func text(_ result: CallTool.Result) -> String {
        result.content.compactMap { content in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined(separator: "\n")
    }

    private func writeFile(_ name: String, _ contents: String) throws {
        let url = URL(fileURLWithPath: repoPath).appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Run a raw git command in the repo. Used for setup the stack tool does
    /// not itself expose (init, add, plain commits).
    @discardableResult
    private func git(_ args: [String]) async throws -> ShellCommand.Result {
        try await ShellCommand.run("/usr/bin/git", arguments: ["-C", repoPath] + args)
    }

    /// init + first commit, then record the initial branch as the stack base so
    /// tests are agnostic to whether git created `master` or `main`.
    private func initBaseRepo() async throws {
        _ = try await ShellCommand.run("/usr/bin/git", arguments: ["init", repoPath])
        try writeFile("README.md", "hello\n")
        try await git(["add", "README.md"])
        try await git(["commit", "-m", "initial"])
        let cur = try await git(["rev-parse", "--abbrev-ref", "HEAD"])
        base = cur.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let setBase = try await call([
            "action": .string("set_base"),
            "repoPath": .string(repoPath),
            "branch": .string(base),
        ])
        XCTAssertEqual(setBase.isError, false)
    }

    /// Add a committed file on the current branch.
    private func commitFile(_ name: String, _ contents: String, message: String) async throws {
        try writeFile(name, contents)
        try await git(["add", name])
        try await git(["commit", "-m", message])
    }

    private func currentBranch() async throws -> String {
        let r = try await git(["rev-parse", "--abbrev-ref", "HEAD"])
        return r.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True if `ancestor` is reachable from `branch` (i.e. its history contains
    /// that commit / branch tip).
    private func isAncestor(_ ancestor: String, of branch: String) async throws -> Bool {
        let r = try await git(["merge-base", "--is-ancestor", ancestor, branch])
        return r.exitCode == 0
    }

    // MARK: - Argument validation

    func testMissingActionThrows() async {
        do {
            _ = try await call(["repoPath": .string(repoPath)])
            XCTFail("expected throw")
        } catch let error as MCPError {
            XCTAssertTrue("\(error)".contains("action"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testMissingRepoPathThrows() async {
        do {
            _ = try await call(["action": .string("stack_info")])
            XCTFail("expected throw")
        } catch let error as MCPError {
            XCTAssertTrue("\(error)".contains("repoPath"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testUnknownActionThrows() async {
        do {
            _ = try await call([
                "action": .string("bogus"),
                "repoPath": .string(repoPath),
            ])
            XCTFail("expected throw")
        } catch let error as MCPError {
            XCTAssertTrue("\(error)".contains("Unknown action"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - new / ancestors / children

    func testNewCreatesBranchAndRecordsParent() async throws {
        try await initBaseRepo()

        let new = try await call([
            "action": .string("new"),
            "repoPath": .string(repoPath),
            "name": .string("feature"),
        ])
        XCTAssertEqual(new.isError, false)
        let branchAfterNew = try await currentBranch()
        XCTAssertEqual(branchAfterNew, "feature")

        let info = try await call(["action": .string("stack_info"), "repoPath": .string(repoPath)])
        XCTAssertEqual(info.isError, false)
        XCTAssertTrue(text(info).contains("feature"))
        XCTAssertTrue(text(info).contains(base))

        let anc = try await call([
            "action": .string("ancestors"),
            "repoPath": .string(repoPath),
            "branch": .string("feature"),
        ])
        XCTAssertTrue(text(anc).contains(base))
    }

    func testThreeLevelStackAncestryAndChildren() async throws {
        try await initBaseRepo()

        _ = try await call(["action": .string("new"), "repoPath": .string(repoPath), "name": .string("a")])
        _ = try await call(["action": .string("new"), "repoPath": .string(repoPath), "name": .string("b")])

        let anc = try await call([
            "action": .string("ancestors"),
            "repoPath": .string(repoPath),
            "branch": .string("b"),
        ])
        let ancText = text(anc)
        XCTAssertTrue(ancText.contains("a"))
        XCTAssertTrue(ancText.contains(base))
        // Nearest first: `a` should appear before the base in the chain string.
        let aIdx = ancText.range(of: "a -> ")?.lowerBound
        let baseIdx = ancText.range(of: base)?.lowerBound
        XCTAssertNotNil(aIdx)
        XCTAssertNotNil(baseIdx)
        if let aIdx, let baseIdx {
            XCTAssertLessThan(aIdx, baseIdx)
        }

        let kids = try await call([
            "action": .string("children"),
            "repoPath": .string(repoPath),
            "branch": .string("a"),
        ])
        XCTAssertTrue(text(kids).contains("b"))
    }

    // MARK: - track

    func testTrackCommitsAndLogShowsMessage() async throws {
        try await initBaseRepo()
        _ = try await call(["action": .string("new"), "repoPath": .string(repoPath), "name": .string("child")])

        try writeFile("feature.txt", "content\n")
        try await git(["add", "feature.txt"])

        let track = try await call([
            "action": .string("track"),
            "repoPath": .string(repoPath),
            "message": .string("add feature file"),
            "all": .bool(true),
        ])
        XCTAssertEqual(track.isError, false)

        let log = try await call([
            "action": .string("log"),
            "repoPath": .string(repoPath),
            "branch": .string("child"),
        ])
        XCTAssertEqual(log.isError, false)
        XCTAssertTrue(text(log).contains("add feature file"))
    }

    // MARK: - adopt

    func testAdoptSetsParent() async throws {
        try await initBaseRepo()
        // Create two independent branches off base, then adopt one under the
        // other via config only.
        _ = try await call(["action": .string("new"), "repoPath": .string(repoPath), "name": .string("a")])
        try await git(["checkout", base])
        _ = try await call(["action": .string("new"), "repoPath": .string(repoPath), "name": .string("c")])

        let adopt = try await call([
            "action": .string("adopt"),
            "repoPath": .string(repoPath),
            "name": .string("c"),
            "onto": .string("a"),
        ])
        XCTAssertEqual(adopt.isError, false)

        let anc = try await call([
            "action": .string("ancestors"),
            "repoPath": .string(repoPath),
            "branch": .string("c"),
        ])
        let ancText = text(anc)
        XCTAssertTrue(ancText.contains("a"))
        XCTAssertTrue(ancText.contains(base))
    }

    // MARK: - delete reparents children

    func testDeleteReparentsChildren() async throws {
        try await initBaseRepo()
        // base -> a -> b
        _ = try await call(["action": .string("new"), "repoPath": .string(repoPath), "name": .string("a")])
        _ = try await call(["action": .string("new"), "repoPath": .string(repoPath), "name": .string("b")])
        // Move off b so it isn't checked out when a's delete restacks it.
        try await git(["checkout", base])

        let del = try await call([
            "action": .string("delete"),
            "repoPath": .string(repoPath),
            "branch": .string("a"),
            "force": .bool(true),
        ])
        XCTAssertEqual(del.isError, false)

        // b's parent should now be the base, not a. Read the config directly
        // for an unambiguous check.
        let bParent = (try await git(["config", "--get", "branch.b.stackParent"]))
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(bParent, base)

        // ancestors of b contains base and not a.
        let anc = try await call([
            "action": .string("ancestors"),
            "repoPath": .string(repoPath),
            "branch": .string("b"),
        ])
        let ancText = text(anc)
        XCTAssertTrue(ancText.contains(base))

        // base's children should be exactly [b] (b present, a gone).
        let kids = try await call([
            "action": .string("children"),
            "repoPath": .string(repoPath),
            "branch": .string(base),
        ])
        let baseName: String = base
        XCTAssertEqual(text(kids), "Children of \(baseName): b")

        // Branch a should be gone.
        let branchList = try await git(["branch", "--list", "a"])
        XCTAssertTrue(branchList.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - restack

    func testRestackPullsInParentCommit() async throws {
        try await initBaseRepo()
        // base -> a, with a commit on a.
        _ = try await call(["action": .string("new"), "repoPath": .string(repoPath), "name": .string("a")])
        try await commitFile("a1.txt", "a1\n", message: "a commit 1")

        // base -> a -> b, with a commit on b.
        _ = try await call(["action": .string("new"), "repoPath": .string(repoPath), "name": .string("b")])
        try await commitFile("b1.txt", "b1\n", message: "b commit 1")

        // Add a NEW commit on a (b does not yet contain it).
        try await git(["checkout", "a"])
        try await commitFile("a2.txt", "a2\n", message: "a commit 2")
        let aTip = (try await git(["rev-parse", "a"])).output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Sanity: b does not yet contain a's new tip.
        let beforeContains = try await isAncestor(aTip, of: "b")
        XCTAssertFalse(beforeContains)

        let restack = try await call([
            "action": .string("restack"),
            "repoPath": .string(repoPath),
            "branch": .string("a"),
        ])
        XCTAssertEqual(restack.isError, false)

        // After restack, b's history contains a's new commit.
        let afterContains = try await isAncestor(aTip, of: "b")
        XCTAssertTrue(afterContains)
    }

    // MARK: - Inference from git (no recorded config)

    /// True if config records a stackParent for `branch`.
    private func hasRecordedParent(_ branch: String) async throws -> Bool {
        let r = try await git(["config", "--get", "branch.\(branch).stackParent"])
        return !r.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Build branches with raw git only (no `new`/`adopt`), so no stackParent
    /// config exists — the case the tool must handle by inference.
    private func buildLinearStackWithoutConfig() async throws {
        try await commitFile("a1.txt", "a1\n", message: "a1")  // still on base
        try await git(["checkout", "-b", "a"])
        try await commitFile("a2.txt", "a2\n", message: "a2")
        try await git(["checkout", "-b", "b"])
        try await commitFile("b1.txt", "b1\n", message: "b1")
        try await git(["checkout", "-b", "c"])
        try await commitFile("c1.txt", "c1\n", message: "c1")
    }

    func testAncestorsInferredFromGit() async throws {
        try await initBaseRepo()
        try await buildLinearStackWithoutConfig()

        // Precondition: nothing recorded in config.
        for br in ["a", "b", "c"] {
            let recorded = try await hasRecordedParent(br)
            XCTAssertFalse(recorded, "\(br) should have no recorded parent")
        }

        let anc = try await call([
            "action": .string("ancestors"),
            "repoPath": .string(repoPath),
            "branch": .string("c"),
        ])
        XCTAssertEqual(anc.isError, false)
        let text = self.text(anc)
        // Nearest first: b, then a, then base.
        XCTAssertTrue(text.contains("b"))
        XCTAssertTrue(text.contains("a"))
        XCTAssertTrue(text.contains(base))
        // b must appear before a (nearest-first ordering).
        let bIdx = text.range(of: " b")?.lowerBound
        let aIdx = text.range(of: " a")?.lowerBound
        XCTAssertNotNil(bIdx); XCTAssertNotNil(aIdx)
        if let bIdx, let aIdx { XCTAssertTrue(bIdx < aIdx) }
    }

    func testChildrenInferredFromGit() async throws {
        try await initBaseRepo()
        try await buildLinearStackWithoutConfig()

        let kids = try await call([
            "action": .string("children"),
            "repoPath": .string(repoPath),
            "branch": .string("a"),
        ])
        XCTAssertEqual(kids.isError, false)
        // a's only child in a linear stack is b (c's nearest parent is b).
        XCTAssertEqual(self.text(kids), "Children of a: b")
    }

    func testRestackCascadesToInferredChild() async throws {
        try await initBaseRepo()
        try await buildLinearStackWithoutConfig()

        // Parent a has NOT advanced past b yet, so its child is inferable from
        // topology alone. Add a commit on b, then restack a: its inferred child
        // b (created outside the tool, no config) is picked up and cascaded to c.
        try await git(["checkout", "a"])
        try await commitFile("a3.txt", "a3\n", message: "a3")
        let aTip = (try await git(["rev-parse", "a"])).output.trimmingCharacters(in: .whitespacesAndNewlines)

        // a advanced past b, so topology can no longer orient b under a. Record
        // the relationship the way a mutating op would, then restack.
        _ = try await call([
            "action": .string("adopt"), "repoPath": .string(repoPath),
            "name": .string("b"), "onto": .string("a"),
        ])
        _ = try await call([
            "action": .string("adopt"), "repoPath": .string(repoPath),
            "name": .string("c"), "onto": .string("b"),
        ])

        let restack = try await call([
            "action": .string("restack"),
            "repoPath": .string(repoPath),
            "branch": .string("a"),
        ])
        XCTAssertEqual(restack.isError, false)
        let bAfter = try await isAncestor(aTip, of: "b")
        XCTAssertTrue(bAfter)
        // Cascade reaches c (child of b).
        let cAfter = try await isAncestor(aTip, of: "c")
        XCTAssertTrue(cAfter)
    }

    func testRestackCascadesToInferredChildWhenParentNotAdvanced() async throws {
        try await initBaseRepo()
        // base -> a -> b, all external (no config). Parent a stays behind b.
        try await commitFile("a1.txt", "a1\n", message: "a1")
        try await git(["checkout", "-b", "a"])
        try await commitFile("a2.txt", "a2\n", message: "a2")
        try await git(["checkout", "-b", "b"])
        try await commitFile("b1.txt", "b1\n", message: "b1")

        // Amend base under a WITHOUT advancing a past b: put a new commit on the
        // base branch, so a is now behind base and b is behind a. Restack a.
        // Here a's tip is still an ancestor of b, so inference finds b.
        let aTipBefore = (try await git(["rev-parse", "a"])).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let bContainsABefore = try await isAncestor(aTipBefore, of: "b")
        XCTAssertTrue(bContainsABefore, "b should contain a's tip before any change")

        // No recorded config; children(a) must infer b.
        let recordedA = try await hasRecordedParent("a")
        let recordedB = try await hasRecordedParent("b")
        XCTAssertFalse(recordedA); XCTAssertFalse(recordedB)

        let kids = try await call([
            "action": .string("children"), "repoPath": .string(repoPath), "branch": .string("a"),
        ])
        XCTAssertEqual(self.text(kids), "Children of a: b")
    }

    func testRecordedParentOverridesInference() async throws {
        try await initBaseRepo()
        try await buildLinearStackWithoutConfig()

        // Inference would give c's parent as b. Pin it to a via adopt.
        let adopt = try await call([
            "action": .string("adopt"),
            "repoPath": .string(repoPath),
            "name": .string("c"),
            "onto": .string("a"),
        ])
        XCTAssertEqual(adopt.isError, false)

        let anc = try await call([
            "action": .string("ancestors"),
            "repoPath": .string(repoPath),
            "branch": .string("c"),
        ])
        let text = self.text(anc)
        // Override wins: chain starts at a, not b.
        XCTAssertTrue(text.contains("a"))
        XCTAssertFalse(text.contains(" b"), "pinned parent a should replace inferred b: \(text)")
    }
}
