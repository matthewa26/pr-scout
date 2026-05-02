import XCTest
@testable import PRScout

final class RepoDiscoveryTests: XCTestCase {
    func test_parsesSshUrlWithGitSuffix() {
        let r = RepoDiscovery.parseGitHubURL("git@github.com:foo/bar.git")
        XCTAssertEqual(r?.owner, "foo")
        XCTAssertEqual(r?.name, "bar")
    }

    func test_parsesSshUrlWithoutGitSuffix() {
        let r = RepoDiscovery.parseGitHubURL("git@github.com:foo/bar")
        XCTAssertEqual(r?.owner, "foo")
        XCTAssertEqual(r?.name, "bar")
    }

    func test_parsesHttpsUrlWithGitSuffix() {
        let r = RepoDiscovery.parseGitHubURL("https://github.com/foo/bar.git")
        XCTAssertEqual(r?.owner, "foo")
        XCTAssertEqual(r?.name, "bar")
    }

    func test_parsesHttpsUrlWithoutGitSuffix() {
        let r = RepoDiscovery.parseGitHubURL("https://github.com/foo/bar")
        XCTAssertEqual(r?.owner, "foo")
        XCTAssertEqual(r?.name, "bar")
    }

    func test_parsesSshSchemeUrl() {
        let r = RepoDiscovery.parseGitHubURL("ssh://git@github.com/foo/bar.git")
        XCTAssertEqual(r?.owner, "foo")
        XCTAssertEqual(r?.name, "bar")
    }

    func test_stripsTrailingSlash() {
        let r = RepoDiscovery.parseGitHubURL("https://github.com/foo/bar/")
        XCTAssertEqual(r?.owner, "foo")
        XCTAssertEqual(r?.name, "bar")
    }

    func test_returnsNilForNonGitHubHost() {
        XCTAssertNil(RepoDiscovery.parseGitHubURL("https://gitlab.com/foo/bar.git"))
        XCTAssertNil(RepoDiscovery.parseGitHubURL("git@gitlab.com:foo/bar.git"))
    }

    func test_returnsNilForMalformedInput() {
        XCTAssertNil(RepoDiscovery.parseGitHubURL(""))
        XCTAssertNil(RepoDiscovery.parseGitHubURL("https://github.com/"))
        XCTAssertNil(RepoDiscovery.parseGitHubURL("git@github.com:"))
        XCTAssertNil(RepoDiscovery.parseGitHubURL("git@github.com:onlyowner"))
    }

}
