#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

REPO="Happ-proxy/happ-desktop"
ASSET="Happ.linux.x64.deb"
PKG_FILE="happ.nix"

# Selection mode:
#   stable      - highest semver among non-prerelease releases (default)
#   prerelease  - highest semver among all releases
#   latest      - trust the upstream "Latest" marker (upstream marks stale
#                 releases as latest, so this is kept only for compatibility)
MODE="stable"
PIN_VERSION=""
FLOOR=""
UPDATE_FLAKE=0
DO_BUILD=0
DRY_RUN=0
ALLOW_DOWNGRADE=0
NOTES_FILE=""

usage() {
  cat <<'EOF'
Usage: scripts/update.sh [options]

Update happ.nix to a newer happ-desktop release.

Options:
  --stable           Consider stable releases only, pick highest semver (default)
  --prerelease       Consider pre-releases too, pick highest semver
  --latest           Trust the upstream "Latest" release marker (deprecated)
  --version VER      Use a specific release version
  --asset NAME       Release asset (default: Happ.linux.x64.deb)
  --floor VER        Refuse to resolve anything older than VER
  --allow-downgrade  Permit switching to an older version (default: refuse)
  --update-flake     Update flake.lock
  --build            Build the package after updating
  --notes FILE       Write release notes to a Markdown file
  --dry-run          Show changes without modifying repository files
  -h, --help         Show this help
EOF
}

while (($#)); do
  case "$1" in
    --stable)          MODE="stable"; shift ;;
    --prerelease)      MODE="prerelease"; shift ;;
    --latest)          MODE="latest"; shift ;;
    --version)         PIN_VERSION="${2:?Missing version}"; shift 2 ;;
    --asset)           ASSET="${2:?Missing asset name}"; shift 2 ;;
    --floor)           FLOOR="${2:?Missing version}"; shift 2 ;;
    --allow-downgrade) ALLOW_DOWNGRADE=1; shift ;;
    --update-flake)    UPDATE_FLAKE=1; shift ;;
    --build)           DO_BUILD=1; shift ;;
    --notes)           NOTES_FILE="${2:?Missing file path}"; shift 2 ;;
    --dry-run)         DRY_RUN=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    *)                 echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
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

current_hash() {
  sed -n 's/^[[:space:]]*sha256 = "\(.*\)";.*/\1/p' "$PKG_FILE" | head -n1
}

