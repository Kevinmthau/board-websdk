import { Board, BoardContactType } from "@harrishill/board-sdk";

// -----------------------------------------------------------------------------
// Status header: always renders, even off-device.
// -----------------------------------------------------------------------------

const statusEl = document.getElementById("status")!;
function renderStatus(): void {
  const on = Board.isOnDevice;
  statusEl.innerHTML = `
    <strong>isOnDevice</strong> <span class="${on ? "yes" : "no"}">${on ? "true" : "false"}</span><br>
    <strong>sdkVersion</strong> ${Board.sdkVersion}<br>
    <strong>bridgeVersion</strong> ${Board.bridgeVersion ?? "n/a"}
  `;
}
renderStatus();

if (!Board.isOnDevice) {
  document.body.classList.add("offline");
  console.info(
    "Not running on a Board. Install the harness APK from ../sample/ and " +
      "point it at this page (or drop the built dist/ into its assets) to see " +
      "the SDK live.",
  );
} else {
  wireTouchCanvas();
  wireSession();
  wireSaves();
  wirePauseMenu();
}

// -----------------------------------------------------------------------------
// Touch / piece input: draw contacts on a full-screen canvas.
// -----------------------------------------------------------------------------

function wireTouchCanvas(): void {
  const canvas = document.getElementById("touch-canvas") as HTMLCanvasElement;
  const ctx = canvas.getContext("2d")!;

  function resize(): void {
    canvas.width = canvas.clientWidth * devicePixelRatio;
    canvas.height = canvas.clientHeight * devicePixelRatio;
    ctx.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
  }
  resize();
  window.addEventListener("resize", resize);

  Board.input.subscribe((contacts) => {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    for (const c of contacts) {
      const isPiece = c.type === BoardContactType.Glyph;
      ctx.fillStyle = isPiece ? "rgba(255, 107, 157, 0.85)" : "rgba(0, 210, 255, 0.85)";
      ctx.beginPath();
      ctx.arc(c.x, c.y, isPiece ? 28 : 20, 0, Math.PI * 2);
      ctx.fill();

      if (isPiece) {
        // Indicate orientation with a short line from center.
        const rad = (c.orientation * Math.PI) / 180;
        ctx.strokeStyle = "#fff";
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.moveTo(c.x, c.y);
        ctx.lineTo(c.x + Math.cos(rad) * 28, c.y + Math.sin(rad) * 28);
        ctx.stroke();

        ctx.fillStyle = "#fff";
        ctx.font = "13px ui-monospace, monospace";
        ctx.fillText(`#${c.glyphId}`, c.x + 34, c.y + 4);
      }
    }
  });
}

// -----------------------------------------------------------------------------
// Session: show players, open selector, open profile switcher.
// -----------------------------------------------------------------------------

function wireSession(): void {
  const playersEl = document.getElementById("players")!;

  function render(): void {
    const players = Board.session.getPlayers();
    playersEl.innerHTML = players.length
      ? players
          .map((p) => `<li>${escapeHtml(p.name)} <em>(${p.type})</em></li>`)
          .join("")
      : "<li><em>No players in session</em></li>";
  }
  render();

  document.getElementById("add-player-btn")!.addEventListener("click", async () => {
    await Board.session.presentAddPlayer();
    render();
  });
  document.getElementById("switcher-btn")!.addEventListener("click", () => {
    Board.session.showProfileSwitcher();
  });
}

// -----------------------------------------------------------------------------
// Saves: list + create a throwaway save.
// -----------------------------------------------------------------------------

function wireSaves(): void {
  const savesEl = document.getElementById("saves")!;

  async function render(): Promise<void> {
    try {
      const saves = await Board.save.list();
      savesEl.innerHTML = saves.length
        ? saves
            .map(
              (s) =>
                `<li>${escapeHtml(s.description)} <em>(${s.fileSize}B, v${escapeHtml(s.gameVersion)})</em></li>`,
            )
            .join("")
        : "<li><em>No saves yet</em></li>";
    } catch (err) {
      savesEl.innerHTML = `<li><em>Error: ${escapeHtml(String(err))}</em></li>`;
    }
  }
  void render();

  document.getElementById("create-save-btn")!.addEventListener("click", async () => {
    const payload = new TextEncoder().encode(
      JSON.stringify({ createdAt: Date.now(), note: "hello from the example" }),
    );
    await Board.save.create(`Test ${new Date().toLocaleTimeString()}`, payload, 0, "0.1.0");
    await render();
  });
  document.getElementById("refresh-saves-btn")!.addEventListener("click", () => {
    void render();
  });
}

// -----------------------------------------------------------------------------
// Pause menu: configure context, poll for results.
// -----------------------------------------------------------------------------

function wirePauseMenu(): void {
  const resultEl = document.getElementById("pause-result")!;

  document.getElementById("configure-pause-btn")!.addEventListener("click", () => {
    Board.pause.setContext({
      gameName: "SDK Example",
      offerSaveOption: true,
      customButtons: [
        { id: "help", title: "Help", icon: "square" },
        { id: "restart", title: "Restart", icon: "circulararrow" },
      ],
      audioTracks: [
        { id: "music", name: "Music", value: 80 },
        { id: "sfx", name: "Sound effects", value: 90 },
      ],
    });
    resultEl.innerHTML = "<em>Pause context set. Open the system pause menu to interact.</em>";
  });

  document.getElementById("clear-pause-btn")!.addEventListener("click", () => {
    Board.pause.clearContext();
    resultEl.innerHTML = "<em>Pause context cleared.</em>";
  });

  setInterval(() => {
    const result = Board.pause.pollResult();
    if (result) {
      resultEl.textContent = JSON.stringify(result, null, 2);
    }
  }, 500);
}

// -----------------------------------------------------------------------------

function escapeHtml(s: string): string {
  const replacements: Record<string, string> = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  };
  return s.replace(
    /[&<>"']/g,
    (c) => replacements[c],
  );
}
