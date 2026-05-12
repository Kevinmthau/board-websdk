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
| `sample/` | Generic Android SDK harness Gradle project. Keep this as the vendor test harness only; do not use its package identity for a real game. Generated games receive their own copy under `../games/<slug>/android/`. |
| `scripts/create-game.sh` | First-class game scaffold command. Creates a game directory under the workspace `games/` folder with unique Android package id, app label, Board app id, and web build path. |
| `scripts/update-game-sdk.sh` | Copies a versioned SDK tarball into an existing generated game, updates `web/package.json`, and refreshes `web/package-lock.json`. |
| `board-web-sdk-harness-debug.apk` | Pre-built APK of the harness with the included `example/` baked in. Sideload onto an arm64 Android 10+ device or arm64 emulator image to sanity-check that the SDK works end-to-end before you start iterating. |

## Create a game scaffold

Create real games with the scaffold command instead of editing `sample/` in place:

```bash
./scripts/create-game.sh \
  --name "Game Name" \
  --slug game-slug \
  --package com.yourname.gameslug
```

This creates a game project in the workspace `games/` directory:

```text
../games/game-slug/
  web/
  android/
  vendor/
  scripts/build_android.sh
  AGENTS.md
  README.md
```

The generated Android project gets `applicationId` and `namespace` set to the package id, the Java package moved to the same package, the app label set to the display name, and `BoardNativePlugin.setAppId(...)` set to the slug. The Android build copies from `../games/game-slug/web/dist` by default.

Generated projects also include a game-local `AGENTS.md` and `scripts/build_android.sh`. Use those from inside the game repo instead of editing this SDK bundle's `sample/` harness in place.

Generated projects are intended to be their own Git repositories. `create-game.sh`
initializes a local `main` branch and attempts an initial scaffold commit by
default; pass `--no-git` only when you want a plain directory. Create the GitHub
remote manually after reviewing the scaffold:

```bash
cd ../games/game-slug
gh repo create game-slug --private --source . --remote origin --push
```

Without GitHub CLI:

```bash
git remote add origin git@github.com:<owner>/game-slug.git
git push -u origin main
```

Android app identity is the package/application id, not the display label. Changing only `android:label` makes the launcher name different, but Android still treats APKs with the same `applicationId` as the same app.

## Update a generated game's SDK

Generated games vendor the SDK npm tarball in `vendor/` and reference it from
`web/package.json`. After updating the SDK bundle's tarball, push that version
into a game with:

```bash
./scripts/update-game-sdk.sh --game ../games/game-slug
```

If there is more than one SDK tarball in this repo, select one explicitly:

```bash
./scripts/update-game-sdk.sh \
  --game ../games/game-slug \
  --sdk-tarball harrishill-board-sdk-0.1.0.tgz
```

The helper updates the package lock but does not commit in the game repo. Review
and commit the game-side changes from that game directory.

## Two ways to develop

### Browser-only (fastest loop, no device)

```bash
cd example
npm install
npm run dev
```

Opens at <http://localhost:5173>. `Board.isOnDevice` is `false`, bridge-backed sections are disabled, and the canvas uses separate simulated app input. This mode is for layout, styling, wiring, and syntax-checking your SDK calls without pretending the bridge exists.

### On a Board device (or the harness APK on arm64 Android)

The bridge only exists inside a Board WebView. Two paths:

1. **Pre-built harness APK.** Install `board-web-sdk-harness-debug.apk` on an arm64 Android 10+ device or arm64 emulator image. The bundled example will load with `Board.isOnDevice === true`, so you can confirm bridges, touch input, and APIs all work before touching the build pipeline.

