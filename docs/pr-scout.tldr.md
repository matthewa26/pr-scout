# pr-scout

> Scan GitHub PRs across local repository clones and surface only the ones that need your attention.
> Built on top of `gh`. Profile-based config auto-resolves from the working directory.
> More information: <https://github.com/matthewa26/pr-scout>.

- List actionable PRs in the current directory's repos:

`pr-scout`

- Run interactive setup to build a config from scratch:

`pr-scout config`

- Write a non-interactive starter config to the default path:

`pr-scout init`

- Scan a specific directory and emit machine-readable JSON:

`pr-scout list --directory {{path/to/repos}} --format json`

- Use a named profile (overrides directory-based auto-resolution):

`pr-scout list --profile {{work}}`

- Impersonate another GitHub user (e.g. inspect their review queue):

`pr-scout list --user {{some-handle}}`

- Verbose progress output to stderr (full scan trace):

`pr-scout list --verbose`

- Show help for a specific subcommand:

`pr-scout {{list|config|init}} --help`
