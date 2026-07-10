import XCTest
@testable import GitMageFeature

final class GitStatusParserTests: XCTestCase {
    func testParsesBranchAndChanges() {
        let output = """
        ## main...origin/main [ahead 2, behind 1]
         M Sources/App.swift
        ?? Notes/todo.md
        R  Old.swift -> New.swift
        """

        let snapshot = GitStatusParser.parse(
            statusOutput: output,
            repositoryRoot: "/tmp/repo",
            lastCommitSummary: "Refine repo inspector"
        )

        XCTAssertEqual(snapshot.branchName, "main")
        XCTAssertEqual(snapshot.upstream, "origin/main")
        XCTAssertEqual(snapshot.aheadCount, 2)
        XCTAssertEqual(snapshot.behindCount, 1)
        XCTAssertEqual(snapshot.lastCommitSummary, "Refine repo inspector")
        XCTAssertEqual(snapshot.changes.count, 3)
        XCTAssertEqual(snapshot.changes[0].kind, .modified)
        XCTAssertEqual(snapshot.changes[1].kind, .untracked)
        XCTAssertEqual(snapshot.changes[2].kind, .renamed)
    }

    func testParsesNoCommitsHeader() {
        let snapshot = GitStatusParser.parse(
            statusOutput: "## No commits yet on develop\n?? README.md",
            repositoryRoot: "/tmp/repo",
            lastCommitSummary: nil
        )

        XCTAssertEqual(snapshot.branchName, "develop")
        XCTAssertNil(snapshot.upstream)
        XCTAssertEqual(snapshot.changes.first?.kind, .untracked)
    }
}

