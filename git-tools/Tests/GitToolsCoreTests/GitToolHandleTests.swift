import XCTest
import MCP
@testable import GitToolsCore

final class GitToolHandleTests: XCTestCase {

    private var repoPath: String!

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

        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("git-tools-mcp-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        repoPath = base.path
    }

    override func tearDownWithError() throws {
        if let repoPath {
            try? FileManager.default.removeItem(atPath: repoPath)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func call(_ args: [String: Value]) async throws -> CallTool.Result {
        try await GitTool.handle(args)
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

    /// init + add a file + commit, returning a repo ready for further ops.
    private func initCommittedRepo() async throws {
        _ = try await call(["action": .string("init"), "repoPath": .string(repoPath)])
        try writeFile("README.md", "hello\n")
        _ = try await call([
            "action": .string("add"),
            "repoPath": .string(repoPath),
            "files": .string("README.md"),
        ])
        _ = try await call([
            "action": .string("commit"),
            "repoPath": .string(repoPath),
            "message": .string("initial"),
        ])
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
            _ = try await call(["action": .string("status")])
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

    func testAddWithoutFilesThrows() async throws {
        _ = try await call(["action": .string("init"), "repoPath": .string(repoPath)])
        do {
            _ = try await call(["action": .string("add"), "repoPath": .string(repoPath)])
            XCTFail("expected throw")
        } catch let error as MCPError {
            XCTAssertTrue("\(error)".contains("files"))
        }
    }

    // MARK: - init / status / add / commit

    func testInitCreatesRepo() async throws {
        let result = try await call(["action": .string("init"), "repoPath": .string(repoPath)])
        XCTAssertEqual(result.isError, false)
        var isDir: ObjCBool = false
        let gitDir = URL(fileURLWithPath: repoPath).appendingPathComponent(".git").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: gitDir, isDirectory: &isDir))
    }

    func testStatusUntrackedThenStaged() async throws {
        _ = try await call(["action": .string("init"), "repoPath": .string(repoPath)])
        try writeFile("a.txt", "x\n")

        let untracked = try await call(["action": .string("status"), "repoPath": .string(repoPath)])
        XCTAssertEqual(untracked.isError, false)
        XCTAssertTrue(text(untracked).contains("a.txt"))
        XCTAssertTrue(text(untracked).contains("Untracked"))

        _ = try await call([
            "action": .string("add"), "repoPath": .string(repoPath), "files": .string("a.txt"),
        ])
        let staged = try await call(["action": .string("status"), "repoPath": .string(repoPath)])
        XCTAssertTrue(text(staged).contains("Staged"))
    }

    func testCommitThenStatusClean() async throws {
        try await initCommittedRepo()
        let status = try await call(["action": .string("status"), "repoPath": .string(repoPath)])
        XCTAssertTrue(text(status).contains("clean"))
    }

    func testCommitWithoutStagedChangesIsError() async throws {
        _ = try await call(["action": .string("init"), "repoPath": .string(repoPath)])
        let result = try await call([
            "action": .string("commit"),
            "repoPath": .string(repoPath),
            "message": .string("nothing"),
        ])
        XCTAssertEqual(result.isError, true)
    }

    // MARK: - log / show

    func testLogShowsCommit() async throws {
        try await initCommittedRepo()
        let result = try await call(["action": .string("log"), "repoPath": .string(repoPath)])
        XCTAssertEqual(result.isError, false)
        XCTAssertTrue(text(result).contains("initial"))
    }

    func testShowHead() async throws {
        try await initCommittedRepo()
        let result = try await call([
            "action": .string("show"),
            "repoPath": .string(repoPath),
            "stat": .bool(true),
        ])
        XCTAssertEqual(result.isError, false)
        XCTAssertTrue(text(result).contains("README.md"))
    }

    // MARK: - diff

    func testDiffUnstagedChange() async throws {
        try await initCommittedRepo()
        try writeFile("README.md", "hello world\n")
        let result = try await call(["action": .string("diff"), "repoPath": .string(repoPath)])
        XCTAssertEqual(result.isError, false)
        XCTAssertTrue(text(result).contains("README.md"))
    }

    // MARK: - branch management

    func testBranchCreateInfoRenameDelete() async throws {
        try await initCommittedRepo()

        let create = try await call([
            "action": .string("branch_create"),
            "repoPath": .string(repoPath),
            "name": .string("feature"),
        ])
        XCTAssertEqual(create.isError, false)

        let info = try await call(["action": .string("branch_info"), "repoPath": .string(repoPath)])
        XCTAssertTrue(text(info).contains("feature"))

        let rename = try await call([
            "action": .string("branch_rename"),
            "repoPath": .string(repoPath),
            "oldName": .string("feature"),
            "newName": .string("feature2"),
        ])
        XCTAssertEqual(rename.isError, false)

        let delete = try await call([
            "action": .string("branch_delete"),
            "repoPath": .string(repoPath),
            "name": .string("feature2"),
            "force": .bool(true),
        ])
        XCTAssertEqual(delete.isError, false)
    }

    // MARK: - tag / remote / worktree list

    func testTagCreateAndList() async throws {
        try await initCommittedRepo()
        let create = try await call([
            "action": .string("tag"),
            "repoPath": .string(repoPath),
            "name": .string("v1"),
        ])
        XCTAssertEqual(create.isError, false)

        let list = try await call([
            "action": .string("tag"),
            "repoPath": .string(repoPath),
            "list": .bool(true),
        ])
        XCTAssertTrue(text(list).contains("v1"))
    }

    func testRemoteEmpty() async throws {
        try await initCommittedRepo()
        let result = try await call(["action": .string("remote"), "repoPath": .string(repoPath)])
        XCTAssertEqual(result.isError, false)
        XCTAssertTrue(text(result).contains("No remotes"))
    }

    func testWorktreeList() async throws {
        try await initCommittedRepo()
        let result = try await call(["action": .string("worktree_list"), "repoPath": .string(repoPath)])
        XCTAssertEqual(result.isError, false)
        XCTAssertTrue(text(result).contains(repoPath))
    }

    func testWorktreeFindByBranchName() async throws {
        try await initCommittedRepo()
        let worktreePath = repoPath + "-feature"
        _ = try await call([
            "action": .string("worktree_add"),
            "repoPath": .string(repoPath),
            "worktreePath": .string(worktreePath),
            "branch": .string("feature"),
            "createBranch": .bool(true),
        ])

        // git canonicalizes the worktree path (e.g. /var -> /private/var on macOS),
        // so match the trailing component rather than the literal we passed in.
        let found = try await call([
            "action": .string("worktree_find_by_branch_name"),
            "repoPath": .string(repoPath),
            "branch": .string("feature"),
        ])
        XCTAssertEqual(found.isError, false)
        XCTAssertTrue(text(found).hasSuffix("-feature"))

        // Fully-qualified ref resolves to the same worktree.
        let qualified = try await call([
            "action": .string("worktree_find_by_branch_name"),
            "repoPath": .string(repoPath),
            "branch": .string("refs/heads/feature"),
        ])
        XCTAssertEqual(text(qualified), text(found))
    }

    func testWorktreeFindByBranchNameNotFound() async throws {
        try await initCommittedRepo()
        let result = try await call([
            "action": .string("worktree_find_by_branch_name"),
            "repoPath": .string(repoPath),
            "branch": .string("nonexistent"),
        ])
        XCTAssertEqual(result.isError, false)
        XCTAssertTrue(text(result).contains("No worktree found"))
    }
}
