---
name: board-web-sdk
description: Build, modify, and validate web games or web apps that use the Board Web SDK. Use when Codex needs to create a Board-compatible game, edit the Vite example, integrate @harrishill/board-sdk APIs, handle physical piece and touch input, use Board session/save/pause/avatar APIs, build the Android harness APK, or check local Node/JDK/Android SDK prerequisites before game development.
---

# Board Web SDK

## Overview

Use this skill to build Board-compatible web games from this SDK bundle. The SDK runs inside a Board WebView bridge on device, while normal browsers are useful for layout, game UI, and build validation.

## Required Preflight

Before creating a game or changing `example/` into a game, run the local checker from the repository root:

```bash
skills/board-web-sdk/scripts/check-local-tools.sh --mode game
```

Use `--mode browser` for browser-only work and `--mode harness` for Android harness or Board-device validation.

If the script reports missing software, SDKs, or local dependencies, stop before doing dependent work and prompt the user to install or configure the missing items. Do not run `npm install`, Android SDK downloads, package-manager installs, or other networked setup without user approval.

## Workflow

1. Read `README.md` for the current bundle workflow.
2. Read `example/src/main.ts` for working SDK call patterns.
3. Read relevant `board-sdk/*.d.ts` files before using a namespace in a new way.
4. Use `example/` as the default fork point for games unless the user specifies another project.
5. Import from `@harrishill/board-sdk` in bundled TypeScript/ESM apps.
6. Keep `vite.config.ts` relative asset behavior so built output works from Android assets.
7. Validate with `cd example && npm run build`; use the harness commands when Board bridge behavior matters.

## SDK Rules

Always gate Board APIs:

```ts
import { Board, BoardContactType } from "@harrishill/board-sdk";

if (Board.isOnDevice) {
  Board.input.subscribe((contacts) => {
    const pieces = contacts.filter((c) => c.type === BoardContactType.Glyph);
    // Update game state from piece contactId, glyphId, x, y, orientation, phase.
  });
}
```

- Treat `Board.isOnDevice === false` as the normal browser preview path.
- Never call Board APIs off-device unless guarded, because bridge-backed APIs throw.
- Use browser preview for layout, game UI, and syntax checks; use a Board device or harness for bridge behavior.
- Treat `Board.input.subscribe` as a frame stream. Contacts persist across frames; a stationary piece reports until it ends.
- Diff by `contactId` and `phase`; filter `BoardContactType.Glyph` for physical pieces.
- Use `Board.bridgeVersion ?? 0` to feature-gate newer host APIs.
- Use `Board.session` for players, `Board.save` for save payloads, `Board.pause` for pause menu integration, and `Board.avatar` for player avatar images.

## Build And Run

Browser-only loop, after dependencies are already installed or the user approves installing them:

```bash
cd example
npm run dev
```

Production web build:

```bash
cd example
npm run build
```

Harness APK:

```bash
cd example
npm run build
cd ../sample
./gradlew assembleDebug
```

Raw bridge tester:

```bash
cd sample
./gradlew assembleDebug -Pweb=raw
```

Install APK:

```bash
adb install sample/app/build/outputs/apk/debug/app-debug.apk
```

## Gotchas

- The native bridge exists only inside the Board WebView or harness. A normal browser should show an off-device path.
- The harness loads built output from `example/dist` into `https://appassets.androidplatform.net/...`.
- Physical pieces can also create pointer-like activity in app UI. Filter the SDK contact stream by contact type, and guard canvas/UI pointer handlers as needed.
- The Gradle wrapper is included; system Gradle is not required.
- Android harness builds require JDK 17+ and Android SDK platform 34.
