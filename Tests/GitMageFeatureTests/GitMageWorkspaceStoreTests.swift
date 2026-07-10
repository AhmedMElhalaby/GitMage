import XCTest
import AinkradAppKit
@testable import GitMageFeature

final class GitMageWorkspaceStoreTests: XCTestCase {
    func testRoundTripsWorkspaceState() {
        let documents = MemoryDocumentStore()
        let store = GitMageWorkspaceStore(documents: documents)
        let state = GitMageWorkspaceState(repositoryPath: "/tmp/repo", draftCommitMessage: "WIP")

        store.save(state)

        XCTAssertEqual(store.load(), state)
    }

    func testRoundTripsLibraryState() {
        let documents = MemoryDocumentStore()
        let store = GitMageWorkspaceStore(documents: documents)
        let repo = GitMageRepoConfig(id: "abc", path: "/tmp/repo", name: "repo", draftCommitMessage: "WIP", lastBranch: "main")
        let library = GitMageLibraryState(repos: [repo], activeRepoID: "abc")

        store.saveLibrary(library)

        XCTAssertEqual(store.loadLibrary(), library)
    }

    func testMigratesLegacyWorkspaceIntoLibrary() {
        let documents = MemoryDocumentStore()
        let store = GitMageWorkspaceStore(documents: documents)
        store.save(GitMageWorkspaceState(repositoryPath: "/tmp/legacy-repo", draftCommitMessage: "carry over"))

        let library = store.loadLibrary()

        XCTAssertEqual(library.repos.count, 1)
        let repo = try? XCTUnwrap(library.repos.first)
        XCTAssertEqual(repo?.path, "/tmp/legacy-repo")
        XCTAssertEqual(repo?.name, "legacy-repo")
        XCTAssertEqual(repo?.draftCommitMessage, "carry over")
        XCTAssertEqual(library.activeRepoID, repo?.id)

        // Migration is persisted, so a second load returns the same library.
        XCTAssertEqual(store.loadLibrary(), library)
    }

    func testReturnsEmptyLibraryWithoutLegacyState() {
        let store = GitMageWorkspaceStore(documents: MemoryDocumentStore())
        XCTAssertEqual(store.loadLibrary(), GitMageLibraryState())
    }
}

private final class MemoryDocumentStore: PluginDocumentStore {
    private var storage: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        storage[key]
    }

    func setData(_ data: Data?, forKey key: String) {
        storage[key] = data
    }
}

