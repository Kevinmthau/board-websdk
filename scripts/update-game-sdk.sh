#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  ./scripts/update-game-sdk.sh --game ../games/paint-board
  ./scripts/update-game-sdk.sh --game ../games/paint-board --sdk-tarball harrishill-board-sdk-0.1.0.tgz

Copies a versioned Board Web SDK npm tarball into a generated game repo,
updates web/package.json to reference the vendored tarball, and refreshes
web/package-lock.json.
USAGE
}

die() {
    printf 'Error: %s\n\n' "$1" >&2
    usage >&2
    exit 1
}

absolute_file() {
    local file="$1"
    local dir
    dir="$(cd "$(dirname "$file")" && pwd)"
    printf '%s/%s\n' "$dir" "$(basename "$file")"
}

find_default_tarball() {
    local match
    local count=0
    local selected=""

    for match in "$REPO_ROOT"/harrishill-board-sdk-*.tgz; do
        [ -f "$match" ] || continue
        count=$((count + 1))
        selected="$match"
    done

    case "$count" in
        0)
            die "no harrishill-board-sdk-*.tgz tarball found in $REPO_ROOT"
            ;;
        1)
            absolute_file "$selected"
            ;;
        *)
            die "multiple SDK tarballs found; pass --sdk-tarball explicitly"
            ;;
    esac
}

resolve_tarball() {
    local value="$1"

    if [ -z "$value" ]; then
        find_default_tarball
        return 0
    fi

    if [ -f "$value" ]; then
        absolute_file "$value"
        return 0
    fi

    if [ -f "$REPO_ROOT/$value" ]; then
        absolute_file "$REPO_ROOT/$value"
        return 0
    fi

    die "SDK tarball not found: $value"
}

game_arg=""
sdk_tarball_arg=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --game)
            [ "${2:-}" != "" ] || die "--game requires a value"
            game_arg="$2"
            shift 2
            ;;
        --sdk-tarball)
            [ "${2:-}" != "" ] || die "--sdk-tarball requires a value"
            sdk_tarball_arg="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[ -n "$game_arg" ] || die "missing required --game"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

[ -d "$game_arg" ] || die "game directory not found: $game_arg"
GAME_DIR="$(cd "$game_arg" && pwd)"
WEB_DIR="$GAME_DIR/web"
VENDOR_DIR="$GAME_DIR/vendor"
PACKAGE_JSON="$WEB_DIR/package.json"
BUILD_SCRIPT="$GAME_DIR/scripts/build_android.sh"

[ -f "$PACKAGE_JSON" ] || die "expected generated game file not found: $PACKAGE_JSON"
[ -d "$VENDOR_DIR" ] || die "expected generated game directory not found: $VENDOR_DIR"
[ -f "$BUILD_SCRIPT" ] || die "expected generated game build script not found: $BUILD_SCRIPT"

command -v node >/dev/null 2>&1 || die "node is required to update web/package.json"
command -v npm >/dev/null 2>&1 || die "npm is required to refresh web/package-lock.json"

SDK_TARBALL="$(resolve_tarball "$sdk_tarball_arg")"
SDK_TARBALL_NAME="$(basename "$SDK_TARBALL")"

case "$SDK_TARBALL_NAME" in
    harrishill-board-sdk-*.tgz) ;;
    *) die "--sdk-tarball must be named harrishill-board-sdk-<version>.tgz" ;;
esac

DEST_TARBALL="$VENDOR_DIR/$SDK_TARBALL_NAME"
if [ "$SDK_TARBALL" != "$DEST_TARBALL" ]; then
    cp "$SDK_TARBALL" "$DEST_TARBALL"
fi

SDK_SPEC="file:../vendor/$SDK_TARBALL_NAME"
PACKAGE_JSON="$PACKAGE_JSON" SDK_SPEC="$SDK_SPEC" node <<'NODE'
const fs = require("fs");

const packagePath = process.env.PACKAGE_JSON;
const sdkSpec = process.env.SDK_SPEC;
const raw = fs.readFileSync(packagePath, "utf8");
const pkg = JSON.parse(raw);

pkg.dependencies = pkg.dependencies || {};
pkg.dependencies["@harrishill/board-sdk"] = sdkSpec;

fs.writeFileSync(packagePath, `${JSON.stringify(pkg, null, 2)}\n`);
NODE

(cd "$WEB_DIR" && npm install --package-lock-only --include=dev)

sdk_version="${SDK_TARBALL_NAME#harrishill-board-sdk-}"
sdk_version="${sdk_version%.tgz}"

printf 'Updated %s to Board Web SDK %s.\n\n' "$GAME_DIR" "$sdk_version"
printf 'Review and commit from the game repo:\n'
printf '  cd %s\n' "$GAME_DIR"
printf '  git status --short\n'
printf '  git diff -- web/package.json web/package-lock.json vendor/\n'
printf '  git add web/package.json web/package-lock.json vendor/\n'
printf '  git commit -m "Update Board Web SDK to %s"\n' "$sdk_version"
