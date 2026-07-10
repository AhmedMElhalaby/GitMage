import Foundation

enum GitRepositoryError: Error, LocalizedError, Equatable {
    case missingPath
    case pathDoesNotExist(String)
    case notARepository(String)
    case invalidCommitMessage
    case invalidBranchName
    case invalidRemoteURL
    case nothingToCommit
    case detachedHead
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingPath:
            return "Select a repository path first."
        case .pathDoesNotExist(let path):
            return "Path does not exist: \(path)"
        case .notARepository(let path):
            return "Not a git repository: \(path)"
        case .invalidCommitMessage:
            return "Enter a non-empty commit message."
        case .invalidBranchName:
            return "Enter a non-empty branch name."
        case .invalidRemoteURL:
            return "Enter a repository URL to clone."
        case .nothingToCommit:
            return "There are no staged changes to commit."
        case .detachedHead:
            return "You are not on a branch (detached HEAD). Check out a branch first."
        case .commandFailed(let message):
            return message
        }
    }
}

actor GitRepositoryClient {
    /// Cache of picked path → resolved repository root, so routine actions don't
    /// re-run `rev-parse --show-toplevel` on every call.
    private var rootCache: [String: String] = [:]

    func isRepository(at path: String) -> Bool {
        (try? validateRepositoryPath(path)) != nil
    }

    func loadSnapshot(at path: String) throws -> GitRepositorySnapshot {
        let repositoryURL = try validateRepositoryPath(path)
        let rootPath = try runGit(["rev-parse", "--show-toplevel"], in: repositoryURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let statusOutput = try runGit(["status", "--short", "--branch"], in: URL(fileURLWithPath: rootPath))
        let lastCommitSummary = try? runGit(["log", "-1", "--pretty=format:%s"], in: URL(fileURLWithPath: rootPath)).trimmingCharacters(in: .whitespacesAndNewlines)
        return GitStatusParser.parse(
            statusOutput: statusOutput,
            repositoryRoot: rootPath,
            lastCommitSummary: lastCommitSummary?.isEmpty == true ? nil : lastCommitSummary
        )
    }

    func loadBranches(at path: String) throws -> [GitBranchSummary] {
        let repositoryURL = try validateRepositoryPath(path)
        let rootPath = try runGit(["rev-parse", "--show-toplevel"], in: repositoryURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let output = try runGit([
            "for-each-ref",
            "--format=%(HEAD)\t%(refname:short)\t%(upstream:short)\t%(upstream:trackshort)",
            "refs/heads"
        ], in: URL(fileURLWithPath: rootPath))
        return GitBranchParser.parse(output: output)
    }

    func checkoutBranch(_ branchName: String, in path: String) throws {
        let repositoryURL = try validateRepositoryPath(path)
        let rootPath = try runGit(["rev-parse", "--show-toplevel"], in: repositoryURL).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try runGit(["checkout", branchName], in: URL(fileURLWithPath: rootPath))
    }

    func stageAllChanges(in path: String) throws {
        let rootURL = try repositoryRootURL(for: path)
        _ = try runGit(["add", "-A"], in: rootURL)
    }

    func stage(change: GitChange, in path: String) throws {
        let rootURL = try repositoryRootURL(for: path)
        if change.kind == .renamed, let sourcePath = change.sourcePath {
            _ = try runGit(["add", sourcePath, change.filePath], in: rootURL)
        } else {
            _ = try runGit(["add", change.filePath], in: rootURL)
        }
    }

    func unstage(change: GitChange, in path: String) throws {
        let rootURL = try repositoryRootURL(for: path)
        guard change.canUnstage else { return }
        if try !hasHead(in: rootURL) {
            if change.kind == .renamed, let sourcePath = change.sourcePath {
                _ = try runGit(["rm", "--cached", "--", sourcePath, change.filePath], in: rootURL)
            } else {
                _ = try runGit(["rm", "--cached", "--", change.filePath], in: rootURL)
            }
            return
        }

        if change.kind == .renamed, let sourcePath = change.sourcePath {
            _ = try runGit(["restore", "--staged", "--", sourcePath, change.filePath], in: rootURL)
        } else {
            _ = try runGit(["restore", "--staged", "--", change.filePath], in: rootURL)
        }
    }

    func discard(change: GitChange, in path: String) throws {
        let rootURL = try repositoryRootURL(for: path)
        switch change.kind {
        case .untracked:
            _ = try runGit(["clean", "-f", "--", change.filePath], in: rootURL)
        case .renamed:
            if let sourcePath = change.sourcePath {
                _ = try runGit(["restore", "--source=HEAD", "--worktree", "--staged", "--", sourcePath, change.filePath], in: rootURL)
            } else {
                _ = try runGit(["restore", "--source=HEAD", "--worktree", "--staged", "--", change.filePath], in: rootURL)
            }
        default:
            _ = try runGit(["restore", "--source=HEAD", "--worktree", "--staged", "--", change.filePath], in: rootURL)
        }
    }

    func commit(message: String, in path: String) throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitRepositoryError.invalidCommitMessage }

        let rootURL = try repositoryRootURL(for: path)
        let staged = try runGit(["diff", "--cached", "--name-only"], in: rootURL)
        guard !staged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitRepositoryError.nothingToCommit
        }
        _ = try runGit(["commit", "-m", trimmed], in: rootURL)
    }

    func createBranch(_ name: String, in path: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitRepositoryError.invalidBranchName }
        let rootURL = try repositoryRootURL(for: path)
        _ = try runGit(["checkout", "-b", trimmed], in: rootURL)
    }

    func fetch(in path: String) throws {
        let rootURL = try repositoryRootURL(for: path)
        _ = try runGit(["fetch", "--all", "--prune"], in: rootURL)
    }

    /// Fast-forward-only pull. Surfaces git's error when the branch has diverged.
    func pull(in path: String) throws {
        let rootURL = try repositoryRootURL(for: path)
        _ = try runGit(["pull", "--ff-only"], in: rootURL)
    }

    /// Pushes the current branch, setting `origin/<branch>` as upstream when none exists.
    func push(in path: String) throws {
        let rootURL = try repositoryRootURL(for: path)
        let branch = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: rootURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard branch != "HEAD", !branch.isEmpty else { throw GitRepositoryError.detachedHead }

        let hasUpstream = (try? runGit(
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
            in: rootURL
        )) != nil

        if hasUpstream {
            _ = try runGit(["push"], in: rootURL)
        } else {
            _ = try runGit(["push", "-u", "origin", branch], in: rootURL)
        }
    }

    func stashPush(in path: String) throws {
        let rootURL = try repositoryRootURL(for: path)
        _ = try runGit(["stash", "push", "--include-untracked"], in: rootURL)
    }

    func stashPop(in path: String) throws {
        let rootURL = try repositoryRootURL(for: path)
        _ = try runGit(["stash", "pop"], in: rootURL)
    }

    func stashApply(_ entry: GitStashEntry, in path: String) throws {
        let rootURL = try repositoryRootURL(for: path)
        _ = try runGit(["stash", "apply", entry.id], in: rootURL)
    }

    func stashDrop(_ entry: GitStashEntry, in path: String) throws {
        let rootURL = try repositoryRootURL(for: path)
        _ = try runGit(["stash", "drop", entry.id], in: rootURL)
    }

    func loadStashes(in path: String) throws -> [GitStashEntry] {
        let rootURL = try repositoryRootURL(for: path)
        let output = try runGit(["stash", "list", "--format=%gd%x09%gs"], in: rootURL)
        return GitStashParser.parse(output: output)
    }

    /// Initializes a plain directory as a new git repository.
    func initRepository(at path: String) throws {
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw GitRepositoryError.pathDoesNotExist(path)
        }
        _ = try runGit(["init"], in: URL(fileURLWithPath: expanded, isDirectory: true))
        rootCache[path] = nil
    }

    /// Clones `remoteURL` into `parentDirectory` and returns the new repository path.
    func clone(remoteURL: String, into parentDirectory: String) throws -> String {
        let trimmedURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { throw GitRepositoryError.invalidRemoteURL }

        let parentExpanded = (parentDirectory as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parentExpanded, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw GitRepositoryError.pathDoesNotExist(parentDirectory)
        }

        let parentURL = URL(fileURLWithPath: parentExpanded, isDirectory: true)
        let destinationURL = parentURL.appendingPathComponent(
            GitRepositoryClient.repositoryName(fromRemote: trimmedURL),
            isDirectory: true
        )
        _ = try runGit(["clone", trimmedURL, destinationURL.path], in: parentURL)
        return destinationURL.path
    }

    static func repositoryName(fromRemote remote: String) -> String {
        var trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") { trimmed = String(trimmed.dropLast()) }
        if trimmed.hasSuffix(".git") { trimmed = String(trimmed.dropLast(4)) }
        let separators = CharacterSet(charactersIn: "/:")
        let components = trimmed.components(separatedBy: separators).filter { !$0.isEmpty }
        return components.last ?? "repository"
    }

    func loadDiff(for change: GitChange, in path: String) throws -> GitDiffSnapshot {
        let repositoryURL = try validateRepositoryPath(path)
        let rootPath = try runGit(["rev-parse", "--show-toplevel"], in: repositoryURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let rootURL = URL(fileURLWithPath: rootPath)
        let title = change.kind == .renamed ? "\(change.sourcePath ?? change.path) → \(change.filePath)" : change.filePath

        let arguments: [String]
        switch change.kind {
        case .untracked:
            arguments = ["diff", "--no-index", "--", "/dev/null", change.filePath]
        case .renamed:
            let pathspecs = change.sourcePath.map { [$0, change.filePath] } ?? [change.filePath]
            arguments = change.isIndexStaged
                ? ["diff", "--cached", "--no-ext-diff", "--unified=3", "--"] + pathspecs
                : ["diff", "--no-ext-diff", "--unified=3", "--"] + pathspecs
        case .deleted:
            arguments = change.isIndexStaged
                ? ["diff", "--cached", "--no-ext-diff", "--unified=3", "--", change.filePath]
                : ["diff", "--no-ext-diff", "--unified=3", "--", change.filePath]
        default:
            arguments = change.isIndexStaged
                ? ["diff", "--cached", "--no-ext-diff", "--unified=3", "--", change.filePath]
                : ["diff", "--no-ext-diff", "--unified=3", "--", change.filePath]
        }

        let output = try runGit(
            arguments,
            in: rootURL,
            acceptedExitCodes: change.kind == .untracked ? [0, 1] : [0]
        )

        let body = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitDiffSnapshot(
            title: title,
            body: body.isEmpty ? "No diff available." : body,
            isEmpty: body.isEmpty
        )
    }

    private func validateRepositoryPath(_ path: String) throws -> URL {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitRepositoryError.missingPath
        }

        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) else {
            throw GitRepositoryError.pathDoesNotExist(path)
        }

        let url = URL(fileURLWithPath: expanded, isDirectory: isDirectory.boolValue)
        do {
            _ = try runGit(["rev-parse", "--show-toplevel"], in: url)
            return url
        } catch {
            throw GitRepositoryError.notARepository(path)
        }
    }

    private func repositoryRootURL(for path: String) throws -> URL {
        if let cached = rootCache[path] {
            return URL(fileURLWithPath: cached)
        }
        let repositoryURL = try validateRepositoryPath(path)
        let rootPath = try runGit(["rev-parse", "--show-toplevel"], in: repositoryURL).trimmingCharacters(in: .whitespacesAndNewlines)
        rootCache[path] = rootPath
        return URL(fileURLWithPath: rootPath)
    }

    private func hasHead(in repositoryURL: URL) throws -> Bool {
        do {
            _ = try runGit(["rev-parse", "--verify", "HEAD"], in: repositoryURL)
            return true
        } catch {
            return false
        }
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL, acceptedExitCodes: Set<Int32> = [0]) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repositoryURL.path] + arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw GitRepositoryError.commandFailed("Unable to launch git: \(error.localizedDescription)")
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outData, as: UTF8.self)
        let errorOutput = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        guard acceptedExitCodes.contains(process.terminationStatus) else {
            throw GitRepositoryError.commandFailed(errorOutput.isEmpty ? "git \(arguments.joined(separator: " ")) failed" : errorOutput)
        }

        return output
    }
}

