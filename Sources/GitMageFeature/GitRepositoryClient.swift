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

    func loadLog(limit: Int, in path: String) throws -> [GitCommitSummary] {
        let rootURL = try repositoryRootURL(for: path)
        guard try hasHead(in: rootURL) else { return [] }
        let output = try runGit([
            "log",
            "--max-count=\(max(1, limit))",
            "--pretty=format:%H%x09%h%x09%s%x09%an%x09%ar"
        ], in: rootURL)
        return GitLogParser.parse(output: output)
    }

    func remoteInfo(in path: String) throws -> RepoRef? {
        let rootURL = try repositoryRootURL(for: path)
        let url = (try? runGit(["remote", "get-url", "origin"], in: rootURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url, !url.isEmpty else { return nil }
        return RemoteInfoParser.parse(remoteURL: url)
    }

    func loadCommitDiff(sha: String, in path: String) throws -> GitDiffSnapshot {
        let rootURL = try repositoryRootURL(for: path)
        let output = try runGit(
            ["show", "--no-color", "--no-ext-diff", "--unified=3", "--format=medium", sha],
            in: rootURL
        )
        let body = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitDiffSnapshot(
            title: sha,
            body: body.isEmpty ? "No diff available." : body,
            isEmpty: body.isEmpty
        )
    }

    func deleteBranch(_ name: String, in path: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitRepositoryError.invalidBranchName }
        let rootURL = try repositoryRootURL(for: path)
        _ = try runGit(["branch", "-d", trimmed], in: rootURL)   // safe delete; refuses unmerged
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
