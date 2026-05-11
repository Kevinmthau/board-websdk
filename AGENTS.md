# Board Web SDK Agent Guide

## Scope

These instructions apply to the whole repository.

## Local Preflight

Before creating a game with this SDK, or before turning `example/` into a game, run:

```bash
skills/board-web-sdk/scripts/check-local-tools.sh --mode game
```

Use `--mode browser` only for browser-only UI/code work, and `--mode harness` for Android harness or Board-device validation work.

If the check reports missing tools, SDKs, or local dependencies, stop before doing work that depends on them and ask the user whether they want the missing items installed or configured. Do not run installers, `npm install`, Android SDK downloads, or other networked setup without user approval.

## Repo Map

- `README.md`: Canonical SDK handoff and workflow documentation.
- `scripts/create-game.sh`: First-class game scaffold command. Use this to create sibling game projects with unique app identity.
- `example/`: Vite + TypeScript starter copied into generated games as `web/`.
- `harrishill-board-sdk-0.1.0.tgz`: Local npm package used by `example/package.json`.
- `board-sdk/`: Flat ESM and `.d.ts` SDK files for non-bundler integrations.
- `sample/`: Generic vendor Android harness Gradle project. Keep it as the SDK test harness only; do not use its package identity for real games.
- `board-web-sdk-harness-debug.apk`: Prebuilt harness APK with the bundled example.
- `skills/board-web-sdk/`: Repo-local Codex skill for building with this SDK.

## Game Workflow

1. Run the local preflight for game work.
2. Create real games with `./scripts/create-game.sh --name "Game Name" --slug game-slug --package com.yourname.gameslug`. This creates `../<slug>/web/`, `../<slug>/android/`, `../<slug>/vendor/`, `../<slug>/scripts/build_android.sh`, `../<slug>/AGENTS.md`, and `../<slug>/README.md`.
3. In sibling generated game repos, read that game's `AGENTS.md` before editing. It records the package id, Board app id, APK output path, and model path for that game.
4. Do not turn `sample/` into a real game package. `sample/` is only the generic SDK harness and keeps the vendor test identity.
5. Treat Android app identity as the package/application id, not the display label. Changing only the label does not create a distinct APK install identity.
6. Read `README.md`, `example/src/main.ts`, and the relevant `board-sdk/*.d.ts` files before changing SDK usage.
7. Keep game code TypeScript/ESM-compatible unless the user asks for another stack.
8. Import SDK APIs from `@harrishill/board-sdk` when using a bundler.
9. Always guard SDK calls with `Board.isOnDevice`. In normal browsers, Board APIs throw because the native bridge is absent.
10. Keep browser preview useful off-device for layout, game UI, and syntax checks. Simulate gameplay input in app code, never by pretending the bridge exists or forcing `Board.isOnDevice`.
11. Treat `Board.input.subscribe` as a frame stream. Contacts persist across frames; maintain live physical pieces by `contactId` and `phase`, filter `BoardContactType.Glyph`, and treat `glyphId` only as the piece/type id.
12. Use `Board.bridgeVersion ?? 0` to gate newer host-bridge features.
13. Preserve `vite.config.ts` relative asset behavior so Android asset loading from `https://appassets.androidplatform.net/...` keeps working.
14. Preserve the Android wrapper setup order: initialize `BoardNativePlugin` context and app id, load `model.tflite`, activate `RawDataGlyphDetector`, then create/register the WebView bridge and touch channel.

## Verification

- Generated project helper: `cd ../<slug> && ./scripts/build_android.sh`
- Generated browser build: `cd ../<slug>/web && npm run build`
- Browser dev server: `cd example && npm run dev`
- Generated APK: build the web app first, then `cd ../<slug>/android && ./gradlew assembleDebug`
- Raw bridge harness: `cd sample && ./gradlew assembleDebug -Pweb=raw`
- Preferred Board-device loop: `bdb status`, then `cd ../<slug> && ./scripts/build_android.sh --install --launch`
- Fallback install generated APK: `adb install ../<slug>/Builds/Android/<slug>-debug.apk`

If verification fails because local software is missing, run the preflight script again and prompt the user with the missing items.
