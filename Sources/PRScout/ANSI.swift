import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum ANSI {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let magenta = "\u{001B}[35m"
    static let cyan = "\u{001B}[36m"
    static let gray = "\u{001B}[90m"

    static var stdoutIsTTY: Bool {
        isatty(fileno(stdout)) != 0
    }

    static func color(_ s: String, _ code: String, enabled: Bool) -> String {
        enabled ? "\(code)\(s)\(reset)" : s
    }
}