# Dotted numeric comparison, tolerant of "v4.8.3" and "4.8.3-beta1".
# Prints 1 / 0 / -1.
vercmp() {
  local a="${1#v}" b="${2#v}"
  a="${a%%-*}"; b="${b%%-*}"

  local i x y
  local -a av bv
  IFS=. read -r -a av <<<"$a"
  IFS=. read -r -a bv <<<"$b"

  for ((i = 0; i < ${#av[@]} || i < ${#bv[@]}; i++)); do
    x="${av[i]:-0}"; y="${bv[i]:-0}"
    x="${x//[^0-9]/}"; y="${y//[^0-9]/}"
    ((10#${x:-0} > 10#${y:-0})) && { echo 1; return 0; }
    ((10#${x:-0} < 10#${y:-0})) && { echo -1; return 0; }
  done

  echo 0
}

# Highest-semver entry of a releases array (JSON on stdin).
max_release() {
  jq -c '
    map(select(.tag_name | test("^v?[0-9]+\\.[0-9]+\\.[0-9]+")))
    | sort_by(.tag_name | ltrimstr("v") | split("-")[0] | split(".") | map(tonumber) | . + [0, 0, 0] | .[0:3])
    | last // empty'
}

resolve_release() {
  local json

  if [[ -n "$PIN_VERSION" ]]; then
    json="$(api "https://api.github.com/repos/$REPO/releases/tags/$PIN_VERSION")"
  elif [[ "$MODE" == "latest" ]]; then
    json="$(api "https://api.github.com/repos/$REPO/releases/latest")"
  else
    local filter
    filter='map(select(.draft == false))'
    filter+=" | map(select(.assets | any(.name == \$asset)))"
    if [[ "$MODE" == "stable" ]]; then
      filter+=' | map(select(.prerelease == false))'
    fi

    json="$(api "https://api.github.com/repos/$REPO/releases?per_page=100" |
      jq -c --arg asset "$ASSET" "$filter" | max_release)"
  fi

  if [[ -z "$json" || "$json" == "null" ]]; then
    echo "No matching release found (mode: $MODE, asset: $ASSET)" >&2
    return 1
  fi

  if [[ -n "$NOTES_FILE" ]]; then
    jq -r '.body // ""' <<<"$json" >"$NOTES_FILE"
  fi

  jq -er '.tag_name' <<<"$json"
}

OLD_VERSION="$(current_version)"
OLD_HASH="$(current_hash)"

[[ -n "$OLD_VERSION" ]] || {
  echo "Could not read version from $PKG_FILE" >&2
  exit 1
}
[[ -n "$OLD_HASH" ]] || {
  echo "Could not read sha256 from $PKG_FILE" >&2
  exit 1
}

# Baseline: never move backwards relative to what is already pinned or already
# pending in an update branch.
BASELINE="$OLD_VERSION"
if [[ -n "$FLOOR" && "$(vercmp "$FLOOR" "$BASELINE")" == 1 ]]; then
  BASELINE="$FLOOR"
fi

NEW_VERSION="$(resolve_release)"

if [[ -z "$NEW_VERSION" ]]; then
  echo "Could not resolve a version" >&2
  exit 1
fi

CMP="$(vercmp "$NEW_VERSION" "$BASELINE")"

if [[ "$CMP" == -1 ]]; then
  if ((ALLOW_DOWNGRADE)); then
    echo "WARNING: downgrading $BASELINE -> $NEW_VERSION (--allow-downgrade)" >&2
  else
    echo "Refusing to go backwards: baseline $BASELINE, resolved $NEW_VERSION" >&2
    echo "(pass --allow-downgrade to override)" >&2
    exit 1
  fi
fi

echo "Current version : $OLD_VERSION"
[[ "$BASELINE" != "$OLD_VERSION" ]] && echo "Pending version : $BASELINE"
echo "Resolved version: $NEW_VERSION (mode: $MODE)"
echo "Asset           : $ASSET"

if [[ "$CMP" == 0 && "$UPDATE_FLAKE" -eq 0 ]]; then
  echo "Already up to date"
  exit 0
fi

URL="https://github.com/$REPO/releases/download/$NEW_VERSION/$ASSET"
NEW_HASH=""

if [[ "$OLD_VERSION" != "$NEW_VERSION" ]]; then
  echo "Fetching hash   : $URL"
  NEW_HASH="$(nix store prefetch-file --json --hash-type sha256 "$URL" | jq -er '.hash')"
  echo "New hash        : $NEW_HASH"
fi

if ((DRY_RUN)); then
  echo "Dry run: skipping repository changes"
  exit 0
fi

if [[ "$OLD_VERSION" != "$NEW_VERSION" ]]; then
  sed -i \
    -e "s|^\([[:space:]]*version = \"\)[^\"]*\(\";\)|\1$NEW_VERSION\2|" \
    "$PKG_FILE"
fi

if [[ -n "$NEW_HASH" && "$OLD_HASH" != "$NEW_HASH" ]]; then
  sed -i \
    -e "s|^\([[:space:]]*sha256 = \"\)[^\"]*\(\";\)|\1$NEW_HASH\2|" \
    "$PKG_FILE"
fi

if ! git diff --quiet -- "$PKG_FILE"; then
  echo "Updated $PKG_FILE"
else
  echo "No package change"
fi

if ((UPDATE_FLAKE)); then
  echo "Updating flake.lock..."
  nix flake update
fi

if ((DO_BUILD)); then
  echo "Building .#happ..."
  nix build --no-link .#happ
  echo "Build successful"
fi

echo "Done: $OLD_VERSION -> $NEW_VERSION"
