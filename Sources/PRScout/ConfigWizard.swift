import Foundation

/// Interactive `pr-scout config` flow. Prompts the user through profile
/// setup, optionally auto-detecting directories and owners from local
/// clones, and writes the resulting JSON config.
struct ConfigWizard {
    let io: PromptIO
    let configPath: URL
    let viewerLoginProvider: () -> String?
    let ownerDetector: ([String]) -> [String]
    let saveAction: (Config, URL) throws -> Void

    init(
        io: PromptIO = StandardPromptIO(),
        configPath: URL? = nil,
        viewerLoginProvider: @escaping () -> String? = { try? GH.viewerLogin() },
        ownerDetector: @escaping ([String]) -> [String] = ConfigWizard.defaultOwnerDetector,
        saveAction: @escaping (Config, URL) throws -> Void = { try ConfigLoader.save($0, to: $1) }
    ) {
        self.io = io
        self.configPath = configPath ?? ConfigLoader.defaultPath
        self.viewerLoginProvider = viewerLoginProvider
        self.ownerDetector = ownerDetector
        self.saveAction = saveAction
    }

    func run() throws {
        printBanner()

        let existing = try? ConfigLoader.load(at: configPath)
        if let existing, !existing.profiles.isEmpty {
            io.writeLine("")
            io.writeLine("Existing config at \(configPath.path) (\(existing.profiles.count) profile\(existing.profiles.count == 1 ? "" : "s")).")
            let choice = io.choose("What would you like to do?", options: [
                "Replace it with a fresh config",
                "Cancel and keep the existing config",
            ])
            if choice == 1 {
                io.writeLine("Cancelled — nothing changed.")
                return
            }
        }

        var profiles: [String: Profile] = [:]
        var profileOrder: [String] = []
        var defaultProfile: String?

        repeat {
            io.writeLine("")
            io.writeLine(profiles.isEmpty
                ? "── Setting up your first profile ──"
                : "── Adding another profile ──")
            let result = buildProfile(existingNames: Set(profiles.keys))
            profiles[result.name] = result.profile
            profileOrder.append(result.name)
            if profiles.count == 1 { defaultProfile = result.name }
        } while io.confirm("Add another profile?", default: false)

        if profiles.count > 1 {
            let idx = io.choose(
                "Which profile is the default (used when CWD doesn't match any directory)?",
                options: profileOrder,
                default: 0
            )
            defaultProfile = profileOrder[idx]
        }

        let config = Config(defaultProfile: defaultProfile, profiles: profiles)
        let preview = (try? renderJSON(config)) ?? "<unrenderable>"
        io.writeLine("")
        io.writeLine("── Config preview ──")
        io.writeLine(preview)
        io.writeLine("")
        if io.confirm("Save to \(configPath.path)?", default: true) {
            try saveAction(config, configPath)
            io.writeLine("Saved.")
        } else {
            io.writeLine("Discarded — nothing written.")
        }
    }

    // MARK: - Internals

    private func printBanner() {
        io.writeLine("pr-scout config — interactive setup")
        io.writeLine("(press Enter to accept any [bracketed] default)")
    }

    func buildProfile(existingNames: Set<String>) -> (name: String, profile: Profile) {
        let name = io.prompt(
            "Profile name (e.g. work / personal / oss)",
            default: existingNames.isEmpty ? "personal" : nil,
            validator: { value in
                if value.isEmpty { return "name is required" }
                if existingNames.contains(value) { return "name '\(value)' is already used in this config" }
                return nil
            }
        )

        io.writeLine("")
        io.writeLine("Which directories should auto-resolve to this profile?")
        io.writeLine("(comma-separated; ~ is expanded to your home directory)")
        let dirsRaw = io.prompt("Directories", default: defaultDirectorySuggestion(for: name))
        let directories = parseCSV(dirsRaw)

        let suggestedOwners = ownerDetector(directories)

        io.writeLine("")
        let detectedUser = viewerLoginProvider()
        let githubUser: String? = {
            if let u = detectedUser, !u.isEmpty {
                io.writeLine("Detected GitHub user: @\(u)")
                if io.confirm("Use that?", default: true) { return nil }
            } else {
                io.writeLine("Couldn't detect a GitHub user (is `gh auth login` complete?).")
            }
            let answer = io.prompt("GitHub username", default: detectedUser)
            return answer.isEmpty ? nil : answer
        }()

        io.writeLine("")
        io.writeLine("Restrict scanning to specific GitHub owners?")
        io.writeLine("(useful when your scan dirs also contain OSS clones; comma-separated, blank = no restriction)")
        let ownersDefault = suggestedOwners.isEmpty ? "" : suggestedOwners.joined(separator: ", ")
        let ownersRaw = io.prompt("Owners", default: ownersDefault.isEmpty ? nil : ownersDefault)
        let owners = parseCSV(ownersRaw)

        io.writeLine("")
        let categoryOptions = CategoryKind.allCases
        let categoryDescriptions = categoryOptions.map { "\($0.rawValue) — \($0.displayName)" }
        let defaultPicks = Set(categoryOptions.indices.filter {
            CategoryKind.defaultCatalog.contains(categoryOptions[$0])
        })
        let chosen = io.multiChoose(
            "Which categories should this profile show?",
            options: categoryDescriptions,
            defaults: defaultPicks
        )
        let chosenCategories = chosen.sorted().map { categoryOptions[$0] }

        let profile = Profile(
            directories: directories.isEmpty ? nil : directories,
            githubUser: githubUser,
            categories: chosenCategories.isEmpty ? nil : chosenCategories,
            scope: nil,
            ignoreAuthors: nil,
            owners: owners.isEmpty ? nil : owners,
            excludeRepos: nil
        )

        return (name, profile)
    }

    private func defaultDirectorySuggestion(for profileName: String) -> String {
        switch profileName.lowercased() {
        case "work":     return "~/work"
        case "personal": return "~/projects"
        case "oss":      return "~/oss"
        default:         return "~/projects"
        }
    }

    private func parseCSV(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func renderJSON(_ config: Config) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(data: try encoder.encode(config), encoding: .utf8) ?? ""
    }

    static func defaultOwnerDetector(_ directories: [String]) -> [String] {
        let urls = directories.map { URL(fileURLWithPath: ConfigLoader.expandTilde($0)) }
        let repos = RepoDiscovery.discover(in: urls)
        return Set(repos.map(\.owner)).sorted()
    }
}
