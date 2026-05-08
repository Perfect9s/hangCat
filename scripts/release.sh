#!/usr/bin/env bash
# One-shot release: build the .app, commit any pending changes, tag, push,
# and (if `gh` is installed) attach the .zip to a GitHub release.
#
# Usage:
#   ./scripts/release.sh <version> [commit-message]
#
# Examples:
#   ./scripts/release.sh 0.1.1 "fix cat sometimes not appearing"
#   ./scripts/release.sh 0.2.0
#
# What it does, in order:
#   1. Validates the version string (x.y.z).
#   2. Runs scripts/make-app.sh <version> to produce build/hangCat.app.zip.
#   3. If the working tree has uncommitted changes, commits them.
#   4. Tags v<version> (force, so re-running with the same version retags HEAD).
#   5. Pushes commits + tag to origin.
#   6. If `gh` is installed and authenticated:
#        - Creates the release if it doesn't exist (with the .zip attached)
#        - Otherwise re-uploads the .zip to the existing release (--clobber)
#      Otherwise prints the URL/instructions for doing it in the browser.

set -euo pipefail

VERSION="${1:-}"
MSG="${2:-Release v$VERSION}"

if [[ -z "$VERSION" ]]; then
    cat <<EOF
Usage: $(basename "$0") <version> [commit-message]

Examples:
    $(basename "$0") 0.1.1 "fix cat sometimes not appearing"
    $(basename "$0") 0.2.0
EOF
    exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: version should be x.y.z (got: $VERSION)" >&2
    exit 1
fi

cd "$(dirname "$0")/.."

TAG="v$VERSION"
ARTIFACT="build/hangCat.app.zip"

# ---- 1. Build ----
echo "==> [1/5] Building hangCat.app v$VERSION"
./scripts/make-app.sh "$VERSION"

if [[ ! -f "$ARTIFACT" ]]; then
    echo "ERROR: $ARTIFACT was not produced — check make-app.sh output above." >&2
    exit 1
fi

# ---- 2. Commit pending changes ----
if [[ -n "$(git status --porcelain)" ]]; then
    echo "==> [2/5] Committing pending changes"
    git add -A
    git commit -m "$MSG"
else
    echo "==> [2/5] Working tree clean — nothing to commit."
fi

# ---- 3. Tag ----
echo "==> [3/5] Tagging $TAG"
git tag -f -a "$TAG" -m "$TAG"

# ---- 4. Push ----
if ! git remote get-url origin >/dev/null 2>&1; then
    cat <<EOF >&2

ERROR: No 'origin' remote configured.

Set one up first, e.g.:
    git remote add origin https://github.com/<username>/hangCat.git

Then rerun:
    $(basename "$0") $VERSION

EOF
    exit 1
fi

echo "==> [4/5] Pushing to origin"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
git push origin "$BRANCH"
git push origin "$TAG" --force

# ---- 5. GitHub release ----
echo "==> [5/5] GitHub release"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if gh release view "$TAG" >/dev/null 2>&1; then
        echo "    release $TAG already exists — re-uploading artifact"
        gh release upload "$TAG" "$ARTIFACT" --clobber
    else
        echo "    creating release $TAG"
        gh release create "$TAG" "$ARTIFACT" \
            --title "$TAG" \
            --notes "$MSG"
    fi
    URL="$(gh release view "$TAG" --json url -q .url 2>/dev/null || true)"
    [[ -n "$URL" ]] && echo "    $URL"
    echo
    echo "Done."
else
    REMOTE_URL="$(git remote get-url origin)"
    REPO_URL="$(echo "$REMOTE_URL" \
        | sed -E 's|^git@github.com:|https://github.com/|; s|\.git$||')"
    cat <<EOF

   gh CLI not installed / not authenticated — finish in the browser:

   1. Open: ${REPO_URL}/releases/new?tag=${TAG}
   2. Title: $TAG
   3. Notes: $MSG
   4. Drag this file onto the page:
        $(pwd)/$ARTIFACT
   5. Click "Publish release".

   To automate this on next release:
        brew install gh
        gh auth login
        ./scripts/release.sh $VERSION

EOF
fi
