import XCTest
@testable import PRScout

final class ConfigTests: XCTestCase {
    private var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    func test_expandsBareTilde() {
        XCTAssertEqual(ConfigLoader.expandTilde("~"), home)
    }

    func test_expandsTildeWithSubpath() {
        XCTAssertEqual(ConfigLoader.expandTilde("~/foo/bar"), home + "/foo/bar")
    }

    func test_doesNotExpandNonLeadingTilde() {
        XCTAssertEqual(ConfigLoader.expandTilde("/abs/path"), "/abs/path")
        XCTAssertEqual(ConfigLoader.expandTilde("relative/~/path"), "relative/~/path")
    }

    func test_resolvesByDirectoryPrefix() {
        let cfg = Config(
            defaultProfile: nil,
            profiles: [
                "work": Profile(directories: ["~/work"], githubUser: nil, categories: nil, scope: nil, ignoreAuthors: nil, owners: nil, excludeRepos: nil),
                "oss": Profile(directories: ["~/oss"], githubUser: nil, categories: nil, scope: nil, ignoreAuthors: nil, owners: nil, excludeRepos: nil),
            ]
        )
        let cwd = URL(fileURLWithPath: home + "/work/some-repo")
        let resolved = ConfigLoader.resolveProfile(cfg, cwd: cwd, override: nil)
        XCTAssertEqual(resolved?.name, "work")
    }

    func test_longestPrefixWins() {
        let cfg = Config(
            defaultProfile: nil,
            profiles: [
                "broad": Profile(directories: ["~/code"], githubUser: nil, categories: nil, scope: nil, ignoreAuthors: nil, owners: nil, excludeRepos: nil),
                "narrow": Profile(directories: ["~/code/work-stuff"], githubUser: nil, categories: nil, scope: nil, ignoreAuthors: nil, owners: nil, excludeRepos: nil),
            ]
        )
        let cwd = URL(fileURLWithPath: home + "/code/work-stuff/repo")
        let resolved = ConfigLoader.resolveProfile(cfg, cwd: cwd, override: nil)
        XCTAssertEqual(resolved?.name, "narrow")
    }

    func test_fallsBackToDefaultProfile() {
        let cfg = Config(
            defaultProfile: "personal",
            profiles: [
                "personal": Profile(directories: ["~/projects"], githubUser: nil, categories: nil, scope: nil, ignoreAuthors: nil, owners: nil, excludeRepos: nil),
            ]
        )
        let cwd = URL(fileURLWithPath: "/tmp/elsewhere")
        let resolved = ConfigLoader.resolveProfile(cfg, cwd: cwd, override: nil)
        XCTAssertEqual(resolved?.name, "personal")
    }

    func test_returnsNilWhenNoMatchAndNoDefault() {
        let cfg = Config(
            defaultProfile: nil,
            profiles: [
                "work": Profile(directories: ["~/work"], githubUser: nil, categories: nil, scope: nil, ignoreAuthors: nil, owners: nil, excludeRepos: nil),
            ]
        )
        let cwd = URL(fileURLWithPath: "/tmp/elsewhere")
        XCTAssertNil(ConfigLoader.resolveProfile(cfg, cwd: cwd, override: nil))
    }

    func test_explicitOverrideWinsRegardlessOfCwd() {
        let cfg = Config(
            defaultProfile: "work",
            profiles: [
                "work": Profile(directories: ["~/work"], githubUser: nil, categories: nil, scope: nil, ignoreAuthors: nil, owners: nil, excludeRepos: nil),
                "oss": Profile(directories: ["~/oss"], githubUser: nil, categories: nil, scope: nil, ignoreAuthors: nil, owners: nil, excludeRepos: nil),
            ]
        )
        let cwd = URL(fileURLWithPath: home + "/work/repo")
        let resolved = ConfigLoader.resolveProfile(cfg, cwd: cwd, override: "oss")
        XCTAssertEqual(resolved?.name, "oss")
    }

    func test_roundTripsJson() throws {
        let original = Config(
            defaultProfile: "personal",
            profiles: [
                "personal": Profile(
                    directories: ["~/projects"],
                    githubUser: "matthewa26",
                    categories: [.changesRequestedMine, .awaitingMyReview],
                    scope: .currentDirectoryRepos,
                    ignoreAuthors: ["dependabot[bot]"],
                    owners: ["matthewa26"],
                    excludeRepos: ["foo/legacy"]
                ),
            ]
        )
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr-scout-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try ConfigLoader.save(original, to: tmp)
        let decoded = try ConfigLoader.load(at: tmp)
        XCTAssertEqual(decoded.defaultProfile, "personal")
        XCTAssertEqual(decoded.profiles["personal"]?.githubUser, "matthewa26")
        XCTAssertEqual(decoded.profiles["personal"]?.categories, [.changesRequestedMine, .awaitingMyReview])
        XCTAssertEqual(decoded.profiles["personal"]?.owners, ["matthewa26"])
        XCTAssertEqual(decoded.profiles["personal"]?.excludeRepos, ["foo/legacy"])
    }
}
