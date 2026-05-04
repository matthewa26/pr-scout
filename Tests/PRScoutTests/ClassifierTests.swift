import XCTest
@testable import PRScout

final class ClassifierTests: XCTestCase {
    private let viewer = "alice"
    private let repo = DiscoveredRepo(owner: "x", name: "y")

    private func classify(_ json: String, categories: [CategoryKind] = CategoryKind.allCases) throws -> [ClassifiedPR] {
        let pr = try JSONDecoder.gh.decode(PRDetail.self, from: Data(json.utf8))
        return Classifier.classify(prs: [(repo, pr)], viewer: viewer, categories: categories)
    }

    // MARK: - changes_requested_mine

    func test_changesRequestedMine_matchesWhenAuthoredByViewer() throws {
        let result = try classify(JSON.pr(author: "alice", reviewDecision: "CHANGES_REQUESTED"))
        XCTAssertEqual(result.first?.category, .changesRequestedMine)
    }

    func test_changesRequestedMine_skippedWhenAuthoredByOther() throws {
        let result = try classify(JSON.pr(author: "bob", reviewDecision: "CHANGES_REQUESTED"))
        XCTAssertNotEqual(result.first?.category, .changesRequestedMine)
    }

    // MARK: - awaiting_my_review

    func test_awaitingMyReview_whenViewerIsRequested() throws {
        let result = try classify(JSON.pr(author: "bob", reviewRequestLogins: ["alice"]))
        XCTAssertEqual(result.first?.category, .awaitingMyReview)
        XCTAssertTrue(result.first?.reason.contains("requested") == true)
    }

    func test_awaitingMyReview_whenNoReviewsAndNoOtherRequested() throws {
        let result = try classify(JSON.pr(author: "bob", reviewDecision: "REVIEW_REQUIRED"))
        XCTAssertEqual(result.first?.category, .awaitingMyReview)
        XCTAssertTrue(result.first?.reason.contains("no reviews") == true)
    }

    func test_awaitingMyReview_skippedWhenSomeoneElseIsRequested() throws {
        let result = try classify(JSON.pr(author: "bob", reviewRequestLogins: ["carol"]))
        XCTAssertTrue(result.isEmpty)
    }

    func test_awaitingMyReview_skippedWhenAuthoredByViewer() throws {
        let result = try classify(JSON.pr(author: "alice", reviewDecision: "REVIEW_REQUIRED"))
        // viewer's own PRs never qualify for awaitingMyReview
        XCTAssertNotEqual(result.first?.category, .awaitingMyReview)
    }

    func test_awaitingMyReview_treatsBotReviewsAsNoReview() throws {
        // Regression: github-actions[bot] (and similar CI bots) leave COMMENTED
        // reviews on every PR, which previously caused `pr.reviews.isEmpty` to
        // return false and the PR to silently drop out of the category. A PR
        // with only bot reviews still has no human reviewer attention.
        let result = try classify(JSON.pr(
            author: "bob",
            reviewDecision: "REVIEW_REQUIRED",
            reviews: [(login: "github-actions[bot]", state: "COMMENTED", at: "2026-05-04T00:00:00Z")]
        ))
        XCTAssertEqual(result.first?.category, .awaitingMyReview)
        XCTAssertTrue(result.first?.reason.contains("no reviews") == true)
    }

    // MARK: - new_commits_since_my_review

    func test_newCommitsSinceMyReview_matchesWhenCommitsLandAfterReview() throws {
        let result = try classify(JSON.pr(
            author: "bob",
            reviews: [(login: "alice", state: "CHANGES_REQUESTED", at: "2026-05-01T00:00:00Z")],
            commits: [
                (oid: "a", at: "2026-04-30T00:00:00Z", authors: ["bob"]),
                (oid: "b", at: "2026-05-01T12:00:00Z", authors: ["bob"]),
            ]
        ))
        XCTAssertEqual(result.first?.category, .newCommitsSinceMyReview)
        XCTAssertTrue(result.first?.reason.contains("1 commit") == true)
    }

    func test_newCommitsSinceMyReview_skippedWhenNoCommitsAfterReview() throws {
        let result = try classify(JSON.pr(
            author: "bob",
            reviews: [(login: "alice", state: "APPROVED", at: "2026-05-02T00:00:00Z")],
            commits: [(oid: "a", at: "2026-05-01T00:00:00Z", authors: ["bob"])]
        ))
        XCTAssertNotEqual(result.first?.category, .newCommitsSinceMyReview)
    }

    func test_newCommitsSinceMyReview_skippedWhenViewerHasNotReviewed() throws {
        let result = try classify(JSON.pr(
            author: "bob",
            reviews: [(login: "carol", state: "APPROVED", at: "2026-05-01T00:00:00Z")],
            commits: [(oid: "a", at: "2026-05-02T00:00:00Z", authors: ["bob"])]
        ))
        XCTAssertNotEqual(result.first?.category, .newCommitsSinceMyReview)
    }

