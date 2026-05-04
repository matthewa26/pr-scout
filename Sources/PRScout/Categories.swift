import Foundation

enum CategoryKind: String, Codable, CaseIterable {
    /// Author = me, reviewDecision = CHANGES_REQUESTED.
    case changesRequestedMine = "changes_requested_mine"

    /// Author ≠ me, I'm requested or no reviews yet.
    case awaitingMyReview = "awaiting_my_review"

    /// Author ≠ me, I previously reviewed and new commits have been pushed since.
    case newCommitsSinceMyReview = "new_commits_since_my_review"

    /// Author = me, the latest commit is by someone else and I haven't reviewed since.
    case stalePushedByOthers = "stale_pushed_by_others"

    /// Author = me, reviewDecision = APPROVED (clean to merge).
    case mergeableApprovedMine = "mergeable_approved_mine"

    var displayName: String {
        switch self {
        case .changesRequestedMine: return "Your PRs with changes requested"
        case .awaitingMyReview: return "Awaiting your review"
        case .newCommitsSinceMyReview: return "New commits since your review"
        case .stalePushedByOthers: return "Your PRs with non-author commits"
        case .mergeableApprovedMine: return "Your approved PRs (ready to merge)"
        }
    }

    static let defaultCatalog: [CategoryKind] = [
        .changesRequestedMine,
        .awaitingMyReview,
        .newCommitsSinceMyReview,
        .stalePushedByOthers,
    ]
}

/// True when the actor is a GitHub bot. Two signals: `is_bot` from the API
/// (when present) and the conventional `[bot]` suffix on the login (always
/// applied to bot accounts).
func isBotActor(_ actor: GHActor) -> Bool {
    if actor.isBot == true { return true }
    return actor.login.lowercased().hasSuffix("[bot]")
}

struct ClassifiedPR {
    let repo: DiscoveredRepo
    let detail: PRDetail
    let category: CategoryKind
    let reason: String
}

enum Classifier {
    static func classify(
        prs: [(repo: DiscoveredRepo, detail: PRDetail)],
        viewer: String,
        categories: [CategoryKind]
    ) -> [ClassifiedPR] {
        var out: [ClassifiedPR] = []
        // Priority order: A > C > B (per the original spec). Within the catalog
        // here, that maps to: changesRequestedMine, stalePushedByOthers,
        // newCommitsSinceMyReview, awaitingMyReview, mergeableApprovedMine.
        let priority: [CategoryKind] = [
            .changesRequestedMine,
            .stalePushedByOthers,
            .newCommitsSinceMyReview,
            .awaitingMyReview,
            .mergeableApprovedMine,
        ]
        let enabled = Set(categories)

        for (repo, pr) in prs {
            if pr.isDraft { continue }
            for kind in priority where enabled.contains(kind) {
                if let reason = match(pr: pr, kind: kind, viewer: viewer) {
                    out.append(ClassifiedPR(repo: repo, detail: pr, category: kind, reason: reason))
                    break
                }
            }
        }
        return out
    }

    private static func match(pr: PRDetail, kind: CategoryKind, viewer: String) -> String? {
        let isMine = pr.author.login.caseInsensitiveCompare(viewer) == .orderedSame
        switch kind {

        case .changesRequestedMine:
            guard isMine, pr.reviewDecision == "CHANGES_REQUESTED" else { return nil }
            return "changes requested"

        case .awaitingMyReview:
            guard !isMine else { return nil }
            // Either I'm explicitly requested as a reviewer...
            let requested = pr.reviewRequests.contains { $0.login?.caseInsensitiveCompare(viewer) == .orderedSame }
            if requested {
                return "review requested from you"
            }
            // ...or no review activity yet AND no specific reviewer is on the hook.
            // (If someone else is requested, it's their queue, not yours.)
            let someoneElseRequested = pr.reviewRequests.contains {
                ($0.login != nil) || ($0.name != nil)
            }
            let undecided = pr.reviewDecision == "REVIEW_REQUIRED" || pr.reviewDecision == nil || pr.reviewDecision == ""
            // Bot reviews (e.g. github-actions[bot] CI comments) don't count
            // as "the PR has been reviewed" — humans haven't looked at it yet.
            let humanReviews = pr.reviews.filter { !isBotActor($0.author) }
            if humanReviews.isEmpty, !someoneElseRequested, undecided {
                return "no reviews yet"
            }
            return nil

        case .newCommitsSinceMyReview:
            guard !isMine else { return nil }
            // Find my latest review (any state except PENDING).
            let myReviews = pr.reviews.filter {
                $0.author.login.caseInsensitiveCompare(viewer) == .orderedSame
            }
            guard let lastReview = myReviews.compactMap({ $0.submittedAt }).max() else {
                return nil
            }
            // Latest commit pushed after that review?
            let lastCommitDate = pr.commits.map(\.committedDate).max() ?? .distantPast
            let newCommits = pr.commits.filter { $0.committedDate > lastReview }.count
            guard lastCommitDate > lastReview, newCommits > 0 else { return nil }
            let sortedMine = myReviews.sorted { (a, b) in
                (a.submittedAt ?? .distantPast) > (b.submittedAt ?? .distantPast)
            }
            let rawState = sortedMine.first?.state ?? "REVIEWED"
            let stateText = rawState.lowercased().replacingOccurrences(of: "_", with: " ")
            let plural = newCommits == 1 ? "" : "s"
            return "\(newCommits) commit\(plural) since your \(stateText)"

        case .stalePushedByOthers:
            guard isMine else { return nil }
            // Newest commit
            guard let last = pr.commits.max(by: { $0.committedDate < $1.committedDate }) else { return nil }
            let lastAuthors = last.authors.map(\.login)
            let mineOnLast = lastAuthors.contains { $0.caseInsensitiveCompare(viewer) == .orderedSame }
            if mineOnLast { return nil }
            // Have I reviewed/commented after that commit?
            let myActions = pr.reviews.filter { $0.author.login.caseInsensitiveCompare(viewer) == .orderedSame }
            let myLatest = myActions.compactMap(\.submittedAt).max() ?? .distantPast
            if myLatest >= last.committedDate { return nil }
            let other = lastAuthors.first ?? "someone else"
            return "latest commit by \(other), no review from you since"

        case .mergeableApprovedMine:
            guard isMine, pr.reviewDecision == "APPROVED" else { return nil }
            return "approved — ready to merge"
        }
    }
}
