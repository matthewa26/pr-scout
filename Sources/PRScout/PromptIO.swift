import Foundation

/// Minimal IO surface for interactive prompts. Abstracted so the wizard's
/// flow can be exercised in tests by injecting a scripted IO.
protocol PromptIO {
    func writeLine(_ s: String)
    func write(_ s: String)
    func readLine() -> String?
}

/// Production implementation backed by stdin/stdout. Uses `FileHandle.write`
/// directly so partial-line prompts (no trailing newline) appear before
/// `readLine()` blocks, regardless of stdout buffering mode.
struct StandardPromptIO: PromptIO {
    func writeLine(_ s: String) {
        FileHandle.standardOutput.write(Data((s + "\n").utf8))
    }
    func write(_ s: String) {
        FileHandle.standardOutput.write(Data(s.utf8))
    }
    func readLine() -> String? {
        Swift.readLine()
    }
}

extension PromptIO {
    /// Yes/no prompt. Returns the default when input is empty or unrecognized.
    func confirm(_ message: String, default defaultValue: Bool) -> Bool {
        let suffix = defaultValue ? "[Y/n]" : "[y/N]"
        write("\(message) \(suffix) ")
        guard let raw = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
            return defaultValue
        }
        if raw.isEmpty { return defaultValue }
        if ["y", "yes", "true", "1"].contains(raw) { return true }
        if ["n", "no", "false", "0"].contains(raw) { return false }
        return defaultValue
    }

    /// Free-text prompt with optional default and optional validator.
    /// Validator returns nil on accept, an error message on reject (re-prompts).
    func prompt(
        _ message: String,
        default defaultValue: String? = nil,
        validator: ((String) -> String?)? = nil
    ) -> String {
        while true {
            if let d = defaultValue, !d.isEmpty {
                write("\(message) [\(d)]: ")
            } else {
                write("\(message): ")
            }
            let line = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
            let value = line.isEmpty ? (defaultValue ?? "") : line
            if let validator, let err = validator(value) {
                writeLine("  \(err)")
                continue
            }
            return value
        }
    }

    /// Single-pick from a list. Returns the chosen index. Empty input picks `default`.
    func choose(_ message: String, options: [String], default defaultIndex: Int = 0) -> Int {
        writeLine(message)
        for (i, opt) in options.enumerated() {
            let marker = i == defaultIndex ? "*" : " "
            writeLine("  \(marker) \(i + 1)) \(opt)")
        }
        while true {
            write("Choose [\(defaultIndex + 1)]: ")
            guard let line = readLine()?.trimmingCharacters(in: .whitespaces) else {
                return defaultIndex
            }
            if line.isEmpty { return defaultIndex }
            if let n = Int(line), (1...options.count).contains(n) {
                return n - 1
            }
            writeLine("  invalid choice; enter a number 1–\(options.count)")
        }
    }

    /// Multi-pick from a list. Empty input returns the starred defaults.
    /// Otherwise expects comma-separated 1-based indices.
    func multiChoose(
        _ message: String,
        options: [String],
        defaults: Set<Int> = []
    ) -> Set<Int> {
        writeLine(message)
        for (i, opt) in options.enumerated() {
            let mark = defaults.contains(i) ? "*" : " "
            writeLine("  \(mark) \(i + 1)) \(opt)")
        }
        writeLine("(comma-separated numbers, or empty to keep the starred defaults)")
        while true {
            write("> ")
            guard let line = readLine() else { return defaults }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return defaults }
            let parts = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            var picks = Set<Int>()
            var ok = true
            for p in parts {
                guard let n = Int(p), (1...options.count).contains(n) else {
                    ok = false
                    break
                }
                picks.insert(n - 1)
            }
            if ok { return picks }
            writeLine("  invalid choice; expected comma-separated numbers 1–\(options.count)")
        }
    }
}
