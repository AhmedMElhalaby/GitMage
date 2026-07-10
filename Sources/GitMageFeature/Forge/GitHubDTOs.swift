import Foundation

// GitHub REST v3 wire types. Decoded with `JSONDecoder.keyDecodingStrategy =
// .convertFromSnakeCase`, so property names here are camelCase and no
// explicit CodingKeys are declared (that would double-convert).

struct GHUser: Codable {
    let login: String

    func toModel() -> ForgeUser {
        ForgeUser(login: login)
    }
}

struct GHRef: Codable {
    let ref: String
}

struct GHPull: Codable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let draft: Bool?
    let user: GHUser
    let head: GHRef
    let base: GHRef
    let mergeable: Bool?
    let mergeableState: String?
    let additions: Int?
    let deletions: Int?

    func toSummary() -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            number: number,
            title: title,
            author: user.login,
            state: state,
            isDraft: draft ?? false,
            headBranch: head.ref,
            baseBranch: base.ref
        )
    }

    func toDetail() -> PullRequestDetail {
        PullRequestDetail(
            number: number,
            title: title,
            body: body ?? "",
            state: state,
            isDraft: draft ?? false,
            mergeable: mergeable,
            mergeableState: mergeableState ?? "unknown",
            additions: additions ?? 0,
            deletions: deletions ?? 0,
            headBranch: head.ref,
            baseBranch: base.ref
        )
    }
}

struct GHComment: Codable {
    let id: Int
    let user: GHUser
    let body: String
    let createdAt: String

    func toModel() -> PRComment {
        PRComment(id: id, author: user.login, body: body, createdAt: createdAt)
    }
}

struct GHFile: Codable {
    let filename: String
    let status: String
    let patch: String?

    func toModel() -> PRFile {
        PRFile(filename: filename, status: status, patch: patch)
    }
}

struct GHCheckRun: Codable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?

    func toModel() -> CheckRun {
        CheckRun(id: id, name: name, status: status, conclusion: conclusion)
    }
}

struct GHCheckRunsEnvelope: Codable {
    let checkRuns: [GHCheckRun]
}
