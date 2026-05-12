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
- `scripts/create-game.sh`: First-class game scaffold command. Use this to create projects under the workspace `games/` directory with unique app identity.
- `scripts/update-game-sdk.sh`: Updates an existing generated game to a selected vendored SDK tarball and refreshes its web lockfile.
- `example/`: Vite + TypeScript starter copied into generated games as `web/`.
- `harrishill-board-sdk-0.1.0.tgz`: Local npm package used by `example/package.json`.
- `board-sdk/`: Flat ESM and `.d.ts` SDK files for non-bundler integrations.
- `sample/`: Generic vendor Android harness Gradle project. Keep it as the SDK test harness only; do not use its package identity for real games.
- `board-web-sdk-harness-debug.apk`: Prebuilt harness APK with the bundled example.
- `skills/board-web-sdk/`: Repo-local Codex skill for building with this SDK.

## Game Workflow

1. Run the local preflight for game work.
2. Create real games with `./scripts/create-game.sh --name "Game Name" --slug game-slug --package com.yourname.gameslug`. This creates `../games/<slug>/web/`, `../games/<slug>/android/`, `../games/<slug>/vendor/`, `../games/<slug>/scripts/build_android.sh`, `../games/<slug>/AGENTS.md`, and `../games/<slug>/README.md`.
3. Treat each generated game under `../games/` as its own Git repository. The scaffold initializes a local `main` repo by default; create the remote manually with `gh repo create <slug> --private --source . --remote origin --push` or the equivalent `git remote add origin ...`.
4. In generated game repos under `../games/`, read that game's `AGENTS.md` before editing. It records the package id, Board app id, APK output path, model path, and vendored SDK tarball for that game.
5. Do not turn `sample/` into a real game package. `sample/` is only the generic SDK harness and keeps the vendor test identity.
6. Treat Android app identity as the package/application id, not the display label. Changing only the label does not create a distinct APK install identity.
7. Read `README.md`, `example/src/main.ts`, and the relevant `board-sdk/*.d.ts` files before changing SDK usage.
8. Keep game code TypeScript/ESM-compatible unless the user asks for another stack.
9. Import SDK APIs from `@harrishill/board-sdk` when using a bundler.
10. Update an existing game's vendored SDK from this repo with `./scripts/update-game-sdk.sh --game ../games/<slug>`; review and commit those changes from the game repo.
11. Always guard SDK calls with `Board.isOnDevice`. In normal browsers, Board APIs throw because the native bridge is absent.
12. Keep browser preview useful off-device for layout, game UI, and syntax checks. Simulate gameplay input in app code, never by pretending the bridge exists or forcing `Board.isOnDevice`.
13. Treat `Board.input.subscribe` as a frame stream. Contacts persist across frames; maintain live physical pieces by `contactId` and `phase`, filter `BoardContactType.Glyph`, and treat `glyphId` only as the piece/type id.
    Do not handle physical pieces like finger taps, pointer events, or one-shot touch events; pieces are persistent glyph contacts tracked across frames by `contactId`.
14. Use `Board.bridgeVersion ?? 0` to gate newer host-bridge features.
15. Preserve `vite.config.ts` relative asset behavior so Android asset loading from `https://appassets.androidplatform.net/...` keeps working.
16. Preserve the Android wrapper setup order: initialize `BoardNativePlugin` context and app id, load `model.tflite`, activate `RawDataGlyphDetector`, then create/register the WebView bridge and touch channel.

## Verification

- Generated project helper: `cd ../games/<slug> && ./scripts/build_android.sh`
- Generated browser build: `cd ../games/<slug>/web && npm run build`
- Browser dev server: `cd example && npm run dev`
- Generated APK: build the web app first, then `cd ../games/<slug>/android && ./gradlew assembleDebug`
- Raw bridge harness: `cd sample && ./gradlew assembleDebug -Pweb=raw`
- Preferred Board-device loop: `bdb status`, then `cd ../games/<slug> && ./scripts/build_android.sh --install --launch`
- Fallback install generated APK: `adb install ../games/<slug>/Builds/Android/<slug>-debug.apk`

If verification fails because local software is missing, run the preflight script again and prompt the user with the missing items.