enum GitStatusParser {
    static func parse(statusOutput: String, repositoryRoot: String, lastCommitSummary: String?) -> GitRepositorySnapshot {
        let lines = statusOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let header = lines.first ?? ""
        let branchInfo = parseHeader(header)
        let changes = lines.dropFirst().compactMap(parseChangeLine)
        return GitRepositorySnapshot(
            rootPath: repositoryRoot,
            branchName: branchInfo.branchName,
            upstream: branchInfo.upstream,
            aheadCount: branchInfo.aheadCount,
            behindCount: branchInfo.behindCount,
            lastCommitSummary: lastCommitSummary,
            changes: changes
        )
    }

    private static func parseHeader(_ header: String) -> (branchName: String, upstream: String?, aheadCount: Int, behindCount: Int) {
        guard header.hasPrefix("## ") else {
            return ("detached HEAD", nil, 0, 0)
        }

        let content = String(header.dropFirst(3))
        let branchAndState = content.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let branchPart = String(branchAndState.first ?? "")
        let statePart = branchAndState.count > 1 ? String(branchAndState[1]) : ""

        var branchName = branchPart
        var upstream: String?
        if let ellipsis = branchPart.range(of: "...") {
            branchName = String(branchPart[..<ellipsis.lowerBound])
            upstream = String(branchPart[ellipsis.upperBound...])
        }

        var aheadCount = 0
        var behindCount = 0
        if statePart.contains("ahead") {
            aheadCount = parseCount(statePart, token: "ahead")
        }
        if statePart.contains("behind") {
            behindCount = parseCount(statePart, token: "behind")
        }

        if content.contains("No commits yet on ") {
            branchName = content.replacingOccurrences(of: "No commits yet on ", with: "")
            upstream = nil
        }

        return (branchName, upstream, aheadCount, behindCount)
    }

