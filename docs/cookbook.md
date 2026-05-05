# Cookbook

Practical recipes that lift directly. Most assume you've completed [Configuration](configuration.md) and have at least one profile auto-resolving from your working directory.

## tmux status bar — count of actionable PRs

```bash
# In ~/.tmux.conf
set -g status-right '#(pr-scout --format json 2>/dev/null | jq length) PRs '
```

Tmux refreshes status every 15 seconds by default. Adjust with `set -g status-interval 60` if you want it less frequent.

## Open every match in the browser

```bash
pr-scout --format json | jq -r '.[].url' | xargs open
```

On Linux, replace `open` with `xdg-open`.

## Interactive picker via `fzf`

```bash
pr-scout --format list \
  | fzf --ansi --header="Pick a PR" \
  | grep -oE 'https://[^ ]+' \
  | xargs gh pr view --web
```

Pipes the bullet list into fzf, extracts the URL from the selected line, opens it in the browser via `gh`.

## Slack webhook for stale collaborations

A scheduled cron / launchd job that pings you when collaborators have pushed to your PRs and you haven't reviewed since:

```bash
#!/usr/bin/env bash
set -euo pipefail
WEBHOOK="${SLACK_WEBHOOK?:set SLACK_WEBHOOK env var}"

MSG=$(pr-scout --format json \
  | jq -r '.[] | select(.category == "stale_pushed_by_others")
                | "• \(.repo)#\(.number) — \(.reason)\n  \(.url)"')

if [[ -z "$MSG" ]]; then
    exit 0   # nothing stale — don't ping
fi

PAYLOAD=$(jq -Rs --arg t "*Stale PRs needing your attention:*\n\n$MSG" '{text: $t}')
curl -sS -X POST -H 'Content-type: application/json' --data "$PAYLOAD" "$WEBHOOK"
```

## Inspect a teammate's queue

`--user` overrides the viewer login. The classifier still uses your local clones to decide which repos to query, but treats the supplied user as "you" for the categorization:

```bash
pr-scout --user some-teammate
```

Useful for triage handoffs ("what's on Alice's plate while she's on PTO?") or verifying that a specific PR is in someone's queue.

## Block a CI step on a clean queue

If you want CI to fail when you have outstanding review obligations:

```bash
test "$(pr-scout --format json | jq length)" = "0" || {
  echo "PR-scout queue isn't empty — clear it before merging"
  exit 1
}
```

## Filter to a single category

```bash
# Just my PRs with changes requested
pr-scout --format json | jq '.[] | select(.category == "changes_requested_mine")'

# Just other people's PRs awaiting my review
pr-scout --format json | jq '.[] | select(.category == "awaiting_my_review")'
```

## Daily summary email (cron + mailx)

```cron
# Every weekday at 9am, mail me the queue
0 9 * * 1-5  pr-scout --format list | mailx -s "PR queue $(date +%Y-%m-%d)" you@example.com
```

## Shell prompt integration

A minimal PS1 indicator showing PR count when not zero:

```bash
# In ~/.bashrc or ~/.zshrc
pr_scout_count() {
    local n
    n=$(pr-scout --format json 2>/dev/null | jq length 2>/dev/null) || return
    if [[ "$n" -gt 0 ]]; then
        printf ' [%d PR%s]' "$n" "$([[ $n -ne 1 ]] && echo s)"
    fi
}

# Bash
PS1='$(pr_scout_count) \u@\h \w \$ '

# Zsh (use precmd hook for cleanliness)
precmd() { PROMPT='$(pr_scout_count) %n@%m %~ %# ' }
```

Caching `pr_scout_count`'s output for a minute or two with `mktemp` is recommended if you have many repos.

## Per-context profile (autoswitching)

Profiles auto-resolve from CWD via the `directories` field in config. Drop into the right tree and pr-scout picks the right profile automatically — no flags needed:

```bash
cd ~/work/some-repo  && pr-scout      # uses 'work' profile
cd ~/projects/foo    && pr-scout      # uses 'personal' profile
cd ~/oss/random-fork && pr-scout      # uses 'oss' profile
```

See [Configuration > Profile auto-resolution](configuration.md#profile-auto-resolution).

## Periodic check (no UI)

A cron / launchd job that just checks count and pages you if it crosses a threshold:

```bash
#!/usr/bin/env bash
THRESHOLD=10
COUNT=$(pr-scout --format json | jq length)
if (( COUNT > THRESHOLD )); then
    osascript -e "display notification \"$COUNT PRs in queue\" with title \"pr-scout\""
fi
```

(macOS notification example. Linux: use `notify-send`.)

## Running from a non-CWD directory in scripts

```bash
# Don't rely on CWD; pin it
pr-scout --directory ~/work --profile work --format json
```

Useful in cron jobs, CI, or anywhere the active working directory is unpredictable.

## More

If you build something nice with pr-scout, [open a PR](https://github.com/matthewa26/pr-scout/pulls) adding it here. Real-world recipes are the most useful section.
