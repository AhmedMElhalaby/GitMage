import XCTest
@testable import GitMageFeature

final class GitRepositoryClientTests: XCTestCase {
    func testStagesAndCommitsRepositoryChanges() async throws {
        let repoURL = try makeTemporaryRepository()
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let client = GitRepositoryClient()

        try await client.stageAllChanges(in: repoURL.path)
        try await client.commit(message: "Add README", in: repoURL.path)

        let snapshot = try await client.loadSnapshot(at: repoURL.path)
        XCTAssertEqual(snapshot.lastCommitSummary, "Add README")
        XCTAssertTrue(snapshot.changes.isEmpty)
    }

    func testRejectsEmptyCommitMessage() async throws {
        let repoURL = try makeTemporaryRepository()
        let client = GitRepositoryClient()

        do {
            try await client.commit(message: "   ", in: repoURL.path)
            XCTFail("Expected empty commit message to fail")
        } catch let error as GitRepositoryError {
            XCTAssertEqual(error, .invalidCommitMessage)
        }
    }

    private func makeTemporaryRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try runGit(["init"], in: root)
        try runGit(["config", "user.email", "gitmage@example.com"], in: root)
        try runGit(["config", "user.name", "Git Mage"], in: root)
        return root
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path] + arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "GitRepositoryClientTests", code: Int(process.terminationStatus))
        }
    }
}