    private static func parseCount(_ state: String, token: String) -> Int {
        let needle = "\(token) "
        guard let range = state.range(of: needle) else { return 0 }
        let suffix = state[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    private static func parseChangeLine(_ line: String) -> GitChange? {
        guard line.count >= 3 else { return nil }
        let statusCode = String(line.prefix(2))
        let remainder = String(line.dropFirst(3))
        if statusCode == "!!" {
            return GitChange(
                id: "\(statusCode):\(remainder)",
                path: remainder,
                filePath: remainder,
                sourcePath: nil,
                statusCode: statusCode,
                kind: .ignored
            )
        }

        let displayPath: String
        let filePath: String
        let sourcePath: String?
        let kind: GitChangeKind

        if let renameRange = remainder.range(of: " -> ") {
            let oldPath = String(remainder[..<renameRange.lowerBound])
            let newPath = String(remainder[renameRange.upperBound...])
            displayPath = "\(oldPath) → \(newPath)"
            filePath = newPath
            sourcePath = oldPath
            kind = .renamed
        } else {
            displayPath = remainder
            filePath = remainder
            sourcePath = nil
            kind = kindForStatus(statusCode)
        }

        return GitChange(
            id: "\(statusCode):\(displayPath)",
            path: displayPath,
            filePath: filePath,
            sourcePath: sourcePath,
            statusCode: statusCode,
            kind: kind
        )
    }

    private static func kindForStatus(_ statusCode: String) -> GitChangeKind {
        let characters = Array(statusCode)
        let index0 = characters.first ?? " "
        let index1 = characters.dropFirst().first ?? " "

        if statusCode == "??" { return .untracked }
        if index0 == "U" || index1 == "U" { return .conflicted }
        if index0 == "D" || index1 == "D" { return .deleted }
        if index0 != " " && index1 == " " { return .staged }
        if index0 == " " && index1 != " " { return .modified }
        return index0 != " " ? .staged : .modified
    }
}

enum GitBranchParser {
    static func parse(output: String) -> [GitBranchSummary] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .compactMap(parseLine)
            .sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent && !rhs.isCurrent }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private static func parseLine(_ line: String) -> GitBranchSummary? {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4 else { return nil }
        let isCurrent = parts[0] == "*"
        let name = parts[1]
        let upstream = parts[2].isEmpty ? nil : parts[2]
        let tracking = parts[3].isEmpty ? nil : parts[3]
        return GitBranchSummary(name: name, upstream: upstream, isCurrent: isCurrent, tracking: tracking)
    }
}

enum GitStashParser {
    static func parse(output: String) -> [GitStashEntry] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .enumerated()
            .compactMap { index, line in
                let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                guard let ref = parts.first, !ref.isEmpty else { return nil }
                let message = parts.count > 1 ? parts[1] : ref
                return GitStashEntry(id: ref, index: index, message: message)
            }
    }
}
