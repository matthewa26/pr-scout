import ArgumentParser
import Foundation

struct PRScout: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pr-scout",
        abstract: "Scan GitHub PRs across local repos and surface ones that need your attention.",
        version: "0.1.1",
        subcommands: [List.self, Init.self],
        defaultSubcommand: List.self
    )
}

extension PRScout {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List actionable PRs in the current directory's repos."
        )

        @Option(name: [.short, .long], help: "Profile name to use (overrides directory-based resolution).")
        var profile: String?

        @Option(name: [.short, .long], help: "Directory to scan (defaults to CWD).")
        var directory: String?

        @Option(name: [.long], help: "Override the GitHub user (defaults to `gh api user`).")
        var user: String?

        @Option(name: [.long], help: "Override config file path.")
        var config: String?

        @Option(name: [.short, .long], help: "Output format: json | table | list | pretty.")
        var format: OutputFormat = .pretty

        @Flag(name: .long, help: "Verbose progress output to stderr.")
        var verbose: Bool = false

        func run() throws {
            // 1. Verify gh
            if GH.locate() == nil {
                FileHandle.standardError.write(Data((InstallHint.ghMissingMessage() + "\n").utf8))
                throw ExitCode(127)
            }

            // 2. Load config + resolve profile
            let configURL = config.map { URL(fileURLWithPath: ConfigLoader.expandTilde($0)) }
            let cfg = (try? ConfigLoader.load(at: configURL)) ?? .empty

            let cwd: URL = {
                if let dir = directory {
                    return URL(fileURLWithPath: ConfigLoader.expandTilde(dir))
                }
                return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            }()

            let resolved = ConfigLoader.resolveProfile(cfg, cwd: cwd, override: profile)
            let profileName = resolved?.name
            let prof = resolved?.profile ?? Profile(directories: nil, githubUser: nil, categories: nil, scope: nil, ignoreAuthors: nil)

            // 3. Resolve viewer
            let viewer: String
            if let u = user {
                viewer = u
            } else if let u = prof.githubUser {
                viewer = u
            } else {
                viewer = try GH.viewerLogin()
            }

            // 4. Discover repos
            let roots: [URL]
            if let dirs = prof.directories, !dirs.isEmpty, profile != nil || directory == nil {
                // Use profile directories if a profile was resolved by config.
                roots = dirs.map { URL(fileURLWithPath: ConfigLoader.expandTilde($0)) }
            } else {
                roots = [cwd]
            }
            if verbose {
                stderr("Scanning roots: \(roots.map(\.path).joined(separator: ", "))")
            }
            var repos = RepoDiscovery.discover(in: roots)
            if let owners = prof.owners, !owners.isEmpty {
                let allow = Set(owners.map { $0.lowercased() })
                repos = repos.filter { allow.contains($0.owner.lowercased()) }
            }
            if let exclude = prof.excludeRepos, !exclude.isEmpty {
                let block = Set(exclude.map { $0.lowercased() })
                repos = repos.filter { !block.contains($0.slug.lowercased()) }
            }
            if verbose {
                stderr("Discovered \(repos.count) repos: \(repos.map(\.slug).joined(separator: ", "))")
            }
            if repos.isEmpty {
                FileHandle.standardError.write(Data("No GitHub repos found in scan roots.\n".utf8))
                return
            }

            // 5. Decide query strategy + collect PRs
            let scope = prof.scope ?? .currentDirectoryRepos
            let ignoreAuthors = Set((prof.ignoreAuthors ?? defaultBotAuthors).map { $0.lowercased() })

            var summaries: [(DiscoveredRepo, PRSummary)] = []
            switch scope {
            case .currentDirectoryRepos:
                for repo in repos {
                    if verbose { stderr("Listing PRs in \(repo.slug)…") }
                    let list: [PRSummary]
                    do {
                        list = try GH.listOpenPRs(repo: repo)
                    } catch {
                        stderr("warning: skipping \(repo.slug): \(error)")
                        continue
                    }
                    for pr in list { summaries.append((repo, pr)) }
                }
            case .discoveredOrgs:
                let owners = Set(repos.map(\.owner))
                for owner in owners {
                    if verbose { stderr("Searching open PRs in @\(owner)…") }
                    do {
                        let list = try GH.searchOrgPRs(owner: owner)
                        for (repo, pr) in list { summaries.append((repo, pr)) }
                    } catch {
                        stderr("warning: skipping owner \(owner): \(error)")
                    }
                }
            }

            summaries = filterPRSummaries(summaries, ignoreAuthors: ignoreAuthors)

            // 6. Fetch detail for the surviving PRs and classify
            let categories = prof.categories ?? CategoryKind.defaultCatalog
            var details: [(DiscoveredRepo, PRDetail)] = []
            for (repo, summary) in summaries {
                if verbose { stderr("Fetching detail for \(repo.slug)#\(summary.number)…") }
                do {
                    let d = try GH.viewPR(repo: repo, number: summary.number)
                    details.append((repo, d))
                } catch {
                    stderr("warning: skipping \(repo.slug)#\(summary.number): \(error)")
                }
            }

            let classified = Classifier.classify(prs: details, viewer: viewer, categories: categories)

            // 7. Render
            print(Renderer.render(classified, format: format, viewer: viewer, profileName: profileName))
        }
    }

    struct Init: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "init",
            abstract: "Write a starter config file."
        )

        @Option(name: [.long], help: "Output path (defaults to ~/.config/pr-scout/config.json).")
        var path: String?

        @Flag(name: .long, help: "Overwrite an existing config.")
        var force: Bool = false

        func run() throws {
            let url = path.map { URL(fileURLWithPath: ConfigLoader.expandTilde($0)) } ?? ConfigLoader.defaultPath
            if FileManager.default.fileExists(atPath: url.path), !force {
                FileHandle.standardError.write(Data("Refusing to overwrite \(url.path). Pass --force to replace.\n".utf8))
                throw ExitCode(1)
            }
            let starter = Config(
                defaultProfile: "personal",
                profiles: [
                    "personal": Profile(
                        directories: ["~/projects"],
                        githubUser: nil,
                        categories: CategoryKind.defaultCatalog,
                        scope: .currentDirectoryRepos,
                        ignoreAuthors: defaultBotAuthors,
                        owners: nil,
                        excludeRepos: nil
                    ),
                ]
            )
            try ConfigLoader.save(starter, to: url)
            print("Wrote \(url.path)")
        }
    }
}

