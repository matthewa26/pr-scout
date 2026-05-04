import XCTest
@testable import PRScout

final class FilterTests: XCTestCase {
    private let repo = DiscoveredRepo(owner: "x", name: "y")

    private func summary(
        number: Int = 1,
        login: String,
        isBot: Bool,
        isDraft: Bool = false,
        url: String = "https://github.com/x/y/pull/1"
    ) throws -> PRSummary {
        let json = """
        {
          "number": \(number),
          "title": "Test",
          "author": {"login": "\(login)", "is_bot": \(isBot)},
          "createdAt": "2026-05-01T00:00:00Z",
          "updatedAt": "2026-05-01T00:00:00Z",
          "isDraft": \(isDraft),
          "reviewDecision": null,
          "url": "\(url)",
          "headRefOid": "abc"
        }
        """
        return try JSONDecoder.gh.decode(PRSummary.self, from: Data(json.utf8))
    }

    func test_dropsAuthorsListedInIgnoreAuthors() throws {
        let pr = try summary(login: "dependabot[bot]", isBot: true)
        let result = filterPRSummaries([(repo, pr)], ignoreAuthors: ["dependabot[bot]"])
        XCTAssertTrue(result.isEmpty)
    }

    func test_keepsBotsWhenLoginIsNotInIgnoreAuthors() throws {
        // Regression: previously a hardcoded `is_bot != true` filter dropped
        // every bot PR regardless of the user's config. Removing dependabot
        // from ignoreAuthors must actually surface its PRs.
        let pr = try summary(login: "dependabot[bot]", isBot: true)
        let result = filterPRSummaries([(repo, pr)], ignoreAuthors: [])
        XCTAssertEqual(result.count, 1)
    }

    func test_dropsDraftsRegardlessOfAuthor() throws {
        let pr = try summary(login: "alice", isBot: false, isDraft: true)
        let result = filterPRSummaries([(repo, pr)], ignoreAuthors: [])
        XCTAssertTrue(result.isEmpty)
    }

    func test_keepsHumanAuthorsByDefault() throws {
        let pr = try summary(login: "alice", isBot: false)
        let result = filterPRSummaries([(repo, pr)], ignoreAuthors: [])
        XCTAssertEqual(result.count, 1)
    }

    func test_authorMatchIsCaseInsensitive() throws {
        let pr = try summary(login: "Dependabot[Bot]", isBot: true)
        let result = filterPRSummaries([(repo, pr)], ignoreAuthors: ["dependabot[bot]"])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - deduplicateSummariesByURL

    func test_dedupeCollapsesAliasedRepos() throws {
        // Same canonical URL via two clones with different origin owners (e.g.
        // the repo was renamed and an old clone still points to the previous
        // owner; GitHub redirects, so both `gh pr list` calls return the PR).
        let oldOwner = DiscoveredRepo(owner: "OldOrg", name: "the-repo")
        let newOwner = DiscoveredRepo(owner: "NewOrg", name: "the-repo")
        let url = "https://github.com/NewOrg/the-repo/pull/42"
        let pr1 = try summary(number: 42, login: "alice", isBot: false, url: url)
        let pr2 = try summary(number: 42, login: "alice", isBot: false, url: url)
        let result = deduplicateSummariesByURL([(oldOwner, pr1), (newOwner, pr2)])
        XCTAssertEqual(result.count, 1)
    }

    func test_dedupeKeepsDistinctPRs() throws {
        let r = DiscoveredRepo(owner: "x", name: "y")
        let pr1 = try summary(number: 1, login: "a", isBot: false, url: "https://github.com/x/y/pull/1")
        let pr2 = try summary(number: 2, login: "a", isBot: false, url: "https://github.com/x/y/pull/2")
        let result = deduplicateSummariesByURL([(r, pr1), (r, pr2)])
        XCTAssertEqual(result.count, 2)
    }
}
