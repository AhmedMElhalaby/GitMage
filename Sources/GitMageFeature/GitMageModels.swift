import Foundation

struct GitMageWorkspaceState: Codable, Equatable {
    var repositoryPath: String
    var draftCommitMessage: String

    init(repositoryPath: String = "", draftCommitMessage: String = "") {
        self.repositoryPath = repositoryPath
        self.draftCommitMessage = draftCommitMessage
    }
}

struct GitRepositorySnapshot: Equatable {
    let rootPath: String
    let branchName: String
    let upstream: String?
    let aheadCount: Int
    let behindCount: Int
    let lastCommitSummary: String?
    let changes: [GitChange]

    var isDirty: Bool { !changes.isEmpty }

    var headline: String {
        if let lastCommitSummary, !lastCommitSummary.isEmpty {
            return lastCommitSummary
        }
        return "No commits yet"
    }

    var statusSummary: String {
        guard !changes.isEmpty else { return "Clean" }
        let changeCount = changes.count
        let stagedCount = changes.filter(\.isStaged).count
        let untrackedCount = changes.filter(\.isUntracked).count
        let pieces = [
            "\(changeCount) changed",
            stagedCount > 0 ? "\(stagedCount) staged" : nil,
            untrackedCount > 0 ? "\(untrackedCount) untracked" : nil
        ].compactMap { $0 }
        return pieces.joined(separator: " · ")
    }
}

struct GitBranchSummary: Identifiable, Equatable {
    let name: String
    let upstream: String?
    let isCurrent: Bool
    let tracking: String?

    var id: String { name }

    var subtitle: String {
        if let tracking, !tracking.isEmpty {
            return tracking
        }
        if let upstream, !upstream.isEmpty {
            return upstream
        }
        return isCurrent ? "current branch" : "local branch"
    }
}

struct GitDiffSnapshot: Equatable {
    let title: String
    let body: String
    let isEmpty: Bool
}

struct GitChange: Identifiable, Equatable {
    let id: String
    let path: String
    let filePath: String
    let sourcePath: String?
    let statusCode: String
    let kind: GitChangeKind

    var isStaged: Bool { kind.isStaged }
    var isUntracked: Bool { kind == .untracked }
}

enum GitChangeKind: Equatable {
    case staged
    case modified
    case untracked
    case renamed
    case deleted
    case conflicted
    case ignored

    var label: String {
        switch self {
        case .staged: return "Staged"
        case .modified: return "Modified"
        case .untracked: return "Untracked"
        case .renamed: return "Renamed"
        case .deleted: return "Deleted"
        case .conflicted: return "Conflict"
        case .ignored: return "Ignored"
        }
    }

    var isStaged: Bool {
        self == .staged || self == .renamed || self == .deleted
    }
}