2. **Your own generated game build.** When you want to iterate on your own code, use the generated helper from the game root:

   ```bash
   cd ../games/game-slug

   # Build web/dist, assemble Android, and copy the APK to Builds/Android/
   ./scripts/build_android.sh

   # Recommended Board-device loop when bdb is installed
   bdb status
   ./scripts/build_android.sh --install --launch

   # Fallback install path
   adb install Builds/Android/game-slug-debug.apk
   ```

   The generated Android wrapper expects the built web output at `../games/game-slug/web/dist`. `sample/` remains the generic SDK harness and should not be used as a real game's APK identity.

   The Android wrapper APK is arm64-only because the bundled native bridge AAR ships `arm64-v8a` libraries. The default x86_64 Android Emulator cannot install it unless matching x86_64 native artifacts are added.

   Use `./scripts/build_android.sh --web-target raw` or set `-Pweb=raw` on the Gradle command to load `android/app/src/main/assets/index.html` (a hand-rolled tabbed test page) instead of your built web app — useful for poking the bridge directly without the TS SDK in the middle.

3. **A real Board device.** Same as option 2, but the host OS provides the bridge — you don't need the harness APK at all once the device-side WebView host is wired to load your build.

### Android wrapper initialization order

The generated wrapper models the required native setup order:

1. Create `WebViewBoardContext`, attach the `Activity`, call `BoardNativePlugin.setBoardContext(...)`, set the game-specific app id, then call `BoardNativePlugin.initialize()`.
2. Load `model.tflite`, create `TrackerParameters`, and activate `RawDataGlyphDetector`.
3. Create and configure the `WebView`, register `BoardJsBridge` as `window.BoardSDK`, register `BoardTouchChannel` for `https://appassets.androidplatform.net`, then load the generated asset URL.

## Minimal usage

```ts
import {
  Board,
  BoardContactPhase,
  BoardContactType,
  type BoardContact,
} from "@harrishill/board-sdk";

const livePieces = new Map<number, BoardContact>();

if (Board.isOnDevice) {
  // Board.input.subscribe is a live frame stream, not only an event stream.
  Board.input.subscribe((contacts) => {
    for (const c of contacts) {
      if (c.type !== BoardContactType.Glyph) {
        continue;
      }

      if (c.phase === BoardContactPhase.Ended || c.phase === BoardContactPhase.Canceled) {
        livePieces.delete(c.contactId);
      } else {
        livePieces.set(c.contactId, c);
      }
    }

    for (const piece of livePieces.values()) {
      console.log(
        `contact ${piece.contactId} uses glyph ${piece.glyphId} at (${piece.x}, ${piece.y})`,
      );
    }
  });

  // Configure the system pause menu
  Board.pause.setContext({
    gameName: "My Game",
    offerSaveOption: true,
  });
}
```

Use `contactId` as the stable physical contact instance for a piece on the surface. Use `glyphId` only as the classifier's piece/type id; multiple physical pieces can share a glyph class, and the same glyph can appear again later with a different `contactId`.

`example/src/main.ts` shows every namespace in the same file with small readable sections — that's the place to look for working call patterns.

## API surface

| Namespace | Purpose |
|---|---|
| `Board.input` | Finger + piece (Glyph) contacts, delivered as a live sensor frame stream. |
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
2. **Track pieces by `contactId`, not `glyphId`.** `contactId` is the current physical contact instance. `glyphId` is the detected piece class/type.
3. **Contacts persist across frames.** A piece sitting still reports every frame with phase `Stationary` until lifted (`Ended`). Don't treat every frame as a new event — maintain current state keyed by `contactId` and prune `Ended`/`Canceled` contacts.
4. **Built output is loaded over `https://appassets.androidplatform.net/...`.** The harness uses `WebViewAssetLoader` with that origin; design system features that depend on `location.origin`, absolute paths, cookies, or storage origin accordingly.
5. **Vite needs `base: "./"` for Android assets.** Absolute asset paths can work in dev and still fail when the built app is loaded from the APK asset origin.
6. **The native bridge is arm64-only in this bundle.** Use an arm64 Android device or arm64 emulator image for APK validation unless you add matching x86_64 native artifacts.

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
