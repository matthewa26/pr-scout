import XCTest
@testable import PRScout

final class FilterTests: XCTestCase {
    private let repo = DiscoveredRepo(owner: "x", name: "y")

    private func summary(login: String, isBot: Bool, isDraft: Bool = false) throws -> PRSummary {
        let json = """
        {
          "number": 1,
          "title": "Test",
          "author": {"login": "\(login)", "is_bot": \(isBot)},
          "createdAt": "2026-05-01T00:00:00Z",
          "updatedAt": "2026-05-01T00:00:00Z",
          "isDraft": \(isDraft),
          "reviewDecision": null,
          "url": "https://github.com/x/y/pull/1",
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
}
