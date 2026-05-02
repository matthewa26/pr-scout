import Foundation

enum InstallHint {
    static func ghMissingMessage() -> String {
        let header = "pr-scout requires the GitHub CLI (`gh`), which was not found on PATH."
        let footer = "After installing, run `gh auth login` to authenticate."
        let body: String

        #if os(macOS)
        body = """
        Install on macOS:
          brew install gh

        Or via MacPorts:
          sudo port install gh
        """
        #elseif os(Linux)
        body = linuxInstructions()
        #else
        body = "See https://github.com/cli/cli#installation for install instructions."
        #endif

        return [header, "", body, "", footer].joined(separator: "\n")
    }

    #if os(Linux)
    private static func linuxInstructions() -> String {
        let distro = detectDistro()
        switch distro {
        case .debian:
            return """
            Install on Debian/Ubuntu:
              # Add GitHub CLI's official apt repo (recommended):
              (type -p wget >/dev/null || sudo apt install wget -y) \\
                && sudo mkdir -p -m 755 /etc/apt/keyrings \\
                && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \\
                  | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \\
                && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \\
                && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \\
                  | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \\
                && sudo apt update && sudo apt install gh -y
            """
        case .fedora:
            return """
            Install on Fedora/RHEL/CentOS:
              sudo dnf install gh
            """
        case .arch:
            return """
            Install on Arch Linux:
              sudo pacman -S github-cli
            """
        case .alpine:
            return """
            Install on Alpine:
              sudo apk add github-cli
            """
        case .unknown:
            return """
            Generic Linux options:
              # Flatpak:    flatpak install flathub io.github.cli.cli
              # Snap:       sudo snap install gh
              # Conda:      conda install gh -c conda-forge
              # Webi:       curl -sS https://webi.sh/gh | sh

            Or see https://github.com/cli/cli/blob/trunk/docs/install_linux.md
            """
        }
    }

    private enum Distro { case debian, fedora, arch, alpine, unknown }

    private static func detectDistro() -> Distro {
        guard let data = try? String(contentsOfFile: "/etc/os-release", encoding: .utf8) else {
            return .unknown
        }
        let lower = data.lowercased()
        if lower.contains("id_like=debian") || lower.contains("id=debian") || lower.contains("id=ubuntu") {
            return .debian
        }
        if lower.contains("id=fedora") || lower.contains("id_like=\"rhel") || lower.contains("id_like=fedora") {
            return .fedora
        }
        if lower.contains("id=arch") || lower.contains("id_like=arch") {
            return .arch
        }
        if lower.contains("id=alpine") {
            return .alpine
        }
        return .unknown
    }
    #endif
}
