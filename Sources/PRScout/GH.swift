import Foundation

struct GHError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

enum GH {
    /// Resolve gh on PATH; nil if missing.
    static func locate() -> String? {
        let env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
        for dir in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("gh").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Run `gh` with the given args and return raw stdout. Throws on non-zero exit.
    @discardableResult
    static func run(_ args: [String]) throws -> Data {
        guard let bin = locate() else {
            throw GHError(message: InstallHint.ghMissingMessage())
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errText = String(data: errData, encoding: .utf8) ?? ""
            let cmd = "gh " + args.joined(separator: " ")
            throw GHError(message: "`\(cmd)` failed (exit \(process.terminationStatus)): \(errText)")
        }
        return outData
    }

    static func runJSON<T: Decodable>(_ args: [String], as type: T.Type) throws -> T {
        let data = try run(args)
        do {
            return try JSONDecoder.gh.decode(T.self, from: data)
        } catch {
            let preview = String(data: data.prefix(400), encoding: .utf8) ?? "<non-utf8>"
            throw GHError(message: "Failed to decode gh JSON output: \(error). First 400 bytes:\n\(preview)")
        }
    }

    static func viewerLogin() throws -> String {
        struct User: Decodable { let login: String }
        let user = try runJSON(["api", "user"], as: User.self)
        return user.login
    }

    /// One-shot summary of open PRs in a repo. Cheap; one network call.
    static func listOpenPRs(repo: DiscoveredRepo) throws -> [PRSummary] {
        let fields = "number,title,author,createdAt,updatedAt,isDraft,reviewDecision,url,headRefOid"
        return try runJSON(
            ["pr", "list", "--repo", repo.slug, "--state", "open", "--limit", "200", "--json", fields],
            as: [PRSummary].self
        )
    }

    /// Detailed view of one PR including reviews + commits. Used for category filtering.
    static func viewPR(repo: DiscoveredRepo, number: Int) throws -> PRDetail {
        let fields = "number,title,author,createdAt,updatedAt,isDraft,reviewDecision,url,reviews,commits,reviewRequests,latestReviews,headRefOid"
        return try runJSON(
            ["pr", "view", String(number), "--repo", repo.slug, "--json", fields],
            as: PRDetail.self
        )
    }
}

// MARK: - Decoders

extension JSONDecoder {
    static let gh: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601withFractional
        return d
    }()
}

extension JSONDecoder.DateDecodingStrategy {
    static var iso8601withFractional: JSONDecoder.DateDecodingStrategy {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return .custom { decoder in
            let container = try decoder.singleValueContainer()
            let s = try container.decode(String.self)
            if let d = withFractional.date(from: s) { return d }
            if let d = plain.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date string: \(s)"
            )
        }
    }
}

// MARK: - Models (matching gh's --json field names)

struct GHActor: Decodable, Hashable {
    let login: String
    let isBot: Bool?

    private enum CodingKeys: String, CodingKey { case login, isBot, is_bot }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `gh pr list`'s author payload uses "is_bot"; some other endpoints use "isBot".
        self.login = try c.decode(String.self, forKey: .login)
        if let b = try c.decodeIfPresent(Bool.self, forKey: .isBot) {
            self.isBot = b
        } else if let b = try c.decodeIfPresent(Bool.self, forKey: .is_bot) {
            self.isBot = b
        } else {
            self.isBot = nil
        }
    }
}

struct PRSummary: Decodable {
    let number: Int
    let title: String
    let author: GHActor
    let createdAt: Date
    let updatedAt: Date
    let isDraft: Bool
    let reviewDecision: String?  // "APPROVED" | "CHANGES_REQUESTED" | "REVIEW_REQUIRED" | nil/""
    let url: String
    let headRefOid: String?
}

struct PRDetail: Decodable {
    let number: Int
    let title: String
    let author: GHActor
    let createdAt: Date
    let updatedAt: Date
    let isDraft: Bool
    let reviewDecision: String?
    let url: String
    let reviews: [Review]
    let commits: [Commit]
    let reviewRequests: [ReviewRequest]
    let latestReviews: [Review]?
    let headRefOid: String?

    struct Review: Decodable {
        let author: GHActor
        let state: String  // APPROVED | CHANGES_REQUESTED | COMMENTED | DISMISSED | PENDING
        let submittedAt: Date?
        let body: String?
    }

    struct Commit: Decodable {
        let oid: String
        let messageHeadline: String?
        let committedDate: Date
        let authors: [GHActor]
    }

    struct ReviewRequest: Decodable {
        let login: String?
        let name: String?
        // gh emits a polymorphic shape: user requests have `login`,
        // team requests have `name` (and `slug`).
    }
}
