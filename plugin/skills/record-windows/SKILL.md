---
name: record-windows
description: Record macOS app windows to video or capture window screenshots using the gridcap CLI. Use when the user asks to record the screen, record a window, capture a demo/tutorial video, screenshot a specific window, or arrange windows for a recording. Records each window to its own MP4 and can pause/resume/stop a live session.
---

# Recording macOS windows with gridcap

`gridcap` is a command-line tool that records individual macOS windows — each to its own
MP4 — and captures per-window screenshots. Every command prints JSON to stdout, so parse
stdout and ignore stderr (which carries human status only).

The normal flow is **check → list → (arrange) → record → control → stop**. Follow it in order.

## 0. Make sure gridcap is installed

```bash
command -v gridcap
```

If that prints nothing, gridcap isn't installed. Tell the user to install it and stop —
do not try to build it yourself:

```bash
brew install CodyAMaughan/tap/gridcap
```

(Or, from a source checkout: `swift build -c release` and use `.build/release/gridcap`.)

## 1. Check permissions first

gridcap needs **Screen Recording** (for listing/screenshots/recording) and, only for
`arrange`, **Accessibility**. Always check before recording:

```bash
gridcap list --check-permission
# {"accessibility":"granted","screen_recording":"granted"}
```

If `screen_recording` is `denied`, tell the user to grant it to their terminal app in
**System Settings → Privacy & Security → Screen Recording**, then fully quit and reopen
the terminal. Do not attempt to record until it reads `granted`.

## 2. List windows to get their IDs

```bash
gridcap list                       # all windows
gridcap list --app-filter Safari   # case-insensitive substring on app name or title
```

Each entry has a numeric `window_id`, `title`, `app_name`, and `bounds`. Pick the
`window_id`(s) you need. If the user named an app, filter by it and confirm which window
you'll record when there's more than one match — never guess silently.

## 3. (Optional) Arrange windows for a clean layout

Position/resize a window before recording (needs Accessibility permission):

```bash
gridcap arrange 12345 --x 0 --y 0 --width 1280 --height 720
```

## 4a. Screenshot a single window

```bash
gridcap screenshot 12345 --output ./shot.png
```

## 4b. Record one or more windows

Each window becomes its own `window_<id>_<session>.mp4` in the output directory.

```bash
# Fixed-length recording (blocks until done), two windows at once:
gridcap record --windows 12345,67890 --output-dir ./out --duration 30

# Open-ended recording you control from another step — name the session yourself:
gridcap record --windows 12345 --output-dir ./out --session-id demo
```

- Prefer `--duration` when the user knows how long; the command returns a JSON summary
  with the file paths when it finishes.
- For an open-ended recording, **always pass `--session-id`** (e.g. a short slug) so you
  can control and stop it in later steps. Run it in the background so you can issue
  control commands while it records.
- Default is 30 fps; pass `--fps` to change. Add `--verbose` only when debugging.

## 5. Control a running (open-ended) session

Address the session by the `--session-id` you chose:

```bash
gridcap status        --session-id demo   # frame counts, file sizes, paused state
gridcap pause         --session-id demo
gridcap resume        --session-id demo
gridcap add-window    --session-id demo --window 67890   # start capturing another window
gridcap remove-window --session-id demo --window 12345   # finalize just that window
gridcap stop          --session-id demo   # finalize all MP4s and end the session
```

Pausing drops frames but keeps the output timeline gap-free.

## 6. Always stop what you started

An open-ended `record` runs until you `stop` it (or `Ctrl+C` the foreground process).
Never leave a session running — finalize with `gridcap stop --session-id <id>` when the
user is done, and report the resulting file paths.

## Common mistakes to avoid

- Do **not** record before `gridcap list --check-permission` shows `screen_recording: granted`.
- Do **not** record a window id you haven't confirmed via `gridcap list` — ids change as windows open/close.
- Do **not** start an open-ended recording without a `--session-id`; you won't be able to stop it cleanly.
- Do **not** parse stderr as data — only stdout is JSON.
