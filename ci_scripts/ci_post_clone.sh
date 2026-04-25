#!/bin/sh

# Xcode Cloud post-clone script
# Runs after repo clone, before xcodebuild.
# Regenerates .xcodeproj so source changes stay in sync.

set -e

echo "ci_post_clone: regenerating xcodeproj from project.yml..."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "ci_post_clone: xcodegen not found, installing via Homebrew..."
    brew install xcodegen
fi

xcodegen
echo "ci_post_clone: done."