    // MARK: - stale_pushed_by_others

    func test_stalePushedByOthers_matchesWhenLatestCommitIsByOther() throws {
        let result = try classify(JSON.pr(
            author: "alice",
            commits: [
                (oid: "a", at: "2026-05-01T00:00:00Z", authors: ["alice"]),
                (oid: "b", at: "2026-05-02T00:00:00Z", authors: ["bob"]),
            ]
        ))
        XCTAssertEqual(result.first?.category, .stalePushedByOthers)
        XCTAssertTrue(result.first?.reason.contains("bob") == true)
    }

    func test_stalePushedByOthers_skippedWhenViewerCommittedSince() throws {
        let result = try classify(JSON.pr(
            author: "alice",
            reviews: [(login: "alice", state: "COMMENTED", at: "2026-05-03T00:00:00Z")],
            commits: [
                (oid: "a", at: "2026-05-01T00:00:00Z", authors: ["alice"]),
                (oid: "b", at: "2026-05-02T00:00:00Z", authors: ["bob"]),
            ]
        ))
        // Viewer commented after bob's commit → not stale
        XCTAssertNotEqual(result.first?.category, .stalePushedByOthers)
    }

    func test_stalePushedByOthers_skippedWhenLatestIsByViewer() throws {
        let result = try classify(JSON.pr(
            author: "alice",
            commits: [
                (oid: "a", at: "2026-05-01T00:00:00Z", authors: ["bob"]),
                (oid: "b", at: "2026-05-02T00:00:00Z", authors: ["alice"]),
            ]
        ))
        XCTAssertNotEqual(result.first?.category, .stalePushedByOthers)
    }

    // MARK: - mergeable_approved_mine

    func test_mergeableApprovedMine_matches() throws {
        let result = try classify(JSON.pr(author: "alice", reviewDecision: "APPROVED"))
        XCTAssertEqual(result.first?.category, .mergeableApprovedMine)
    }

    // MARK: - priority + filtering

    func test_priorityPrefersChangesRequestedOverStale() throws {
        // Mine + CHANGES_REQUESTED + latest commit by bob → should classify as
        // changes_requested_mine (higher priority), not stale_pushed_by_others.
        let result = try classify(JSON.pr(
            author: "alice",
            reviewDecision: "CHANGES_REQUESTED",
            commits: [(oid: "b", at: "2026-05-02T00:00:00Z", authors: ["bob"])]
        ))
        XCTAssertEqual(result.first?.category, .changesRequestedMine)
    }

    func test_draftsAreSkipped() throws {
        let result = try classify(JSON.pr(author: "alice", reviewDecision: "CHANGES_REQUESTED", isDraft: true))
        XCTAssertTrue(result.isEmpty)
    }

    func test_disabledCategoriesAreFilteredOut() throws {
        // Configure only awaiting_my_review enabled; a CHANGES_REQUESTED on
        // viewer's PR shouldn't surface anywhere.
        let result = try classify(
            JSON.pr(author: "alice", reviewDecision: "CHANGES_REQUESTED"),
            categories: [.awaitingMyReview]
        )
        XCTAssertTrue(result.isEmpty)
    }
}

// MARK: - Test JSON builder

private enum JSON {
    static func pr(
        author: String,
        reviewDecision: String? = nil,
        isDraft: Bool = false,
        reviewRequestLogins: [String] = [],
        reviews: [(login: String, state: String, at: String)] = [],
        commits: [(oid: String, at: String, authors: [String])] = []
    ) -> String {
        let decisionField: String = {
            if let d = reviewDecision { return "\"\(d)\"" }
            return "null"
        }()
        let requestsJson = reviewRequestLogins
            .map { "{\"login\":\"\($0)\"}" }
            .joined(separator: ",")
        let reviewsJson = reviews
            .map { "{\"author\":{\"login\":\"\($0.login)\",\"is_bot\":false},\"state\":\"\($0.state)\",\"submittedAt\":\"\($0.at)\",\"body\":\"\"}" }
            .joined(separator: ",")
        let commitsJson = commits.map { c -> String in
            let authors = c.authors
                .map { "{\"login\":\"\($0)\",\"is_bot\":false}" }
                .joined(separator: ",")
            return "{\"oid\":\"\(c.oid)\",\"messageHeadline\":\"\",\"committedDate\":\"\(c.at)\",\"authors\":[\(authors)]}"
        }.joined(separator: ",")
        return """
        {
          "number": 1,
          "title": "Test PR",
          "author": {"login": "\(author)", "is_bot": false},
          "createdAt": "2026-04-30T00:00:00Z",
          "updatedAt": "2026-05-01T00:00:00Z",
          "isDraft": \(isDraft),
          "reviewDecision": \(decisionField),
          "url": "https://github.com/x/y/pull/1",
          "reviews": [\(reviewsJson)],
          "commits": [\(commitsJson)],
          "reviewRequests": [\(requestsJson)]
        }
        """
    }
}
