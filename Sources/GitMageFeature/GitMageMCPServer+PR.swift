import Foundation

/// The pull-request half of Git Mage's MCP surface.
///
/// The host shipped a `pr_op` tool that called a `gitmage.pr_op` action **no
/// Git Mage build ever registered**, so every PR call the assistant ever made
/// failed. These tools are the first working implementation, and they go to the
/// same `GitForgeProvider` the Pull Requests UI drives — one GitHub client, not
/// two.
///
/// Only what the provider genuinely implements is published. A tool advertised
/// to the model that always fails is worse than an absent one; that was the
/// `pr_op` bug.
///
/// ## Destructive classification
///
/// `destructive` is the host's Full-auto gate, so the question is not "is this
/// visible to other people" but "can the result be undone through the API".
///
/// - `pr_merge` — **true.** `merge` rewrites the base branch. Undoing it means a
///   revert commit or a force-push; the merged history is not recoverable
///   through the forge.
/// - `pr_close` — **true.** Closing forecloses the review: CI stops, reviewers
///   are dismissed, and the branch may be auto-deleted. It also destroys nothing
///   the model owns, so it is the weaker of the two — but it terminates work in
///   progress, which is exactly what a human should confirm.
/// - `pr_create` — **false.** `createPullRequest` is purely additive: it
///   overwrites no existing state, and a wrong PR is fully remediable by closing
///   it. It is also the single most common thing the assistant is asked to do,
///   so gating it behind an approval prompt would make Full-auto useless for
///   ordinary work while protecting nothing that is actually at risk. (This
///   matches the host's own `GitPrTool.prOperations`, which listed only
///   `mergePR`.)
/// - `pr_comment` / `pr_review` — **false**, same reasoning: a POST that appends
///   a comment or a review. Nothing is overwritten and the author can delete it.
///   A review is the closer call, since an `approve` can trip branch-protection
///   auto-merge — but the merge itself is what the gate should stop, and
///   `pr_merge` already carries the flag.
/// - Listing, viewing and check status are `readOnly` and plainly not
///   destructive.
///
/// The host additionally applies `isIrreversible = destructiveHint ||
/// hasOptionLookingValue(arguments)` on top of these, so argument-shaped
/// escapes are already covered upstream; these flags are the honest static
/// classification only.
@MainActor
extension GitMageMCPServer {
    static let prTools: [Tool] = [
        Tool("pr_list", "listPRs", "List the repository's pull requests.",
             route: .pullRequest, readOnly: true,
             argsHint: "{\"state\": \"open\"|\"closed\"|\"all\"} (default \"open\")"),
        Tool("pr_view", "viewPR",
             "Read a pull request: description, commits, changed files and comments.",
             route: .pullRequest, readOnly: true,
             argsHint: "{\"number\": number} (required)"),
        Tool("pr_checks", "ciStatus", "Report the CI check runs for a pull request's head branch.",
             route: .pullRequest, readOnly: true,
             argsHint: "{\"number\": number} (required)"),
        Tool("pr_create", "createPR", "Open a pull request.",
             route: .pullRequest,
             argsHint: "{\"title\": string (required), \"head\": string (required), "
             + "\"base\": string (required), \"body\": string, \"draft\": bool}"),
        Tool("pr_comment", "commentPR", "Post a comment on a pull request.",
             route: .pullRequest,
             argsHint: "{\"number\": number (required), \"body\": string (required)}"),
        Tool("pr_review", "reviewPR", "Submit a review on a pull request.",
             route: .pullRequest,
             argsHint: "{\"number\": number (required), "
             + "\"event\": \"approve\"|\"requestChanges\"|\"comment\" (required), \"body\": string}"),
        Tool("pr_merge", "mergePR", "Merge a pull request. This rewrites the base branch.",
             route: .pullRequest, destructive: true,
             argsHint: "{\"number\": number (required), "
             + "\"method\": \"merge\"|\"squash\"|\"rebase\" (default \"merge\")}"),
        Tool("pr_close", "closePR", "Close a pull request without merging it.",
             route: .pullRequest, destructive: true,
             argsHint: "{\"number\": number} (required)"),
    ]
}
