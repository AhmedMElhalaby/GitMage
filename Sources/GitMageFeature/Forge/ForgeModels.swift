import Foundation

/// Identifies a forge (e.g. GitHub) repository by host/owner/name, parsed from
/// a git remote URL. Used to gate forge-backed features (like Pull Requests)
/// to repositories with a recognized origin remote.
struct RepoRef: Equatable {
    let host: String
    let owner: String
    let name: String
}

enum PRState: String, Codable {
    case open
    case closed
    case all
}

enum ReviewEvent: String {
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"
    case comment = "COMMENT"
}

enum MergeMethod: String, CaseIterable {
    case merge
    case squash
    case rebase
}

struct ForgeUser: Equatable {
    let login: String
}

struct PullRequestSummary: Identifiable, Equatable {
    let id: Int
    let number: Int
    let title: String
    let author: String
    let state: String
    let isDraft: Bool
    let headBranch: String
    let baseBranch: String
}

struct PullRequestDetail: Equatable {
    let number: Int
    let title: String
    let body: String
    let state: String
    let isDraft: Bool
    let mergeable: Bool?
    let mergeableState: String
    let additions: Int
    let deletions: Int
    let headBranch: String
    let baseBranch: String
}

struct ForgeComment: Identifiable, Equatable {
    let id: Int
    let author: String
    let body: String
    let createdAt: String
}

struct PRFile: Identifiable, Equatable {
    var id: String { filename }
    let filename: String
    let status: String
    let patch: String?
}

struct CheckRun: Identifiable, Equatable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
}

enum IssueState: String, Codable {
    case open
    case closed
    case all
}

struct IssueLabel: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let color: String
}

struct IssueSummary: Identifiable, Equatable {
    let id: Int
    let number: Int
    let title: String
    let author: String
    let state: String
    let labelNames: [String]
    let commentCount: Int
}

struct IssueDetail: Equatable {
    let number: Int
    let title: String
    let body: String
    let state: String
    let author: String
    let labels: [IssueLabel]
    let assignees: [String]
}
