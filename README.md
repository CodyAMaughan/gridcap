# gridcap

A headless macOS CLI for **recording individual windows** — one MP4 per window, all
captured at once and kept frame-synced — built on
[ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) and
AVFoundation. It also runs as an **MCP server** so AI agents can drive it directly.

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
- **Agent-ready** — drive it as a [Claude Code plugin](#claude-code-skill--cli-plugin),
  or as an [MCP server](#mcp-server-codex-cursor-zed-claude-code-) from any MCP-capable
  harness. JSON on stdout, no GUI, works when spawned from a non-interactive shell.

## Requirements

- macOS 13 (Ventura) or later
- Swift 6 toolchain (Xcode 16+) to build from source

## Install

### Homebrew (recommended)

```bash
brew install CodyAMaughan/tap/gridcap
```

### From source

```bash
git clone https://github.com/CodyAMaughan/gridcap.git
cd gridcap
swift build -c release
cp .build/release/gridcap /usr/local/bin/   # optional: put it on your PATH
```

## Permissions

`gridcap` needs two macOS privacy grants. The terminal app you run it from (Terminal,
iTerm2, etc.) — or the agent that launches it — is what actually gets listed in System
Settings; grant it there.

| Permission | Needed for | Where to grant |
|---|---|---|
| **Screen Recording** | `list`, `screenshot`, `record`, `mcp` | System Settings → Privacy & Security → Screen Recording |
| **Accessibility** | `arrange` (moving/resizing windows) | System Settings → Privacy & Security → Accessibility |

Check what's currently granted:

```bash
gridcap list --check-permission
# { "accessibility": "granted", "screen_recording": "granted" }
```

If Screen Recording was just enabled, fully quit and reopen your terminal (or restart the
agent) so the new grant takes effect.

## CLI usage

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

## Use it from an AI agent

gridcap is built to be driven by coding agents. There are two ways in, and you can use
either (or both):

### Claude Code: skill + CLI plugin

The primary path for [Claude Code](https://claude.com/claude-code). It bundles a **skill**
that teaches the agent the full gridcap workflow (check permissions → list → arrange →
record → control → stop) and drives the `gridcap` CLI directly — no extra server process.

```bash
# Install the gridcap binary first (see Install above), then in Claude Code:
/plugin marketplace add CodyAMaughan/gridcap
/plugin install gridcap@gridcap
```

Once installed, just ask Claude Code to "record the Safari window" (or similar) and the
skill kicks in. The skill expects `gridcap` on your `PATH`.

### MCP server (Codex, Cursor, Zed, Claude Code, …)

The same binary runs as a [Model Context Protocol](https://modelcontextprotocol.io)
server over stdio — the portable path that works in any MCP-capable harness. It exposes
these tools: `check_permissions`, `list_windows`, `arrange_window`, `screenshot_window`,
`start_recording`, `recording_status`, `pause_recording`, `resume_recording`,
`add_window`, `remove_window`, `stop_recording`.

Run it directly to see it speak MCP:

```bash
gridcap mcp
```

**OpenAI Codex** — register it once:

```bash
codex mcp add gridcap -- gridcap mcp
```

or in `~/.codex/config.toml`:

```toml
[mcp_servers.gridcap]
command = "gridcap"
args = ["mcp"]
```

**Claude Code** (if you prefer MCP over the plugin):

```bash
claude mcp add gridcap -- gridcap mcp
```

**Generic MCP client** (Cursor, Zed, Windsurf, etc.) — point it at the command
`gridcap` with argument `mcp`. The equivalent JSON most clients accept:

```json
{
  "mcpServers": {
    "gridcap": {
      "command": "gridcap",
      "args": ["mcp"]
    }
  }
}
```

`start_recording` launches a background session and returns a `session_id`; use the
`recording_status` / `pause_recording` / `resume_recording` / `stop_recording` tools with
that id to drive it, exactly like the CLI.

## Output format

- **stdout** — machine-readable JSON only (pretty-printed, sorted keys).
- **stderr** — human status lines; per-frame debug detail only with `--verbose`.
  (The `mcp` subcommand keeps stdout reserved for the MCP protocol.)

This split means you can pipe stdout straight into `jq` or a parser without filtering.

## Development

```bash
swift build      # debug build
swift test       # run the test suite
```

## License

[MIT](LICENSE) © Cody Maughan

Built on Apple's ScreenCaptureKit and AVFoundation. Depends on
[swift-argument-parser](https://github.com/apple/swift-argument-parser) and the
[Swift MCP SDK](https://github.com/modelcontextprotocol/swift-sdk) (both Apache-2.0).
