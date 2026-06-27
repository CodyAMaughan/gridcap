# gridcap

A headless macOS CLI for **recording individual windows** — one MP4 per window, all
captured at once and kept frame-synced — built on
[ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) and
AVFoundation.

macOS gives you the building blocks (ScreenCaptureKit, `screencapture`) but no
command-line tool that records *multiple specific windows simultaneously, each to its
own file*, that you can drive from a script or an AI agent. `gridcap` is that tool.
Every command speaks JSON on stdout, runs without a GUI, and a recording session can be
paused, resumed, and reshaped (add/remove windows) while it runs over a control socket.

## Features

- **Per-window capture** — record one or many windows, each to a separate MP4.
- **Frame-synced** — all windows in a session share one reference clock, so the files
  line up in time.
- **Live session control** — `pause`, `resume`, `add-window`, `remove-window`, and
  `status` against a running recording, over a Unix domain socket.
- **Continuous timeline across pauses** — paused frames are dropped, but the output
  timeline stays gap-free.
- **Window management** — `list` enumerates windows as JSON; `arrange` moves/resizes a
  window before you record it.
- **Stills too** — `screenshot` captures a single window to PNG.
- **Headless & scriptable** — JSON on stdout, status/diagnostics on stderr, no GUI. Runs
  fine when spawned from a non-interactive shell (e.g. by an IDE agent).

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.7+ toolchain (Xcode 14+ or the Swift toolchain) to build

## Permissions

`gridcap` needs two macOS privacy grants. The terminal app you run it from (Terminal,
iTerm2, etc.) is what actually gets listed in System Settings — grant it there.

| Permission | Needed for | Where to grant |
|---|---|---|
| **Screen Recording** | `list`, `screenshot`, `record` | System Settings → Privacy & Security → Screen Recording |
| **Accessibility** | `arrange` (moving/resizing windows) | System Settings → Privacy & Security → Accessibility |

Check what's currently granted:

```bash
gridcap list --check-permission
# { "accessibility": "granted", "screen_recording": "granted" }
```

If Screen Recording was just enabled, fully quit and reopen your terminal so the new
grant takes effect.

## Build & install

```bash
swift build -c release
# binary at .build/release/gridcap

# optional: put it on your PATH
cp .build/release/gridcap /usr/local/bin/
```

## Usage

The normal flow is **list → (optionally) arrange → record → stop**.

### 1. Find the windows you want

```bash
gridcap list
gridcap list --app-filter Safari    # case-insensitive substring on app or title
```

```json
[
  {
    "window_id": 12345,
    "title": "GitHub — Safari",
    "app_name": "Safari",
    "app_bundle_id": "com.apple.Safari",
    "bounds": { "x": 0, "y": 0, "width": 1440, "height": 900 }
  }
]
```

### 2. (Optional) Arrange a window before recording

```bash
gridcap arrange 12345 --x 0 --y 0 --width 1280 --height 720
```

### 3. Record one or more windows

```bash
# Record two windows for 30s into ./out (each becomes its own MP4)
gridcap record --windows 12345,67890 --output-dir ./out --duration 30

# Record indefinitely until you stop it; name the session yourself
gridcap record --windows 12345 --output-dir ./out --session-id demo
```

Files are written as `window_<id>_<session>.mp4`. When recording finishes, `record`
prints a JSON summary on stdout:

```json
{
  "status": "ok",
  "session_id": "demo",
  "recordings": [
    { "window_id": 12345, "file": "/path/out/window_12345_demo.mp4", "duration_seconds": 30.0 }
  ]
}
```

Add `--verbose` to stream per-frame diagnostics to stderr (otherwise stderr only carries
a few status lines and stdout stays clean JSON). Default frame rate is 30 fps
(`--fps` to change).

### 4. Control a running session

A `record` with no `--duration` runs until stopped. From another shell, address it by its
session id:

```bash
gridcap status        --session-id demo   # frame counts, file sizes, paused state
gridcap pause         --session-id demo
gridcap resume        --session-id demo
gridcap add-window    --session-id demo --window 67890   # start capturing another window
gridcap remove-window --session-id demo --window 12345   # stop & finalize just that window
gridcap stop          --session-id demo   # finalize all and exit
```

You can also stop a foreground `record` with `Ctrl+C` — it finalizes the MP4s cleanly.

### Control socket

Each session listens on a Unix domain socket at `/tmp/gridcap-<session-id>.sock`. The
`status`/`pause`/`resume`/`stop`/`add-window`/`remove-window` subcommands are thin
clients over it: they send a one-line JSON request and print the JSON response. You can
speak the protocol directly if you'd rather not shell out per command.

## Output format

- **stdout** — machine-readable JSON only (pretty-printed, sorted keys).
- **stderr** — human status lines; per-frame debug detail only with `--verbose`.

This split means you can pipe stdout straight into `jq` or a parser without filtering.

## Development

```bash
swift build      # debug build
swift test       # run the test suite
```

## License

[MIT](LICENSE) © Cody Maughan

Built on Apple's ScreenCaptureKit and AVFoundation. Depends on
[swift-argument-parser](https://github.com/apple/swift-argument-parser) (Apache-2.0).
