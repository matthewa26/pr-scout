#!/usr/bin/env bash
# Regenerate the committed man pages under `man/` from the current source.
# Run before cutting a release, or whenever a subcommand's `discussion` /
# option help text changes.

set -euo pipefail

cd "$(dirname "$0")/.."

DATE="${DATE:-$(date -u +%Y-%m-%d)}"

# Single-page output: `pr-scout.1` covers the top-level command and every
# subcommand in one file, which is the brew-friendly shape (`man1.install`
# expects one file per page) and what users typically want from `man pr-scout`.
swift package \
    --allow-writing-to-package-directory \
    generate-manual \
    --authors "Matthew Ayers<matthew@ayers.sh>" \
    --date "$DATE"

OUT=".build/plugins/GenerateManual/outputs/pr-scout"
if [[ ! -d "$OUT" ]]; then
    echo "Expected generated output in $OUT — plugin may have changed." >&2
    exit 1
fi

rm -f man/*.1
cp "$OUT"/*.1 man/

echo "Regenerated man pages in man/ (date: $DATE):"
ls man/
