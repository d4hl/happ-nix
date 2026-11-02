#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

REPO="Happ-proxy/happ-desktop"
ASSET="Happ.linux.x64.deb"
PKG_FILE="happ.nix"

PRERELEASE=0
PIN_VERSION=""
UPDATE_FLAKE=0
DO_BUILD=0
DRY_RUN=0
NOTES_FILE=""

usage() {
  cat <<'EOF'
Usage: scripts/update.sh [options]

Update happ.nix to the latest happ-desktop release.

Options:
  --prerelease       Include pre-releases
  --version VER      Use a specific release version
  --asset NAME       Release asset (default: Happ.linux.x64.deb)
  --update-flake     Update flake.lock
  --build            Build the package after updating
  --notes FILE       Write release notes to a Markdown file
  --dry-run          Show changes without modifying repository files
  -h, --help         Show this help
EOF
}

while (($#)); do
  case "$1" in
    --prerelease)   PRERELEASE=1; shift ;;
    --version)      PIN_VERSION="${2:?Missing version}"; shift 2 ;;
    --asset)        ASSET="${2:?Missing asset name}"; shift 2 ;;
    --update-flake) UPDATE_FLAKE=1; shift ;;
    --build)        DO_BUILD=1; shift ;;
    --notes)        NOTES_FILE="${2:?Missing file path}"; shift 2 ;;
    --dry-run)      DRY_RUN=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for cmd in curl jq nix; do
  command -v "$cmd" >/dev/null || {
    echo "Missing dependency: $cmd" >&2
    exit 1
  }
done

[[ -f "$PKG_FILE" ]] || {
  echo "Missing $PKG_FILE" >&2
  exit 1
}

api() {
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  local headers=(-H "Accept: application/vnd.github+json")

  [[ -n "$token" ]] && headers+=(-H "Authorization: Bearer $token")

  curl -fsSL "${headers[@]}" "$1"
}

current_version() {
  sed -n 's/^[[:space:]]*version = "\(.*\)";.*/\1/p' "$PKG_FILE" | head -n1
}

resolve_release() {
  local json

  if [[ -n "$PIN_VERSION" ]]; then
    json="$(api "https://api.github.com/repos/$REPO/releases/tags/$PIN_VERSION")"
  elif ((PRERELEASE)); then
    json="$(api "https://api.github.com/repos/$REPO/releases?per_page=20" |
      jq -c --arg asset "$ASSET" \
        'map(select(.assets | any(.name == $asset))) | .[0]')"
  else
    json="$(api "https://api.github.com/repos/$REPO/releases/latest")"
  fi

  if [[ -z "$json" || "$json" == "null" ]]; then
    echo "Could not find a release" >&2
    return 1
  fi

  if [[ -n "$NOTES_FILE" ]]; then
    jq -r '.body // ""' <<<"$json" > "$NOTES_FILE"
  fi

  jq -er '.tag_name' <<<"$json"
}

OLD_VERSION="$(current_version)"
[[ -n "$OLD_VERSION" ]] || {
  echo "Could not read version from $PKG_FILE" >&2
  exit 1
}

NEW_VERSION="$(resolve_release)"
URL="https://github.com/$REPO/releases/download/$NEW_VERSION/$ASSET"

echo "Current version : $OLD_VERSION"
echo "New version     : $NEW_VERSION"
echo "Asset           : $ASSET"
echo "Fetching hash   : $URL"

NEW_HASH="$(nix store prefetch-file --json --hash-type sha256 "$URL" | jq -er '.hash')"
OLD_HASH="$(sed -n 's/^[[:space:]]*sha256 = "\(.*\)";.*/\1/p' "$PKG_FILE" | head -n1)"

echo "New hash        : $NEW_HASH"

if [[ "$OLD_VERSION" == "$NEW_VERSION" &&
      "$OLD_HASH" == "$NEW_HASH" &&
      "$UPDATE_FLAKE" -eq 0 ]]; then
  echo "Already up to date."
  exit 0
fi

if ((DRY_RUN)); then
  echo "Dry run: skipping repository changes."
  exit 0
fi

if [[ "$OLD_VERSION" != "$NEW_VERSION" || "$OLD_HASH" != "$NEW_HASH" ]]; then
  sed -i \
    -e "s|^\([[:space:]]*version = \"\)[^\"]*\(\";\)|\1$NEW_VERSION\2|" \
    -e "s|^\([[:space:]]*sha256 = \"\)[^\"]*\(\";\)|\1$NEW_HASH\2|" \
    "$PKG_FILE"

  echo "Updated $PKG_FILE"
fi

if ((UPDATE_FLAKE)); then
  echo "Updating flake.lock..."
  nix flake update
fi

if ((DO_BUILD)); then
  echo "Building .#happ..."
  nix build --no-link .#happ
  echo "Build successful."
fi

echo "Done: $OLD_VERSION -> $NEW_VERSION"

