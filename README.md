# Board Web SDK — alpha handoff

Alpha drop of the Board Web SDK for partners building **web apps that run on Board**, the tabletop gaming platform with physical-piece tracking.

## How the pieces fit together

```
Board device (or the harness APK in this bundle, on any Android 10+)
  └─ WebView, with bridge injected by the host
      └─ Your web app
          └─ import { Board } from "@harrishill/board-sdk"
              └─ host injects window.BoardSDK + window.boardTouch
```

Anywhere `window.BoardSDK` is present, `Board.isOnDevice` is `true` and the SDK works without further setup. In a normal browser it's `false` and any API call throws — gate your code behind `Board.isOnDevice` so the same bundle runs both places.

## What's in this bundle

| Path | What it is |
|---|---|
| `example/` | Vite + TypeScript starter project. Use this as your fork point — every SDK namespace (input, session, save, pause) is wired up in `src/main.ts` for reference. |
| `harrishill-board-sdk-0.1.0.tgz` | The SDK as an npm tarball. `example/`'s `package.json` already references it via `file:../harrishill-board-sdk-0.1.0.tgz`. |
| `board-sdk/` | The same SDK as flat `.js` + `.d.ts` files, for non-bundler use (drop-in `<script type="module">`, Foundry-style modules, etc.). |
| `sample/` | Android harness Gradle project. Bakes your `example/dist` into an APK and serves it in a WebView with the Board bridge injected. Vendored AAR under `sample/app/libs/`. |
| `board-web-sdk-harness-debug.apk` | Pre-built APK of the harness with the included `example/` baked in. Sideload onto any Android 10+ device or emulator to sanity-check that the SDK works end-to-end before you start iterating. |

## Two ways to develop

### Browser-only (fastest loop, no device)

```bash
cd example
npm install
npm run dev
```

Opens at <http://localhost:5173>. `Board.isOnDevice` is `false` and the interactive sections are disabled. This mode is for layout, styling, wiring, and syntax-checking your SDK calls.

### On a Board device (or the harness APK on any Android)

The bridge only exists inside a Board WebView. Two paths:

1. **Pre-built harness APK.** Install `board-web-sdk-harness-debug.apk` on any Android 10+ device or emulator. The bundled example will load with `Board.isOnDevice === true`, so you can confirm bridges, touch input, and APIs all work before touching the build pipeline.

2. **Your own build through the harness.** When you want to iterate on your own code:

   ```bash
   # 1. Build your web app
   cd example          # or your fork of it
   npm install
   npm run build       # produces example/dist

   # 2. Build the harness — it copies example/dist into APK assets
   cd ../sample
   ./gradlew assembleDebug

   # 3. Install
   adb install app/build/outputs/apk/debug/app-debug.apk
   ```

   The harness expects your web app's built output at `<bundle root>/example/dist`. Either keep your project named `example/` next to `sample/`, or edit the `from '../../example/dist'` line in `sample/app/build.gradle`.

   Set `-Pweb=raw` on the Gradle command to load `sample/app/src/main/assets/index.html` (a hand-rolled tabbed test page) instead of your built example — useful for poking the bridge directly without the TS SDK in the middle.

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
- For the harness build: JDK 17, Android SDK with `compileSdk 34`, Gradle is wrapped in `sample/gradlew`
- A Board device, the bundled harness APK, or the browser preview, for runtime

## Documentation

- Full developer docs: <https://docs.dev.board.fun/>
- Developer portal: <https://dev.board.fun/>
- Contact: hello@board.fun

APIs may shift before 1.0. Reach out with anything rough.

## License

See `board-sdk/` and the SDK tarball for the LICENSE file. Full license terms are published at <https://docs.dev.board.fun/more/license>.