/// Drop drafts and any PR whose author login is in `ignoreAuthors`. Bots are
/// only filtered when their login appears in `ignoreAuthors` — `is_bot` flags
/// from the GitHub API are deliberately ignored so users can opt in to seeing
/// Dependabot/Renovate/etc. by editing their config.
func filterPRSummaries(
    _ summaries: [(DiscoveredRepo, PRSummary)],
    ignoreAuthors: Set<String>
) -> [(DiscoveredRepo, PRSummary)] {
    summaries.filter { _, pr in
        !pr.isDraft && !ignoreAuthors.contains(pr.author.login.lowercased())
    }
}

let defaultBotAuthors: [String] = [
    "dependabot", "dependabot[bot]",
    "renovate", "renovate[bot]",
    "github-actions", "github-actions[bot]",
    "claude-code", "claude-code[bot]",
]

func stderr(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
}

PRScout.main()

// MARK: - Org-wide search helper

extension GH {
    static func searchOrgPRs(owner: String) throws -> [(DiscoveredRepo, PRSummary)] {
        // gh search prs returns a different shape than `gh pr list` — repository
        // is an object, and there's no headRefOid in the response. We map it.
        struct SearchHit: Decodable {
            let number: Int
            let title: String
            let author: GHActor
            let createdAt: Date
            let updatedAt: Date
            let isDraft: Bool
            let url: String
            let repository: Repo
            struct Repo: Decodable {
                let nameWithOwner: String
            }
        }
        let fields = "number,title,author,createdAt,updatedAt,isDraft,url,repository"
        let hits = try GH.runJSON(
            ["search", "prs", "--owner", owner, "--state", "open", "--limit", "200", "--json", fields],
            as: [SearchHit].self
        )
        return hits.compactMap { hit in
            let parts = hit.repository.nameWithOwner.split(separator: "/", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let repo = DiscoveredRepo(owner: String(parts[0]), name: String(parts[1]))
            let summary = PRSummary(
                number: hit.number,
                title: hit.title,
                author: hit.author,
                createdAt: hit.createdAt,
                updatedAt: hit.updatedAt,
                isDraft: hit.isDraft,
                reviewDecision: nil,
                url: hit.url,
                headRefOid: nil
            )
            return (repo, summary)
        }
    }
}
