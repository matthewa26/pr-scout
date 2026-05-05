import XCTest
@testable import PRScout

final class ConfigWizardTests: XCTestCase {
    func test_buildProfile_minimalFlow() {
        let io = ScriptedIO(inputs: [
            "work",                                    // profile name
            "~/code",                                  // directories
            "y",                                       // use detected GH user (matt)
            "",                                        // owners — accept suggestions (none here)
            "",                                        // categories — accept defaults
        ])
        let wizard = ConfigWizard(
            io: io,
            configPath: URL(fileURLWithPath: "/tmp/unused"),
            viewerLoginProvider: { "matt" },
            ownerDetector: { _ in [] },
            saveAction: { _, _ in }
        )
        let result = wizard.buildProfile(existingNames: [])
        XCTAssertEqual(result.name, "work")
        XCTAssertEqual(result.profile.directories, ["~/code"])
        XCTAssertNil(result.profile.githubUser)  // nil = "use gh api user at runtime"
        XCTAssertEqual(result.profile.categories, CategoryKind.defaultCatalog)
        XCTAssertNil(result.profile.owners)
    }

    func test_buildProfile_overridesDetectedUserAndAddsOwners() {
        let io = ScriptedIO(inputs: [
            "work",
            "~/code",
            "n",                  // do NOT use detected user
            "matthewa26",         // explicit user
            "truthly-inc",        // owners
            "1",                  // pick only the first category
        ])
        let wizard = ConfigWizard(
            io: io,
            configPath: URL(fileURLWithPath: "/tmp/unused"),
            viewerLoginProvider: { "wrong-user" },
            ownerDetector: { _ in ["truthly-inc"] },
            saveAction: { _, _ in }
        )
        let result = wizard.buildProfile(existingNames: [])
        XCTAssertEqual(result.profile.githubUser, "matthewa26")
        XCTAssertEqual(result.profile.owners, ["truthly-inc"])
        XCTAssertEqual(result.profile.categories, [CategoryKind.allCases[0]])
    }

    func test_buildProfile_rejectsDuplicateName() {
        let io = ScriptedIO(inputs: [
            "personal",            // already taken — rejected
            "work",                // accepted
            "~/code",
            "y",
            "",
            "",
        ])
        let wizard = ConfigWizard(
            io: io,
            configPath: URL(fileURLWithPath: "/tmp/unused"),
            viewerLoginProvider: { "alice" },
            ownerDetector: { _ in [] },
            saveAction: { _, _ in }
        )
        let result = wizard.buildProfile(existingNames: ["personal"])
        XCTAssertEqual(result.name, "work")
    }

    func test_run_savesCompleteConfig() throws {
        let saveExpectation = SaveCapture()
        let io = ScriptedIO(inputs: [
            "personal",
            "~/projects",
            "y",
            "",
            "",
            "n",                  // no second profile
            "y",                  // save
        ])
        let wizard = ConfigWizard(
            io: io,
            configPath: URL(fileURLWithPath: "/tmp/pr-scout-wizard-test.json"),
            viewerLoginProvider: { "alice" },
            ownerDetector: { _ in [] },
            saveAction: { config, url in
                saveExpectation.config = config
                saveExpectation.url = url
            }
        )
        try wizard.run()
        XCTAssertNotNil(saveExpectation.config)
        XCTAssertEqual(saveExpectation.config?.defaultProfile, "personal")
        XCTAssertEqual(saveExpectation.config?.profiles.count, 1)
        XCTAssertNotNil(saveExpectation.config?.profiles["personal"])
    }

    func test_run_userCancelsAtSavePrompt() throws {
        let saveExpectation = SaveCapture()
        let io = ScriptedIO(inputs: [
            "personal",
            "~/projects",
            "y",
            "",
            "",
            "n",
            "n",                  // do not save
        ])
        let wizard = ConfigWizard(
            io: io,
            configPath: URL(fileURLWithPath: "/tmp/pr-scout-wizard-test.json"),
            viewerLoginProvider: { "alice" },
            ownerDetector: { _ in [] },
            saveAction: { config, url in
                saveExpectation.config = config
                saveExpectation.url = url
            }
        )
        try wizard.run()
        XCTAssertNil(saveExpectation.config, "saveAction should not have been invoked")
    }
}

private final class SaveCapture {
    var config: Config?
    var url: URL?
}
