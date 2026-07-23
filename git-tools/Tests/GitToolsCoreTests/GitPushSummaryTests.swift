import XCTest
@testable import GitToolsCore

final class GitPushSummaryTests: XCTestCase {

    func testNewBranch() {
        let output = """
        To github.com:example/repo.git
        *\trefs/heads/fix/x:refs/heads/fix/x\t[new branch]
        Done
        """
        XCTAssertEqual(GitTool.summarizePush(output), "pushed refs/heads/fix/x")
    }

    func testForcedUpdateDropsBanner() {
        let output = """
        To github.com:example/repo.git
        +\trefs/heads/refactor/y:refs/heads/refactor/y\td6b76d3c...365c33bf (forced update)
        Done
        """
        XCTAssertEqual(GitTool.summarizePush(output), "pushed refs/heads/refactor/y")
    }

    func testMultipleRefs() {
        let output = """
        To github.com:example/repo.git
        \trefs/heads/a:refs/heads/a\t111..222
        *\trefs/heads/b:refs/heads/b\t[new branch]
        Done
        """
        XCTAssertEqual(
            GitTool.summarizePush(output),
            "pushed refs/heads/a\npushed refs/heads/b"
        )
    }

    func testUpToDateRefReadsAsUpToDate() {
        // `=` flag: ref existed remotely and moved nothing.
        let output = """
        To github.com:example/repo.git
        =\trefs/heads/a:refs/heads/a\t[up to date]
        Done
        """
        XCTAssertEqual(GitTool.summarizePush(output), "up to date refs/heads/a")
    }

    func testUpToDateFallsBackToRaw() {
        // No porcelain ref lines; "Everything up-to-date" arrives on stderr.
        XCTAssertEqual(
            GitTool.summarizePush("Everything up-to-date\n"),
            "Everything up-to-date"
        )
    }
}
