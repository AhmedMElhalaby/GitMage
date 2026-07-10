import Foundation

enum GitRepositoryError: Error, LocalizedError, Equatable {
    case missingPath
    case pathDoesNotExist(String)
    case notARepository(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingPath:
            return "Select a repository path first."
        case .pathDoesNotExist(let path):
            return "Path does not exist: \(path)"
        case .notARepository(let path):
            return "Not a git repository: \(path)"
        case .commandFailed(let message):
            return message
        }
    }
}

actor GitRepositoryClient {
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

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws -> String {
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

        guard process.terminationStatus == 0 else {
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
            return GitChange(id: "\(statusCode):\(remainder)", path: remainder, statusCode: statusCode, kind: .ignored)
        }

        let displayPath: String
        let kind: GitChangeKind

        if let renameRange = remainder.range(of: " -> ") {
            let oldPath = String(remainder[..<renameRange.lowerBound])
            let newPath = String(remainder[renameRange.upperBound...])
            displayPath = "\(oldPath) → \(newPath)"
            kind = .renamed
        } else {
            displayPath = remainder
            kind = kindForStatus(statusCode)
        }

        return GitChange(id: "\(statusCode):\(displayPath)", path: displayPath, statusCode: statusCode, kind: kind)
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
