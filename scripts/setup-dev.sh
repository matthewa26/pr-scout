#!/usr/bin/env bash
# One-time developer setup: installs git hooks and verifies the build.
# Run after cloning the repository.

set -euo pipefail

cd "$(dirname "$0")/.."

git config core.hooksPath .githooks
chmod +x .githooks/*

echo "Hooks path set to .githooks/"
echo "Verifying build..."
swift build

echo
echo "Setup complete. The pre-commit hook will run 'swift test' on every commit."
