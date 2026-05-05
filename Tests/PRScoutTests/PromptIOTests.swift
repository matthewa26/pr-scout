import XCTest
@testable import PRScout

final class PromptIOTests: XCTestCase {
    // MARK: - confirm

    func test_confirm_emptyInputReturnsDefaultTrue() {
        let io = ScriptedIO(inputs: [""])
        XCTAssertTrue(io.confirm("Continue?", default: true))
    }

    func test_confirm_emptyInputReturnsDefaultFalse() {
        let io = ScriptedIO(inputs: [""])
        XCTAssertFalse(io.confirm("Continue?", default: false))
    }

    func test_confirm_acceptsYesVariants() {
        for variant in ["y", "Y", "yes", "YES", "true", "1"] {
            let io = ScriptedIO(inputs: [variant])
            XCTAssertTrue(io.confirm("Continue?", default: false), "expected \(variant) → true")
        }
    }

    func test_confirm_acceptsNoVariants() {
        for variant in ["n", "N", "no", "NO", "false", "0"] {
            let io = ScriptedIO(inputs: [variant])
            XCTAssertFalse(io.confirm("Continue?", default: true), "expected \(variant) → false")
        }
    }

    func test_confirm_unknownInputReturnsDefault() {
        let io = ScriptedIO(inputs: ["maybe"])
        XCTAssertTrue(io.confirm("Continue?", default: true))
    }

    // MARK: - prompt

    func test_prompt_returnsDefaultOnEmptyInput() {
        let io = ScriptedIO(inputs: [""])
        XCTAssertEqual(io.prompt("Name", default: "alice"), "alice")
    }

    func test_prompt_returnsTrimmedInput() {
        let io = ScriptedIO(inputs: ["  bob  "])
        XCTAssertEqual(io.prompt("Name"), "bob")
    }

    func test_prompt_rePromptsOnValidatorFailure() {
        let io = ScriptedIO(inputs: ["", "valid"])
        let result = io.prompt("Name", validator: { v in v.isEmpty ? "empty!" : nil })
        XCTAssertEqual(result, "valid")
    }

    // MARK: - choose

    func test_choose_emptyInputReturnsDefault() {
        let io = ScriptedIO(inputs: [""])
        XCTAssertEqual(io.choose("Pick", options: ["a", "b", "c"], default: 1), 1)
    }

    func test_choose_returnsSelectedIndex() {
        let io = ScriptedIO(inputs: ["3"])
        XCTAssertEqual(io.choose("Pick", options: ["a", "b", "c"]), 2)
    }

    func test_choose_rePromptsOnInvalid() {
        let io = ScriptedIO(inputs: ["99", "abc", "2"])
        XCTAssertEqual(io.choose("Pick", options: ["a", "b", "c"]), 1)
    }

    // MARK: - multiChoose

    func test_multiChoose_emptyInputReturnsDefaults() {
        let io = ScriptedIO(inputs: [""])
        let result = io.multiChoose("Pick", options: ["a", "b", "c"], defaults: [0, 2])
        XCTAssertEqual(result, [0, 2])
    }

    func test_multiChoose_parsesCommaSeparated() {
        let io = ScriptedIO(inputs: ["1, 3"])
        let result = io.multiChoose("Pick", options: ["a", "b", "c"])
        XCTAssertEqual(result, [0, 2])
    }

    func test_multiChoose_rePromptsOnOutOfRange() {
        let io = ScriptedIO(inputs: ["1,99", "2"])
        let result = io.multiChoose("Pick", options: ["a", "b", "c"])
        XCTAssertEqual(result, [1])
    }
}

/// Test double that feeds scripted inputs and captures outputs in order.
final class ScriptedIO: PromptIO {
    private(set) var outputs: [String] = []
    private var inputs: [String]

    init(inputs: [String]) { self.inputs = inputs }

    func writeLine(_ s: String) { outputs.append(s) }
    func write(_ s: String) { outputs.append(s) }
    func readLine() -> String? {
        guard !inputs.isEmpty else { return nil }
        return inputs.removeFirst()
    }
}
