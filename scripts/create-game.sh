#!/usr/bin/env bash
set -euo pipefail

OLD_PACKAGE="co.harrishill.board.websdktest"
OLD_PACKAGE_PATH="${OLD_PACKAGE//.//}"
OLD_APP_ID="00000000-0000-0000-0000-web-sdk-test"
SDK_TARBALL="harrishill-board-sdk-0.1.0.tgz"

usage() {
    cat <<'USAGE'
Usage:
  ./scripts/create-game.sh --name "Game Name" --slug game-slug --package com.example.gameslug

Creates a sibling project next to board-websdk:
  ../<slug>/web/
  ../<slug>/android/
  ../<slug>/vendor/
  ../<slug>/scripts/build_android.sh
  ../<slug>/AGENTS.md
  ../<slug>/README.md
USAGE
}

die() {
    printf 'Error: %s\n\n' "$1" >&2
    usage >&2
    exit 1
}

replace_in_file() {
    local file="$1"
    local search="$2"
    local replace="$3"

    [ -f "$file" ] || die "expected file not found: $file"
    SEARCH="$search" REPLACE="$replace" perl -0pi -e 's/\Q$ENV{SEARCH}\E/$ENV{REPLACE}/g' "$file"
}

copy_tree() {
    local src="$1"
    local dest="$2"

    mkdir -p "$dest"
    (
        cd "$src"
        tar \
            --exclude './node_modules' \
            --exclude './dist' \
            --exclude './.gradle' \
            --exclude './build' \
            --exclude './app/build' \
            --exclude './app/src/main/assets/example' \
            -cf - .
    ) | (
        cd "$dest"
        tar -xf -
    )
}

