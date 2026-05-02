import Foundation

struct DiscoveredRepo: Hashable {
    let owner: String
    let name: String
    var slug: String { "\(owner)/\(name)" }
}

enum RepoDiscovery {
    /// Walk the given roots and return unique GitHub `owner/repo` pairs found
    /// from `.git/config` `[remote "origin"]` URLs.
    static func discover(in roots: [URL], maxDepth: Int = 6) -> [DiscoveredRepo] {
        var seen = Set<DiscoveredRepo>()
        for root in roots {
            walk(root, depth: 0, maxDepth: maxDepth) { gitDir in
                if let repo = parseOriginRemote(gitDir: gitDir) {
                    seen.insert(repo)
                }
            }
        }
        return seen.sorted { $0.slug < $1.slug }
    }

    private static func walk(
        _ url: URL,
        depth: Int,
        maxDepth: Int,
        onGitDir: (URL) -> Void
    ) {
        guard depth <= maxDepth else { return }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }

        let gitDir = url.appendingPathComponent(".git", isDirectory: true)
        if fm.fileExists(atPath: gitDir.path) {
            onGitDir(gitDir)
            // Don't descend into a repo's children — they aren't separate repos
            // we'd otherwise discover. (Submodules use a different structure.)
            return
        }

        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries {
            let name = entry.lastPathComponent
            if shouldSkipDirectory(name) { continue }
            walk(entry, depth: depth + 1, maxDepth: maxDepth, onGitDir: onGitDir)
        }
    }

    private static let skipDirNames: Set<String> = [
        "node_modules", "Pods", ".build", "DerivedData", "build",
        "target", "dist", "out", "vendor", ".venv", "venv", "__pycache__",
    ]

    private static func shouldSkipDirectory(_ name: String) -> Bool {
        skipDirNames.contains(name)
    }

    private static func parseOriginRemote(gitDir: URL) -> DiscoveredRepo? {
        // Handles both regular .git directories and submodule .git files.
        var configURL = gitDir.appendingPathComponent("config")
        if !FileManager.default.fileExists(atPath: configURL.path) {
            // .git might be a file pointing to a worktree's gitdir
            if let txt = try? String(contentsOf: gitDir, encoding: .utf8),
               let line = txt.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) {
                let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                let resolved = URL(fileURLWithPath: path, relativeTo: gitDir.deletingLastPathComponent()).standardizedFileURL
                configURL = resolved.appendingPathComponent("config")
            } else {
                return nil
            }
        }

        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return nil
        }

        // Naive INI scan looking for [remote "origin"] -> url = ...
        var inOriginSection = false
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inOriginSection = trimmed == "[remote \"origin\"]"
                continue
            }
            if inOriginSection, trimmed.hasPrefix("url") {
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let url = parts[1].trimmingCharacters(in: .whitespaces)
                if let repo = parseGitHubURL(url) {
                    return repo
                }
            }
        }
        return nil
    }

    static func parseGitHubURL(_ raw: String) -> DiscoveredRepo? {
        // git@github.com:owner/repo(.git)?
        if raw.hasPrefix("git@github.com:") {
            let tail = String(raw.dropFirst("git@github.com:".count))
            return splitOwnerRepo(tail)
        }
        // ssh://git@github.com/owner/repo(.git)?
        if raw.hasPrefix("ssh://git@github.com/") {
            return splitOwnerRepo(String(raw.dropFirst("ssh://git@github.com/".count)))
        }
        // https://github.com/owner/repo(.git)?
        if raw.hasPrefix("https://github.com/") {
            return splitOwnerRepo(String(raw.dropFirst("https://github.com/".count)))
        }
        if raw.hasPrefix("http://github.com/") {
            return splitOwnerRepo(String(raw.dropFirst("http://github.com/".count)))
        }
        return nil
    }

    private static func splitOwnerRepo(_ tail: String) -> DiscoveredRepo? {
        var s = tail
        if s.hasSuffix(".git") { s.removeLast(4) }
        if s.hasSuffix("/") { s.removeLast() }
        let parts = s.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let owner = String(parts[0])
        let name = String(parts[1])
        guard !owner.isEmpty, !name.isEmpty else { return nil }
        return DiscoveredRepo(owner: owner, name: name)
    }
}
