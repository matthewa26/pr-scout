import ArgumentParser
import Foundation

struct PRScout: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pr-scout",
        abstract: "Scan GitHub PRs across local repos and surface ones that need your attention.",
        usage: """
        pr-scout [list] [<options>]
        pr-scout config [--path <path>]
        pr-scout init [--path <path>] [--force]
        """,
        discussion: """
        pr-scout walks the directories registered in your active profile, finds local Git
        clones via their `.git/config` origin URLs, queries open PRs from each via the GitHub
        CLI (`gh`), and classifies them into a small catalog of categories targeting common
        review attention patterns:

          • Your PRs that have changes requested
          • Others' PRs awaiting your review
          • Others' PRs that have new commits since your last review
          • Your PRs where someone else pushed and you haven't reviewed since
          • Your PRs that are approved and ready to merge

        Profile-based config auto-resolves from the current working directory: any path
        beneath a registered directory uses that profile (longest prefix wins). Each profile
        can scope to specific GitHub owners, customize the category catalog, and override
        the GitHub user identity.

        First-time setup is interactive — run `pr-scout config`. For non-interactive
        scaffolding, use `pr-scout init`.

        Authentication is delegated to `gh`. Run `gh auth login` once and pr-scout will
        reuse those credentials.

        SEE ALSO
          The pr-scout(1) man page, https://github.com/matthewa26/pr-scout/tree/main/docs,
          and `pr-scout <subcommand> --help` for per-subcommand options.
        """,
        version: "0.2.1",
        subcommands: [List.self, ConfigCommand.self, Init.self],
        defaultSubcommand: List.self
    )
}

extension PRScout {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List actionable PRs in the current directory's repos.",
            discussion: """
            Default subcommand — `pr-scout` with no subcommand runs `list`.

            The active profile is resolved by matching the current working directory (or
            --directory) against each profile's `directories` prefix; the longest matching
            prefix wins. With no match, falls back to `defaultProfile`. With no config at
            all, scans the current directory.

            For each registered directory, repositories are discovered via `.git/config`
            origin URLs. The viewer's GitHub login defaults to `gh api user`; override
            with --user or in profile config. PRs are classified into the categories
            enabled in the profile (see the `categories` doc for the full catalog).

            Output formats:
              json   — stable schema for scripts; pipe through jq.
              table  — aligned ASCII columns; good for at-a-glance scanning.
              list   — plain bullets, no ANSI; safe for piping or logs.
              pretty — ANSI colors; falls back to `list` when stdout isn't a TTY.

            Use --verbose to see the full scan trace on stderr.
            """
        )

        @Option(
            name: [.short, .long],
            help: ArgumentHelp(
                "Profile name to use (overrides directory-based resolution).",
                discussion: "Useful when running from outside any registered directory but you want a specific profile applied — e.g. CI scripts or scheduled jobs."
            )
        )
        var profile: String?

        @Option(
            name: [.short, .long],
            help: ArgumentHelp(
                "Directory to scan (defaults to CWD).",
                discussion: "Profile auto-resolution still applies — the supplied path is matched against each profile's `directories` prefix."
            )
        )
        var directory: String?

        @Option(
            name: [.long],
            help: ArgumentHelp(
                "Override the GitHub user (defaults to `gh api user`).",
                discussion: "Useful for inspecting another reviewer's queue, running against a different GitHub account than gh is logged into, or impersonation in scripts."
            )
        )
        var user: String?

        @Option(
            name: [.long],
            help: ArgumentHelp(
                "Override config file path.",
                discussion: "Defaults to ~/.config/pr-scout/config.json (or $XDG_CONFIG_HOME/pr-scout/config.json if set)."
            )
        )
        var config: String?

        @Option(
            name: [.short, .long],
            help: ArgumentHelp(
                "Output format: json | table | list | pretty.",
                discussion: "`pretty` is the default and auto-falls-back to `list` when stdout isn't a TTY, so piping always produces clean output."
            )
        )
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

            summaries = deduplicateSummariesByURL(summaries)
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
            abstract: "Write a starter config file (non-interactive).",
            discussion: """
            Writes a single-profile starter config to ~/.config/pr-scout/config.json. The
            generated profile is named `personal`, scans `~/projects`, enables the default
            category catalog, and lists the standard bot logins in `ignoreAuthors`.

            For interactive setup that walks through profile creation step-by-step
            (with auto-detection of directories, GitHub user, and owners), use
            `pr-scout config` instead.
            """
        )

        @Option(
            name: [.long],
            help: ArgumentHelp(
                "Output path (defaults to ~/.config/pr-scout/config.json).",
                discussion: "Parent directory is created if it doesn't exist. Path is expanded for ~ and resolved against the current process's working directory."
            )
        )
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

    struct ConfigCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "config",
            abstract: "Walk through interactive setup to build a config from scratch.",
            discussion: """
            Walks through profile creation step-by-step:

              1. Profile name (validated for non-empty + uniqueness).
              2. Directories the profile auto-resolves from (with sensible defaults
                 per profile name — `work` → ~/work, `personal` → ~/projects, etc.).
              3. GitHub user — auto-detected via `gh api user`, with confirm/override.
              4. Owners allowlist — auto-suggested from the GitHub owners of local
                 clones found in the chosen directories.
              5. Categories to enable — multi-select from the catalog with the
                 default catalog pre-checked.
              6. Add another profile? Repeat from step 1, or finish.
              7. (When >1 profile) which profile is the default?
              8. JSON preview, then confirm before save.

            If a config already exists at the target path, the wizard offers
            replace-or-cancel up front — it doesn't merge or edit in place.
            """
        )

        @Option(
            name: [.long],
            help: ArgumentHelp(
                "Output path (defaults to ~/.config/pr-scout/config.json).",
                discussion: "Useful for testing alternate configs or scripting setup against a known location."
            )
        )
        var path: String?

        func run() throws {
            let url = path.map { URL(fileURLWithPath: ConfigLoader.expandTilde($0)) }
                ?? ConfigLoader.defaultPath
            let wizard = ConfigWizard(configPath: url)
            try wizard.run()
        }
    }
}

/// Collapse summaries that share a canonical URL. Triggered when two local
/// clones point at different owners that GitHub redirects to the same repo
/// (e.g. after a repo rename) — `gh pr list` returns the same PRs from each,
/// and the PR URL is already canonical, so identical URLs are duplicates.
func deduplicateSummariesByURL(_ summaries: [(DiscoveredRepo, PRSummary)]) -> [(DiscoveredRepo, PRSummary)] {
    var seen = Set<String>()
    return summaries.filter { _, pr in seen.insert(pr.url).inserted }
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
