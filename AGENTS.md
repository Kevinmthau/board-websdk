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
- `example/`: Vite + TypeScript starter. Prefer this as the fork point for games.
- `harrishill-board-sdk-0.1.0.tgz`: Local npm package used by `example/package.json`.
- `board-sdk/`: Flat ESM and `.d.ts` SDK files for non-bundler integrations.
- `sample/`: Android harness Gradle project that bakes `example/dist` into an APK.
- `board-web-sdk-harness-debug.apk`: Prebuilt harness APK with the bundled example.
- `skills/board-web-sdk/`: Repo-local Codex skill for building with this SDK.

## Game Workflow

1. Read `README.md`, `example/src/main.ts`, and the relevant `board-sdk/*.d.ts` files before changing SDK usage.
2. Keep game code TypeScript/ESM-compatible unless the user asks for another stack.
3. Import SDK APIs from `@harrishill/board-sdk` when using a bundler.
4. Always guard SDK calls with `Board.isOnDevice`. In normal browsers, Board APIs throw because the native bridge is absent.
5. Keep browser preview useful off-device for layout, game UI, and syntax checks. Simulate input only in app code, never by pretending the bridge exists.
6. Treat `Board.input.subscribe` as a frame stream. Contacts persist across frames; diff by `contactId` and `phase`, and filter `BoardContactType.Glyph` for physical pieces.
7. Use `Board.bridgeVersion ?? 0` to gate newer host-bridge features.
8. Preserve `vite.config.ts` relative asset behavior so Android asset loading keeps working.

## Verification

- Browser build: `cd example && npm run build`
- Browser dev server: `cd example && npm run dev`
- Harness APK: build the web app first, then `cd sample && ./gradlew assembleDebug`
- Raw bridge harness: `cd sample && ./gradlew assembleDebug -Pweb=raw`
- Install APK: `adb install sample/app/build/outputs/apk/debug/app-debug.apk`

If verification fails because local software is missing, run the preflight script again and prompt the user with the missing items.
