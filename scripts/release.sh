#!/bin/bash
# Builds the zip, then creates a GitHub release and uploads the artifact.
# Requires: GITHUB_TOKEN env var.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
OWNER="icrefin"
REPO="dockglance"
TOKEN="${GITHUB_TOKEN:?set GITHUB_TOKEN}"
API="https://github.com/api/v5"

echo "==> building release artifact"
( cd "$ROOT" && ./scripts/make-app.sh )

ZIP="$ROOT/dist/DockGlance-$VERSION.zip"

echo "==> creating release v$VERSION"
RELEASE_JSON="$(
    curl -fsS -X POST -H "Authorization: token $TOKEN" "$API/repos/$OWNER/$REPO/releases" \
        -d "tag_name=v$VERSION" \
        -d "target_commitish=main" \
        -d "name=v$VERSION" \
        -d "body=Release v$VERSION of the dock-side metrics widget."
)"
RELEASE_ID="$(echo "$RELEASE_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
echo "release id: $RELEASE_ID"

echo "==> uploading $ZIP"
curl -fs -X POST -H "Authorization: token $TOKEN" \
    "$API/repos/$OWNER/$REPO/releases/$RELEASE_ID/attach_files" \
    -F "file=@$ZIP" >/dev/null
echo "==> done: https://github.com/$OWNER/$REPO/releases/download/v$VERSION/DockGlance-$VERSION.zip"