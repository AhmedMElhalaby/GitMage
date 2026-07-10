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

