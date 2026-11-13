#!/bin/bash
# Updates Rep Coach to the latest version, even when Xcode has edited the project file.
#
#   ./scripts/update.sh
#
# Xcode sometimes writes into ExerciseTracker.xcodeproj (e.g. when a Team is picked under Signing &
# Capabilities), and then a plain `git pull` refuses to run. This script keeps your Team ID in
# Config/Local.xcconfig (which updates never touch), sets Xcode's edits aside with `git stash`
# (nothing is deleted; `git stash list` shows them), then pulls.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_DIR=ExerciseTracker.xcodeproj
PROJECT=$PROJECT_DIR/project.pbxproj
LOCAL=Config/Local.xcconfig

if pgrep -xq Xcode; then
    echo "Tip: quit Xcode first (⌘Q) so it doesn't write to the project while it's being updated."
fi

if ! git diff --quiet -- "$PROJECT_DIR"; then
    team=$(git diff -- "$PROJECT" | sed -n 's/^+.*DEVELOPMENT_TEAM = \([A-Z0-9]\{10\}\);.*/\1/p' | head -n 1)
    if [ -n "$team" ]; then
        if [ ! -f "$LOCAL" ]; then
            cp Config/Local.xcconfig.example "$LOCAL"
        fi
        if ! grep -q "^DEVELOPMENT_TEAM = [A-Z0-9]\{10\}" "$LOCAL" || grep -q "^DEVELOPMENT_TEAM = ABCDE12345" "$LOCAL"; then
            sed -i '' "s/^DEVELOPMENT_TEAM = .*/DEVELOPMENT_TEAM = $team/" "$LOCAL"
            grep -q "^DEVELOPMENT_TEAM = $team" "$LOCAL" || echo "DEVELOPMENT_TEAM = $team" >> "$LOCAL"
            echo "Saved your Team ID ($team) in $LOCAL."
        fi
    fi
    git stash push -m "Xcode project edits before update $(date '+%Y-%m-%d %H:%M')" -- "$PROJECT_DIR" >/dev/null
    echo "Set Xcode's edits to the project aside (see: git stash list)."
fi

git pull --ff-only
echo "Up to date. Open ExerciseTracker.xcodeproj and run both apps again."
