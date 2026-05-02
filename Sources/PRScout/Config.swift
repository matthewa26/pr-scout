import Foundation

struct Config: Codable {
    var defaultProfile: String?
    var profiles: [String: Profile]

    static let empty = Config(defaultProfile: nil, profiles: [:])
}

struct Profile: Codable {
    /// Directory prefixes (supporting `~`) used to auto-resolve a profile
    /// from the current working directory. Optional.
    var directories: [String]?

    /// Override the GitHub user. If nil, `gh api user` is used.
    var githubUser: String?

    /// Categories to evaluate. If nil, the default catalog is used.
    var categories: [CategoryKind]?

    /// How repos are discovered.
    var scope: Scope?

    enum Scope: String, Codable {
        /// Walk profile directories, find local clones, query only those repos.
        case currentDirectoryRepos
        /// Walk profile directories, infer the unique GitHub orgs, query all PRs in those orgs.
        case discoveredOrgs
    }

    /// Authors to ignore when scanning (bots etc). Defaults to a sensible bot list.
    var ignoreAuthors: [String]?

    /// Allowlist of GitHub owners (orgs/users). When set, only repos whose owner
    /// is in this list will be queried — even if other clones exist in the
    /// scanned directories. Useful when you also clone OSS repos that you don't
    /// want polluting your "needs my attention" list.
    var owners: [String]?

    /// Explicit list of `owner/repo` slugs to skip even when discovered.
    var excludeRepos: [String]?
}

enum ConfigLoader {
    static var defaultPath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            .flatMap { $0.isEmpty ? nil : $0 }
            .map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".config", isDirectory: true)
        return xdg
            .appendingPathComponent("pr-scout", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    static func load(at path: URL? = nil) throws -> Config {
        let url = path ?? defaultPath
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    static func save(_ config: Config, to path: URL? = nil) throws {
        let url = path ?? defaultPath
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    /// Pick the profile that best matches `cwd`, preferring the most-specific
    /// directory prefix. Falls back to `defaultProfile`, then nil.
    static func resolveProfile(_ config: Config, cwd: URL, override: String?) -> (name: String, profile: Profile)? {
        if let name = override {
            return config.profiles[name].map { (name, $0) }
        }
        let cwdPath = cwd.standardizedFileURL.path
        var best: (name: String, profile: Profile, length: Int)?
        for (name, profile) in config.profiles {
            for raw in profile.directories ?? [] {
                let expanded = expandTilde(raw)
                let normalized = URL(fileURLWithPath: expanded).standardizedFileURL.path
                if cwdPath == normalized || cwdPath.hasPrefix(normalized + "/") {
                    if best == nil || normalized.count > best!.length {
                        best = (name, profile, normalized.count)
                    }
                }
            }
        }
        if let best { return (best.name, best.profile) }
        if let dflt = config.defaultProfile, let p = config.profiles[dflt] {
            return (dflt, p)
        }
        return nil
    }

    static func expandTilde(_ path: String) -> String {
        if path == "~" { return FileManager.default.homeDirectoryForCurrentUser.path }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2)))
                .path
        }
        return path
    }
}
