#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_TARGET="example"
BUILD_WEB=1

usage() {
    cat <<'USAGE'
Usage:
  ./scripts/build-harness.sh [--web-target example|raw] [--skip-web-build]

Builds the SDK sample harness APK. By default it builds example/dist first and
packages it into the harness. Use --web-target raw to build the raw bridge test
page without the Vite example.

Options:
  --web-target raw       Build the raw bridge tester instead of example/dist.
  --web-target example   Build and package example/dist. This is the default.
  --skip-web-build       Reuse the existing example/dist directory.
USAGE
}

die() {
    printf 'Error: %s\n' "$1" >&2
    printf '\n' >&2
    usage >&2
    exit 1
}

java_major() {
    local java_bin="${1:-java}"
    "$java_bin" -version 2>&1 | awk -F '"' '/version/ {
        split($2, parts, ".")
        if (parts[1] == "1") print parts[2]; else print parts[1]
        exit
    }'
}

javac_major() {
    local javac_bin="${1:-javac}"
    "$javac_bin" -version 2>&1 | awk '/javac/ {
        split($2, parts, ".")
        if (parts[1] == "1") print parts[2]; else print parts[1]
        exit
    }'
}

valid_jdk_home() {
    local java_home="$1"
    local detected_java_major detected_javac_major

    [ -n "$java_home" ] || return 1
    [ -x "$java_home/bin/java" ] || return 1
    [ -x "$java_home/bin/javac" ] || return 1

    detected_java_major="$(java_major "$java_home/bin/java")"
    detected_javac_major="$(javac_major "$java_home/bin/javac")"
    [[ "$detected_java_major" =~ ^[0-9]+$ && "$detected_java_major" -ge 17 ]] || return 1
    [[ "$detected_javac_major" =~ ^[0-9]+$ && "$detected_javac_major" -ge 17 ]] || return 1
}

detect_jdk_home() {
    local candidate

    if [ -n "${JAVA_HOME:-}" ] && valid_jdk_home "$JAVA_HOME"; then
        printf '%s\n' "$JAVA_HOME"
        return 0
    fi

    if [ -x /usr/libexec/java_home ]; then
        candidate="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
        if [ -n "$candidate" ] && valid_jdk_home "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi

    for candidate in \
        "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
        "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home"; do
        if valid_jdk_home "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

detect_android_sdk() {
    local candidate local_properties_sdk

    local_properties_sdk="$(awk -F= '/^[[:space:]]*sdk\.dir[[:space:]]*=/ {
        sub(/^[[:space:]]*sdk\.dir[[:space:]]*=[[:space:]]*/, "")
        sub(/[[:space:]]*$/, "")
        gsub(/\\ /, " ")
        print
        exit
    }' "$ROOT_DIR/sample/local.properties" 2>/dev/null || true)"

    for candidate in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$local_properties_sdk" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
        if [ -n "$candidate" ] && [ -d "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

configure_android_build_env() {
    local jdk_home sdk_dir path_java_major path_javac_major

    if jdk_home="$(detect_jdk_home)"; then
        if [ "${JAVA_HOME:-}" != "$jdk_home" ]; then
            printf 'Using JDK: %s\n' "$jdk_home"
        fi
        export JAVA_HOME="$jdk_home"
    else
        if [ -n "${JAVA_HOME:-}" ]; then
            die "JAVA_HOME is set but does not point to a JDK 17+ directory: $JAVA_HOME"
        fi
        if ! command -v java >/dev/null 2>&1 || ! command -v javac >/dev/null 2>&1; then
            die "JDK 17+ not found. Install one or set JAVA_HOME to a JDK 17+ directory."
        fi
        path_java_major="$(java_major)"
        path_javac_major="$(javac_major)"
        if ! [[ "$path_java_major" =~ ^[0-9]+$ && "$path_java_major" -ge 17 && "$path_javac_major" =~ ^[0-9]+$ && "$path_javac_major" -ge 17 ]]; then
            die "JDK 17+ not found. Install one or set JAVA_HOME to a JDK 17+ directory."
        fi
    fi

    if ! sdk_dir="$(detect_android_sdk)"; then
        die "Android SDK not found. Install it or set ANDROID_HOME or ANDROID_SDK_ROOT."
    fi
    if [ "${ANDROID_HOME:-}" != "$sdk_dir" ]; then
        printf 'Using Android SDK: %s\n' "$sdk_dir"
    fi
    export ANDROID_HOME="$sdk_dir"
    export ANDROID_SDK_ROOT="$sdk_dir"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --web-target)
            [ "${2:-}" != "" ] || die "--web-target requires example or raw"
            WEB_TARGET="$2"
            shift 2
            ;;
        --skip-web-build)
            BUILD_WEB=0
            shift
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
    example|raw) ;;
    *) die "--web-target must be example or raw" ;;
esac

if [ "$WEB_TARGET" = "raw" ]; then
    BUILD_WEB=0
fi

configure_android_build_env

if [ "$BUILD_WEB" -eq 1 ]; then
    if [ ! -d "$ROOT_DIR/example/node_modules" ]; then
        die "example/node_modules not found. Run: cd example && npm install"
    fi
    (cd "$ROOT_DIR/example" && npm run build)
fi

gradle_args=(assembleDebug)
if [ "$WEB_TARGET" = "raw" ]; then
    gradle_args+=("-Pweb=raw")
fi

(cd "$ROOT_DIR/sample" && ./gradlew "${gradle_args[@]}")

printf 'Built harness APK: sample/app/build/outputs/apk/debug/app-debug.apk\n'