xml_escape() {
    local value="$1"
    value=${value//&/&amp;}
    value=${value//</&lt;}
    value=${value//>/&gt;}
    value=${value//\"/&quot;}
    value=${value//\'/&apos;}
    printf '%s' "$value"
}

write_project_readme() {
    local dest="$1"
    local game_name="$2"
    local slug="$3"
    local package_id="$4"

    cat > "$dest/README.md" <<EOF
# $game_name

Generated Board Web SDK game scaffold.

## Layout

- \`web/\`: Vite + TypeScript web game source copied from the SDK example.
- \`android/\`: Android harness project with this game's package identity.
- \`vendor/\`: Local Board Web SDK npm tarball used by \`web/package.json\`.
- \`scripts/build_android.sh\`: Builds web + Android, copies the debug APK,
  and can install/launch with \`bdb\`.

## Identity

- Android package/application id: \`$package_id\`
- Android display label: \`$game_name\`
- Board app id: \`$slug\`
- APK output path: \`Builds/Android/$slug-debug.apk\`
- Current model path: \`android/app/src/main/assets/model.tflite\`

Android treats the package/application id as the install identity. The display
label is only the name shown to users.

## Build

\`\`\`bash
./scripts/build_android.sh
\`\`\`

The script builds \`web/dist\`, runs the Android wrapper build, and copies the
debug APK to \`Builds/Android/$slug-debug.apk\`. Use \`--install --launch\` to
deploy through \`bdb\` when Board device tooling is installed.

\`\`\`bash
bdb status
./scripts/build_android.sh --install --launch
adb install Builds/Android/$slug-debug.apk
\`\`\`

The Android build copies \`web/dist\` into APK assets by default. Use
\`./scripts/build_android.sh --web-target raw\` only for the raw bridge test
page.
EOF
}

write_project_agents() {
    local dest="$1"
    local game_name="$2"
    local slug="$3"
    local package_id="$4"
    local file="$dest/AGENTS.md"

    cat > "$file" <<'EOF'
# __GAME_NAME__ Agent Guide

## Scope

These instructions apply to this generated Board Web SDK game project.

## Project Identity

- Android package/application id: `__PACKAGE_ID__`
- Android display label: `__GAME_NAME__`
- Board app id: `__SLUG__`
- APK output path: `Builds/Android/__SLUG__-debug.apk`
- Current model path: `android/app/src/main/assets/model.tflite`
- WebView asset origin: `https://appassets.androidplatform.net/assets/web/index.html`

Android install identity is the package/application id, not the display label.

## Workflow

1. Keep game code in `web/` TypeScript/ESM-compatible unless the user asks for another stack.
2. Import Board APIs from `@harrishill/board-sdk`.
3. Do not edit the SDK repo's `sample/` harness into this game. This project already has its own Android wrapper and app identity.
4. Preserve `web/vite.config.ts` `base: "./"` so Android asset loading keeps working.
5. Preserve the Android wrapper setup order: initialize `BoardNativePlugin` context and app id, load `model.tflite`, activate `RawDataGlyphDetector`, then create/register the WebView bridge and touch channel.

## Board Input Rules

- Always guard Board APIs with `Board.isOnDevice`; bridge-backed APIs throw in a normal browser.
- Keep `Board.isOnDevice` truthful. Simulate browser gameplay input in app code, not by creating fake bridge globals.
- Treat `Board.input.subscribe(...)` as a live frame stream. Stationary pieces keep reporting until `Ended`.
- Track physical piece instances by `contactId`, never by `glyphId`.
- Treat `glyphId` as the detected piece/type id only.
- Filter `BoardContactType.Glyph` when handling physical pieces.
- Use `Board.bridgeVersion ?? 0` to gate newer host-bridge features.

## Build And Device Loop

```bash
./scripts/build_android.sh
bdb status
./scripts/build_android.sh --install --launch
```

Use `adb install Builds/Android/__SLUG__-debug.apk` as a fallback when `bdb` is unavailable.
EOF

    replace_in_file "$file" "__GAME_NAME__" "$game_name"
    replace_in_file "$file" "__SLUG__" "$slug"
    replace_in_file "$file" "__PACKAGE_ID__" "$package_id"
}

write_build_android_script() {
    local dest="$1"
    local slug="$2"
    local package_id="$3"
    local scripts_dir="$dest/scripts"
    local file="$scripts_dir/build_android.sh"

    mkdir -p "$scripts_dir"
    cat > "$file" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SLUG="__SLUG__"
PACKAGE_ID="__PACKAGE_ID__"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_REL="Builds/Android/${SLUG}-debug.apk"
OUTPUT_APK="$ROOT_DIR/$OUTPUT_REL"
BUILD_WEB=1
INSTALL=0
LAUNCH=0
STATUS=0
WEB_TARGET="web"

usage() {
    cat <<USAGE
Usage:
  ./scripts/build_android.sh [--install] [--launch] [--status] [--skip-web-build] [--web-target web|raw]

Builds the Vite web app, assembles the Android debug APK, and copies it to:
  $OUTPUT_REL

Options:
  --install          Install the copied APK with bdb.
  --launch           Install, then launch $PACKAGE_ID with bdb.
  --status           Run bdb status before install/launch.
  --skip-web-build   Reuse the existing web/dist directory.
  --web-target raw   Build the raw bridge test page instead of web/dist.
USAGE
}

die() {
    printf 'Error: %s\n' "$1" >&2
    printf '\n' >&2
    usage >&2
    exit 1
}

resolve_bdb() {
    if [ -n "${BDB_BIN:-}" ]; then
        if [ -x "$BDB_BIN" ] || command -v "$BDB_BIN" >/dev/null 2>&1; then
            printf '%s\n' "$BDB_BIN"
            return 0
        fi
        return 1
    fi

    local candidate
    for candidate in bdb "$ROOT_DIR/Tools/bdb" "$HOME/Desktop/bdb"; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

run_bdb() {
    local bdb
    if ! bdb="$(resolve_bdb)"; then
        printf 'Error: bdb was requested but was not found. Set BDB_BIN or install bdb on PATH.\n' >&2
        exit 1
    fi
    "$bdb" "$@"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --install)
            INSTALL=1
            shift
            ;;
        --launch)
            INSTALL=1
            LAUNCH=1
            shift
            ;;
        --status)
            STATUS=1
            shift
            ;;
        --skip-web-build)
            BUILD_WEB=0
            shift
            ;;
        --web-target)
            [ "${2:-}" != "" ] || die "--web-target requires web or raw"
            WEB_TARGET="$2"
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

case "$WEB_TARGET" in
    web|raw) ;;
    *) die "--web-target must be web or raw" ;;
esac

if [ "$WEB_TARGET" = "raw" ]; then
    BUILD_WEB=0
fi

if [ "$STATUS" -eq 1 ]; then
    run_bdb status
fi

if [ "$BUILD_WEB" -eq 1 ]; then
    if [ ! -d "$ROOT_DIR/web/node_modules" ]; then
        printf 'Installing web dependencies...\n'
        (cd "$ROOT_DIR/web" && npm install --include=dev)
    fi
    (cd "$ROOT_DIR/web" && npm run build)
fi

gradle_args=(assembleDebug)
if [ "$WEB_TARGET" = "raw" ]; then
    gradle_args+=("-Pweb=raw")
fi

(cd "$ROOT_DIR/android" && ./gradlew "${gradle_args[@]}")

mkdir -p "$(dirname "$OUTPUT_APK")"
cp "$ROOT_DIR/android/app/build/outputs/apk/debug/app-debug.apk" "$OUTPUT_APK"
printf 'Copied APK: %s\n' "$OUTPUT_REL"

if [ "$INSTALL" -eq 1 ]; then
    run_bdb install "$OUTPUT_APK"
fi

if [ "$LAUNCH" -eq 1 ]; then
    run_bdb launch "$PACKAGE_ID"
fi
EOF

    replace_in_file "$file" "__SLUG__" "$slug"
    replace_in_file "$file" "__PACKAGE_ID__" "$package_id"
    chmod +x "$file"
}

