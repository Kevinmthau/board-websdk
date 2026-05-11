# Board Web SDK — alpha handoff

Alpha drop of the Board Web SDK for partners building **web apps that run on Board**, the tabletop gaming platform with physical-piece tracking.

## How the pieces fit together

```
Board device (or the harness APK in this bundle, on arm64 Android 10+)
  └─ WebView, with bridge injected by the host
      └─ Your web app
          └─ import { Board } from "@harrishill/board-sdk"
              └─ host injects window.BoardSDK + window.boardTouch
```

Anywhere `window.BoardSDK` is present, `Board.isOnDevice` is `true` and the SDK works without further setup. In a normal browser it's `false` and any API call throws — gate your code behind `Board.isOnDevice` so the same bundle runs both places.

## What's in this bundle

| Path | What it is |
|---|---|
| `example/` | Vite + TypeScript starter project. `scripts/create-game.sh` copies this into a new game's `web/` directory. Every SDK namespace (input, session, save, pause) is wired up in `src/main.ts` for reference. |
| `harrishill-board-sdk-0.1.0.tgz` | The SDK as an npm tarball. `example/`'s `package.json` references it via `file:../harrishill-board-sdk-0.1.0.tgz`; generated games use `file:../vendor/harrishill-board-sdk-0.1.0.tgz`. |
| `board-sdk/` | The same SDK as flat `.js` + `.d.ts` files, for non-bundler use (drop-in `<script type="module">`, Foundry-style modules, etc.). |
| `sample/` | Generic Android SDK harness Gradle project. Keep this as the vendor test harness only; do not use its package identity for a real game. Generated games receive their own copy under `../<slug>/android/`. |
| `scripts/create-game.sh` | First-class game scaffold command. Creates a sibling game directory with unique Android package id, app label, Board app id, and web build path. |
| `board-web-sdk-harness-debug.apk` | Pre-built APK of the harness with the included `example/` baked in. Sideload onto an arm64 Android 10+ device or arm64 emulator image to sanity-check that the SDK works end-to-end before you start iterating. |

## Create a game scaffold

Create real games with the scaffold command instead of editing `sample/` in place:

```bash
./scripts/create-game.sh \
  --name "Game Name" \
  --slug game-slug \
  --package com.yourname.gameslug
```

This creates a sibling project next to this SDK bundle:

```text
../game-slug/
  web/
  android/
  vendor/
  README.md
```

The generated Android project gets `applicationId` and `namespace` set to the package id, the Java package moved to the same package, the app label set to the display name, and `BoardNativePlugin.setAppId(...)` set to the slug. The Android build copies from `../game-slug/web/dist` by default.

Android app identity is the package/application id, not the display label. Changing only `android:label` makes the launcher name different, but Android still treats APKs with the same `applicationId` as the same app.

## Two ways to develop

### Browser-only (fastest loop, no device)

```bash
cd example
npm install
npm run dev
```

Opens at <http://localhost:5173>. `Board.isOnDevice` is `false` and the interactive sections are disabled. This mode is for layout, styling, wiring, and syntax-checking your SDK calls.

### On a Board device (or the harness APK on arm64 Android)

The bridge only exists inside a Board WebView. Two paths:

1. **Pre-built harness APK.** Install `board-web-sdk-harness-debug.apk` on an arm64 Android 10+ device or arm64 emulator image. The bundled example will load with `Board.isOnDevice === true`, so you can confirm bridges, touch input, and APIs all work before touching the build pipeline.

2. **Your own generated game build.** When you want to iterate on your own code:

   ```bash
   # 1. Build your web app
   cd ../game-slug/web
   npm install
   npm run build       # produces web/dist

   # 2. Build this game's Android wrapper — it copies web/dist into APK assets
   cd ../android
   ./gradlew assembleDebug

   # 3. Install
   adb install app/build/outputs/apk/debug/app-debug.apk
   ```

   The generated Android wrapper expects the built web output at `../game-slug/web/dist`. `sample/` remains the generic SDK harness and should not be used as a real game's APK identity.

   The Android wrapper APK is arm64-only because the bundled native bridge AAR ships `arm64-v8a` libraries. The default x86_64 Android Emulator cannot install it unless matching x86_64 native artifacts are added.

   Set `-Pweb=raw` on the Gradle command to load `android/app/src/main/assets/index.html` (a hand-rolled tabbed test page) instead of your built web app — useful for poking the bridge directly without the TS SDK in the middle.

