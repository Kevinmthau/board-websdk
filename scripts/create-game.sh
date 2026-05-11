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

## Identity

- Android package/application id: \`$package_id\`
- Android display label: \`$game_name\`
- Board app id: \`$slug\`

Android treats the package/application id as the install identity. The display
label is only the name shown to users.

## Build

\`\`\`bash
cd web
npm install
npm run build

cd ../android
./gradlew assembleDebug
\`\`\`

The Android build copies \`web/dist\` into APK assets by default. Use
\`./gradlew assembleDebug -Pweb=raw\` only for the raw bridge test page.
EOF
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
replace_in_file "$ANDROID_DIR/app/build.gradle" "example/dist not found. Run: cd ../../example && npm install && npm run build" "web/dist not found. Run: cd ../../web && npm install && npm run build"
replace_in_file "$ANDROID_DIR/app/build.gradle" "webTarget == 'example'" "webTarget == 'web'"
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

if grep -RqsF -e "$OLD_PACKAGE" -e "$OLD_APP_ID" "$DEST"; then
    printf 'Error: generated project still contains old SDK harness identity values.\n' >&2
    exit 1
fi

printf 'Created Board Web SDK game scaffold:\n'
printf '  %s\n\n' "$DEST"
printf 'Next steps:\n'
printf '  cd %s/web && npm install && npm run build\n' "$DEST"
printf '  cd ../android && ./gradlew assembleDebug\n'
