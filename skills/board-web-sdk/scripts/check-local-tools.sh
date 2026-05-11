#!/usr/bin/env bash
set -u

MODE="game"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --mode. Use game, browser, or harness." >&2
        exit 2
      fi
      MODE="${2:-}"
      shift 2
      ;;
    --mode=*)
      MODE="${1#--mode=}"
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: check-local-tools.sh [--mode game|browser|harness]

Modes:
  game     Check browser tooling plus Android harness tooling.
  browser  Check only local web-game build tooling.
  harness  Check only Android harness and device tooling.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$MODE" != "game" && "$MODE" != "browser" && "$MODE" != "harness" ]]; then
  echo "Invalid --mode '$MODE'. Use game, browser, or harness." >&2
  exit 2
fi

missing=()
actions=()
warnings=()

ok() {
  printf 'OK       %s\n' "$1"
}

warn() {
  warnings+=("$1")
  printf 'WARNING  %s\n' "$1"
}

miss() {
  missing+=("$1")
  printf 'MISSING  %s\n' "$1"
}

action() {
  actions+=("$1")
  printf 'ACTION   %s\n' "$1"
}

need_browser() {
  [[ "$MODE" == "game" || "$MODE" == "browser" ]]
}

need_harness() {
  [[ "$MODE" == "game" || "$MODE" == "harness" ]]
}

node_major() {
  node -p 'process.versions.node.split(".")[0]' 2>/dev/null
}

java_major() {
  local java_bin="${1:-java}"
  "$java_bin" -version 2>&1 | awk -F '"' '/version/ {
    split($2, parts, ".")
    if (parts[1] == "1") print parts[2]; else print parts[1]
    exit
  }'
}

java_version() {
  local java_bin="${1:-java}"
  "$java_bin" -version 2>&1 | awk -F '"' '/version/ {print $2; exit}'
}

javac_version() {
  local javac_bin="${1:-javac}"
  "$javac_bin" -version 2>&1 | awk '/javac/ {print $2; exit}'
}

javac_major() {
  local javac_bin="${1:-javac}"
  local version
  version="$(javac_version "$javac_bin")"
  printf '%s\n' "$version" | awk -F. '{if ($1 == "1") print $2; else print $1}'
}

valid_jdk_home() {
  local java_home="$1"
  local detected_java_major detected_javac_major

  [[ -n "$java_home" ]] || return 1
  [[ -x "$java_home/bin/java" ]] || return 1
  [[ -x "$java_home/bin/javac" ]] || return 1

  detected_java_major="$(java_major "$java_home/bin/java")"
  detected_javac_major="$(javac_major "$java_home/bin/javac")"
  [[ "$detected_java_major" =~ ^[0-9]+$ && "$detected_java_major" -ge 17 ]] || return 1
  [[ "$detected_javac_major" =~ ^[0-9]+$ && "$detected_javac_major" -ge 17 ]] || return 1
}