game_name=""
slug=""
package_id=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --name)
            [ "${2:-}" != "" ] || die "--name requires a value"
            game_name="$2"
            shift 2
            ;;
        --slug)
            [ "${2:-}" != "" ] || die "--slug requires a value"
            slug="$2"
            shift 2
            ;;
        --package)
            [ "${2:-}" != "" ] || die "--package requires a value"
            package_id="$2"
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

[ -n "$game_name" ] || die "missing required --name"
[ -n "$slug" ] || die "missing required --slug"
[ -n "$package_id" ] || die "missing required --package"

case "$game_name" in
    *$'\n'*|*$'\r'*)
        die "--name must be a single line"
        ;;
esac

if [[ ! "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    die "--slug must contain lowercase letters, numbers, and single hyphen separators only"
fi

if [[ ! "$package_id" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]]; then
    die "--package must look like a valid dotted Android package id, for example com.example.mygame"
fi

case "$package_id" in
    "$OLD_PACKAGE"|"$OLD_PACKAGE".*)
        die "--package must be unique to the game, not based on the SDK harness package"
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARENT_DIR="$(cd "$REPO_ROOT/.." && pwd)"
DEST="$PARENT_DIR/$slug"
WEB_DIR="$DEST/web"
ANDROID_DIR="$DEST/android"
VENDOR_DIR="$DEST/vendor"

[ -d "$REPO_ROOT/example" ] || die "missing source directory: $REPO_ROOT/example"
[ -d "$REPO_ROOT/sample" ] || die "missing source directory: $REPO_ROOT/sample"
[ -f "$REPO_ROOT/$SDK_TARBALL" ] || die "missing SDK tarball: $REPO_ROOT/$SDK_TARBALL"

if [ -e "$DEST" ]; then
    die "destination already exists: $DEST"
fi

mkdir -p "$DEST" "$VENDOR_DIR"
copy_tree "$REPO_ROOT/example" "$WEB_DIR"
copy_tree "$REPO_ROOT/sample" "$ANDROID_DIR"
cp "$REPO_ROOT/$SDK_TARBALL" "$VENDOR_DIR/"

label_xml="$(xml_escape "$game_name")"
title_html="$label_xml"

replace_in_file "$WEB_DIR/package.json" '"name": "board-web-sdk-example"' "\"name\": \"$slug\""
replace_in_file "$WEB_DIR/package-lock.json" '"name": "board-web-sdk-example"' "\"name\": \"$slug\""
replace_in_file "$WEB_DIR/package.json" "../$SDK_TARBALL" "../vendor/$SDK_TARBALL"
replace_in_file "$WEB_DIR/package-lock.json" "../$SDK_TARBALL" "../vendor/$SDK_TARBALL"
replace_in_file "$WEB_DIR/README.md" "# Board Web SDK Example" "# $game_name"
replace_in_file "$WEB_DIR/README.md" "cd ../sample && ./gradlew assembleDebug" "cd ../android && ./gradlew assembleDebug"
replace_in_file "$WEB_DIR/README.md" "sample/app/src/main/assets/example/" "android/app/src/main/assets/web/"
replace_in_file "$WEB_DIR/README.md" "Android harness (in this repo)." "Android wrapper (in this project)."
replace_in_file "$WEB_DIR/README.md" "Build this example" "Build this web app"
replace_in_file "$WEB_DIR/README.md" "the default harness path" "the default Android asset path"
replace_in_file "$WEB_DIR/README.md" "The harness native bridge" "The native bridge"
replace_in_file "$WEB_DIR/README.md" "running this example outside the bundle" "running this web app outside the scaffold"
replace_in_file "$WEB_DIR/README.md" "file:../$SDK_TARBALL" "file:../vendor/$SDK_TARBALL"
replace_in_file "$WEB_DIR/README.md" "the tarball in this bundle" "the tarball in ../vendor"
replace_in_file "$WEB_DIR/index.html" "<title>Board Web SDK Example</title>" "<title>$title_html</title>"
replace_in_file "$WEB_DIR/index.html" "<h1>Board Web SDK</h1>" "<h1>$title_html</h1>"

replace_in_file "$ANDROID_DIR/settings.gradle" "rootProject.name = 'board-web-sdk-test'" "rootProject.name = '$slug'"
replace_in_file "$ANDROID_DIR/app/build.gradle" "namespace '$OLD_PACKAGE'" "namespace '$package_id'"
replace_in_file "$ANDROID_DIR/app/build.gradle" "applicationId '$OLD_PACKAGE'" "applicationId '$package_id'"
replace_in_file "$ANDROID_DIR/app/build.gradle" "loads the example (default)" "loads the web build (default)"
replace_in_file "$ANDROID_DIR/app/build.gradle" "loads the example (explicit)" "loads the web build (explicit)"
replace_in_file "$ANDROID_DIR/app/build.gradle" "web=example" "web=web"
replace_in_file "$ANDROID_DIR/app/build.gradle" "./gradlew assembleDebug -Pweb=web   ->" "./gradlew assembleDebug -Pweb=web       ->"
replace_in_file "$ANDROID_DIR/app/build.gradle" "?: 'example'" "?: 'web'"
replace_in_file "$ANDROID_DIR/app/build.gradle" "/assets/example/index.html" "/assets/web/index.html"
replace_in_file "$ANDROID_DIR/app/build.gradle" "Copy the web example's built output into the APK assets. The example lives" "Copy the web app's built output into the APK assets. The web app lives"
replace_in_file "$ANDROID_DIR/app/build.gradle" "in ../../example/ as a Vite project" "in ../../web/ as a Vite project"
replace_in_file "$ANDROID_DIR/app/build.gradle" "copyExampleAssets" "copyWebAssets"
replace_in_file "$ANDROID_DIR/app/build.gradle" "from '../../example/dist'" "from '../../web/dist'"
replace_in_file "$ANDROID_DIR/app/build.gradle" "into 'src/main/assets/example'" "into 'src/main/assets/web'"
replace_in_file "$ANDROID_DIR/app/build.gradle" "file('../../example/dist')" "file('../../web/dist')"
replace_in_file "$ANDROID_DIR/app/build.gradle" "example/dist not found. Run: cd ../../example && npm install && npm run build" "web/dist not found. Run: cd ../../web && npm install --include=dev && npm run build"
replace_in_file "$ANDROID_DIR/app/build.gradle" "webTarget == 'example'" "webTarget == 'web'"
replace_in_file "$ANDROID_DIR/.gitignore" "copyExampleAssets" "copyWebAssets"
replace_in_file "$ANDROID_DIR/.gitignore" "../example/" "../web/"
replace_in_file "$ANDROID_DIR/.gitignore" "app/src/main/assets/example/" "app/src/main/assets/web/"
replace_in_file "$ANDROID_DIR/app/src/main/AndroidManifest.xml" 'android:label="Board Web SDK Test"' "android:label=\"$label_xml\""

old_java_dir="$ANDROID_DIR/app/src/main/java/$OLD_PACKAGE_PATH"
new_java_dir="$ANDROID_DIR/app/src/main/java/${package_id//.//}"
[ -d "$old_java_dir" ] || die "expected Java package directory not found: $old_java_dir"
mkdir -p "$(dirname "$new_java_dir")"
mv "$old_java_dir" "$new_java_dir"
find "$ANDROID_DIR/app/src/main/java" -type d -empty -delete

activity_file="$new_java_dir/BoardWebViewActivity.java"
replace_in_file "$activity_file" "package $OLD_PACKAGE;" "package $package_id;"
replace_in_file "$activity_file" "private static final String TEST_APP_ID = \"$OLD_APP_ID\";" "private static final String APP_ID = \"$slug\";"
replace_in_file "$activity_file" "BoardNativePlugin.setAppId(TEST_APP_ID);" "BoardNativePlugin.setAppId(APP_ID);"

write_project_readme "$DEST" "$game_name" "$slug" "$package_id"
write_project_agents "$DEST" "$game_name" "$slug" "$package_id"
write_build_android_script "$DEST" "$slug" "$package_id"

if grep -RqsF -e "$OLD_PACKAGE" -e "$OLD_APP_ID" "$DEST"; then
    printf 'Error: generated project still contains old SDK harness identity values.\n' >&2
    exit 1
fi

printf 'Created Board Web SDK game scaffold:\n'
printf '  %s\n\n' "$DEST"
printf 'Next steps:\n'
printf '  cd %s\n' "$DEST"
printf '  ./scripts/build_android.sh\n'
printf '  ./scripts/build_android.sh --install --launch\n'
