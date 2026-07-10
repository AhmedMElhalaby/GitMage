import Foundation

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

enum GitLogParser {
    static func parse(output: String) -> [GitCommitSummary] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 5 else { return nil }
                return GitCommitSummary(
                    id: parts[0],
                    shortSHA: parts[1],
                    summary: parts[2],
                    author: parts[3],
                    relativeDate: parts[4]
                )
            }
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