3. **A real Board device.** Same as option 2, but the host OS provides the bridge — you don't need the harness APK at all once the device-side WebView host is wired to load your build.

## Minimal usage

```ts
import { Board, BoardContactType } from "@harrishill/board-sdk";

if (Board.isOnDevice) {
  // Touch and piece input, ~60 fps
  Board.input.subscribe((contacts) => {
    for (const c of contacts) {
      if (c.type === BoardContactType.Glyph) {
        console.log(`Piece ${c.glyphId} at (${c.x}, ${c.y}) rotation ${c.orientation}°`);
      }
    }
  });

  // Configure the system pause menu
  Board.pause.setContext({
    gameName: "My Game",
    offerSaveOption: true,
  });
}
```

`example/src/main.ts` shows every namespace in the same file with small readable sections — that's the place to look for working call patterns.

## API surface

| Namespace | Purpose |
|---|---|
| `Board.input` | Finger + piece (Glyph) contacts, delivered at sensor frame rate. |
| `Board.session` | Multiplayer session: players, guest add/remove, profile switcher. |
| `Board.save` | Save-game create/load/update/delete, cover images, storage limits. |
| `Board.pause` | System pause menu: custom buttons, audio track sliders, result polling. |
| `Board.avatar` | Load player avatar images as data URIs. |
| `Board.isOnDevice` | `true` when the bridge is present. Always check first. |
| `Board.sdkVersion` | SDK semver string. |
| `Board.bridgeVersion` | Host bridge API version, for feature gating across OS releases. |

## Forward/backward compatibility

The SDK ships in your app. The bridge ships in the host OS. They update independently:

| Scenario | Behavior |
|---|---|
| Old SDK + New OS | Existing apps continue to work. |
| New SDK + Old OS | New methods degrade or throw a clear error. Use `Board.bridgeVersion` to feature-gate. |
| New SDK + New OS | Full feature set. |

```ts
if ((Board.bridgeVersion ?? 0) >= 2) {
  // call a V2-only API safely
}
```

`Board.bridgeVersion` may return `0` on current builds where the host hasn't implemented `getApiVersion()` yet. `(Board.bridgeVersion ?? 0) >= N` is the safe pattern.

## Known gotchas

1. **Glyph base conductivity.** Pieces register as multi-touch points. If your app uses pointer events for UI, you may see piece contacts firing pointer drags — filter by `BoardContactType` on the touch stream and/or suppress pointer events over your game canvas.
2. **Contacts persist across frames.** A piece sitting still reports every frame with phase `Stationary` until lifted (`Ended`). Don't treat every frame as a new event — diff by `id` + `phase`.
3. **Built output is loaded over `https://appassets.androidplatform.net/...`.** The harness uses `WebViewAssetLoader` with that origin; design system features that depend on `location.origin` accordingly.

## Requirements

- Node 18+ (build toolchain)
- Any modern ESM-compatible bundler (Vite, webpack 5, esbuild, rollup, Parcel) — the example uses Vite
- For Android builds: JDK 17, Android SDK with `compileSdk 34`, Gradle is wrapped in `sample/gradlew` and generated `android/gradlew`
- A Board device, the bundled harness APK, or the browser preview, for runtime

## Documentation

- Full developer docs: <https://docs.dev.board.fun/>
- Developer portal: <https://dev.board.fun/>
- Contact: hello@board.fun

APIs may shift before 1.0. Reach out with anything rough.

## License

See `board-sdk/` and the SDK tarball for the LICENSE file. Full license terms are published at <https://docs.dev.board.fun/more/license>.