detect_jdk_home() {
  local candidate

  if [[ -n "${JAVA_HOME:-}" && -d "${JAVA_HOME:-}" ]] && valid_jdk_home "$JAVA_HOME"; then
    printf '%s\n' "$JAVA_HOME"
    return 0
  fi

  if [[ -x /usr/libexec/java_home ]]; then
    candidate="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
    if [[ -n "$candidate" && -d "$candidate" ]] && valid_jdk_home "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  for candidate in \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
    "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home"; do
    if [[ -d "$candidate" ]] && valid_jdk_home "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

detect_android_sdk() {
  for candidate in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

printf 'Board Web SDK local tool check (mode: %s)\n' "$MODE"
printf 'Repo: %s\n\n' "$ROOT_DIR"

if need_browser; then
  if command -v node >/dev/null 2>&1; then
    major="$(node_major)"
    version="$(node -v 2>/dev/null)"
    if [[ "$major" =~ ^[0-9]+$ && "$major" -ge 18 ]]; then
      ok "Node $version"
    else
      miss "Node 18+ required; found ${version:-unknown}"
    fi
  else
    miss "Node 18+ is not installed or not on PATH"
  fi

  if command -v npm >/dev/null 2>&1; then
    ok "npm $(npm -v 2>/dev/null)"
  else
    miss "npm is not installed or not on PATH"
  fi

  if [[ -f "$ROOT_DIR/harrishill-board-sdk-0.1.0.tgz" ]]; then
    ok "Local SDK tarball exists"
  else
    miss "harrishill-board-sdk-0.1.0.tgz is missing"
  fi

  if [[ -f "$ROOT_DIR/example/package.json" ]]; then
    ok "example/package.json exists"
  else
    miss "example/package.json is missing"
  fi

  if [[ -d "$ROOT_DIR/example/node_modules" ]]; then
    ok "example/node_modules exists"
  else
    action "example dependencies are not installed; prompt before running: cd example && npm install"
  fi
fi

if need_harness; then
  path_java_ok=false
  path_javac_ok=false
  path_java_problem=""
  path_javac_problem=""
  gradle_java_home="$(awk -F= '/^org.gradle.java.home=/ {print $2}' "$ROOT_DIR/sample/gradle.properties" 2>/dev/null || true)"
  gradle_java_home_ok=false
  if [[ -n "$gradle_java_home" ]] && valid_jdk_home "$gradle_java_home"; then
    gradle_java_home_ok=true
  fi

  if command -v java >/dev/null 2>&1; then
    major="$(java_major)"
    if [[ "$major" =~ ^[0-9]+$ && "$major" -ge 17 ]]; then
      path_java_ok=true
      path_java_version="$(java_version)"
    else
      path_java_problem="java on PATH is not JDK 17+; version is ${major:-unknown}"
    fi
  else
    path_java_problem="java is not on PATH"
  fi

  if command -v javac >/dev/null 2>&1; then
    javac_output="$(javac -version 2>&1 || true)"
    path_javac_version="$(printf '%s\n' "$javac_output" | awk '/javac/ {print $2; exit}')"
    path_javac_major="$(printf '%s\n' "$path_javac_version" | awk -F. '{if ($1 == "1") print $2; else print $1}')"
    if [[ "$path_javac_major" =~ ^[0-9]+$ && "$path_javac_major" -ge 17 ]]; then
      path_javac_ok=true
    else
      first_line="$(printf '%s\n' "$javac_output" | head -1)"
      path_javac_problem="javac on PATH is not JDK 17+ (${first_line:-no version output})"
    fi
  else
    path_javac_problem="javac is not on PATH"
  fi

  if [[ "$path_java_ok" == true && "$path_javac_ok" == true ]]; then
    ok "Java runtime $path_java_version"
    ok "javac $path_javac_version"
  elif [[ "$path_java_ok" == true && "$gradle_java_home_ok" == true ]]; then
    ok "Java runtime $path_java_version"
    warn "javac is not fully usable from PATH (${path_javac_problem:-javac OK}); Gradle will use sample/gradle.properties org.gradle.java.home"
  else
    detected_jdk_home="$(detect_jdk_home || true)"
    if [[ -n "$detected_jdk_home" ]]; then
      detected_jdk_version="$(java_version "$detected_jdk_home/bin/java")"
      detected_javac_version="$(javac_version "$detected_jdk_home/bin/javac")"
      if [[ -n "${JAVA_HOME:-}" && "$JAVA_HOME" == "$detected_jdk_home" ]]; then
        ok "JDK $detected_jdk_version found at JAVA_HOME: $detected_jdk_home"
        warn "java/javac are not fully usable from PATH (${path_java_problem:-java OK}; ${path_javac_problem:-javac OK}); Gradle will use JAVA_HOME"
      else
        action "JDK 17+ found at $detected_jdk_home, but Gradle will not use it by default; prompt before running: export JAVA_HOME='$detected_jdk_home'"
      fi
    else
      if [[ "$path_java_ok" == true ]]; then
        ok "Java runtime $path_java_version"
      else
        miss "JDK 17+ required; $path_java_problem"
      fi
      if [[ "$path_javac_ok" == true ]]; then
        ok "javac $path_javac_version"
      else
        miss "JDK 17+ is required; $path_javac_problem"
      fi
    fi
  fi

  if [[ -n "$gradle_java_home" ]]; then
    if [[ ! -d "$gradle_java_home" ]]; then
      miss "sample/gradle.properties points org.gradle.java.home to a missing path: $gradle_java_home"
    elif [[ ! -x "$gradle_java_home/bin/java" ]]; then
      miss "sample/gradle.properties org.gradle.java.home is missing executable bin/java: $gradle_java_home"
    elif [[ ! -x "$gradle_java_home/bin/javac" ]]; then
      miss "sample/gradle.properties org.gradle.java.home is not a JDK 17+; missing executable bin/javac: $gradle_java_home"
    else
      gradle_java_major="$(java_major "$gradle_java_home/bin/java")"
      gradle_java_version="$(java_version "$gradle_java_home/bin/java")"
      gradle_javac_output="$("$gradle_java_home/bin/javac" -version 2>&1 || true)"
      gradle_javac_version="$(printf '%s\n' "$gradle_javac_output" | awk '/javac/ {print $2; exit}')"
      gradle_javac_major="$(printf '%s\n' "$gradle_javac_version" | awk -F. '{if ($1 == "1") print $2; else print $1}')"
      if [[ "$gradle_java_major" =~ ^[0-9]+$ && "$gradle_java_major" -ge 17 && "$gradle_javac_major" =~ ^[0-9]+$ && "$gradle_javac_major" -ge 17 ]]; then
        ok "Gradle java home JDK $gradle_java_version: $gradle_java_home"
      else
        first_line="$(printf '%s\n' "$gradle_javac_output" | head -1)"
        miss "sample/gradle.properties org.gradle.java.home must be JDK 17+; found java ${gradle_java_version:-unknown}, javac ${first_line:-no version output}"
      fi
    fi
  fi

  sdk_dir="$(detect_android_sdk || true)"
  if [[ -n "$sdk_dir" ]]; then
    ok "Android SDK found at $sdk_dir"
    if [[ -d "$sdk_dir/platforms/android-34" ]]; then
      ok "Android compile SDK 34 installed"
    else
      miss "Android SDK platform android-34 is not installed"
    fi
    if [[ -x "$sdk_dir/platform-tools/adb" ]]; then
      ok "adb found in Android SDK platform-tools"
    elif command -v adb >/dev/null 2>&1; then
      ok "adb $(adb version 2>/dev/null | head -1)"
    else
      miss "adb/platform-tools is not installed or not on PATH"
    fi
  else
    miss "Android SDK not found; set ANDROID_HOME or ANDROID_SDK_ROOT"
    if ! command -v adb >/dev/null 2>&1; then
      miss "adb/platform-tools is not installed or not on PATH"
    fi
  fi

  if [[ -x "$ROOT_DIR/sample/gradlew" ]]; then
    ok "Gradle wrapper is executable"
  elif [[ -f "$ROOT_DIR/sample/gradlew" ]]; then
    action "sample/gradlew exists but is not executable; prompt before running: chmod +x sample/gradlew"
  else
    miss "sample/gradlew is missing"
  fi

  if [[ -f "$ROOT_DIR/sample/app/libs/board-webview-general-debug.aar" ]]; then
    ok "Harness AAR exists"
    if command -v unzip >/dev/null 2>&1; then
      aar_abis="$(unzip -Z1 "$ROOT_DIR/sample/app/libs/board-webview-general-debug.aar" 2>/dev/null | awk -F/ '$1 == "jni" && $2 != "" && $NF ~ /\.so$/ {print $2}' | sort -u | paste -sd, -)"
      if [[ "$aar_abis" == "arm64-v8a" ]]; then
        warn "Harness native bridge is arm64-v8a only; use an arm64 Android 10+ device or emulator image"
      elif [[ -n "$aar_abis" ]]; then
        ok "Harness native ABIs: $aar_abis"
      else
        warn "Harness AAR contains no native ABI directories"
      fi
    else
      warn "unzip is not on PATH; cannot inspect harness native ABIs"
    fi
  else
    miss "sample/app/libs/board-webview-general-debug.aar is missing"
  fi

  if [[ -f "$ROOT_DIR/board-web-sdk-harness-debug.apk" ]]; then
    ok "Prebuilt harness APK exists"
  else
    warn "Prebuilt harness APK is missing; harness can still be built from sample/"
  fi
fi

printf '\n'

if [[ ${#warnings[@]} -gt 0 ]]; then
  printf 'Warnings:\n'
  for item in "${warnings[@]}"; do
    printf '  - %s\n' "$item"
  done
  printf '\n'
fi

if [[ ${#actions[@]} -gt 0 ]]; then
  printf 'Setup actions that require user approval before running:\n'
  for item in "${actions[@]}"; do
    printf '  - %s\n' "$item"
  done
  printf '\n'
fi

if [[ ${#missing[@]} -gt 0 ]]; then
  printf 'Missing required items:\n'
  for item in "${missing[@]}"; do
    printf '  - %s\n' "$item"
  done
  printf '\nPrompt the user to install or configure these items before continuing.\n'
  exit 1
fi

if [[ ${#actions[@]} -gt 0 ]]; then
  printf 'Required software is present, but setup actions remain. Prompt the user before running them.\n'
  exit 1
fi

printf 'All required local tools are available for mode: %s\n' "$MODE"
