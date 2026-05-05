# Installation

## macOS — Homebrew (recommended)

```bash
brew install matthewa26/tap/pr-scout
```

This taps `matthewa26/homebrew-tap` (auto-discovered from the shorthand) and installs `pr-scout` plus its `gh` runtime dependency in one step. Also installs the man page (`man pr-scout`).

To upgrade later:

```bash
brew update
brew upgrade pr-scout
```

To uninstall:

```bash
brew uninstall pr-scout
brew untap matthewa26/tap         # optional — removes the tap entirely
```

## Any platform — from source

Requires the Swift toolchain (Swift 5.9 or later). On macOS, that comes with Xcode or the Command Line Tools (`xcode-select --install`). On Linux, install from [swift.org](https://swift.org/download/).

```bash
git clone https://github.com/matthewa26/pr-scout.git
cd pr-scout
swift build -c release
install .build/release/pr-scout /usr/local/bin/
```

Runtime cold start is <50ms after the one-time build.

## Prerequisite: GitHub CLI (`gh`)

`pr-scout` shells out to [`gh`](https://cli.github.com) for every GitHub query — it doesn't manage tokens itself.

The Homebrew formula installs `gh` automatically. From-source installs need it separately.

### macOS

```bash
brew install gh
```

### Debian / Ubuntu

```bash
(type -p wget >/dev/null || sudo apt install wget -y) \
  && sudo mkdir -p -m 755 /etc/apt/keyrings \
  && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && sudo apt update && sudo apt install gh -y
```

### Fedora / RHEL / CentOS

```bash
sudo dnf install gh
```

### Arch

```bash
sudo pacman -S github-cli
```

### Alpine

```bash
sudo apk add github-cli
```

### Other Linux

See the [official `gh` install docs](https://github.com/cli/cli/blob/trunk/docs/install_linux.md). Flatpak, Snap, Conda, and Webi options are all viable.

If `gh` is missing when you run `pr-scout`, the tool prints a platform-tailored install hint and exits with status 127.

### One-time `gh` authentication

```bash
gh auth login
```

Pick GitHub.com or your Enterprise host, log in via browser or token, and you're done. `pr-scout` reuses these credentials on every invocation.

## Verifying

```bash
pr-scout --version           # prints the installed version
pr-scout --help              # top-level help
gh auth status               # confirms gh is authenticated
```

If any of those fail, see [Troubleshooting](troubleshooting.md).
