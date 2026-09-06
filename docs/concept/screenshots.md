# Screenshots

Press F12 anywhere -- the character-creation diorama, a settings overlay,
mid-game -- and the current frame is saved to `./screenshots/` as a WEBP,
named by the moment it was taken.

## Status

Built.

## Design pillars

1. **Works everywhere, including before a game session exists.** The
   character creator's `CharacterPreviewDiorama` is a real, live-rendered
   scene a player will want to capture, and it's on screen well before any
   `World`/`Player` node is created. Every existing rebindable key
   (`Keybindings.ACTIONS`) only ever becomes a real `InputMap` action via
   `World._apply_keybindings`, which runs once a game session starts --
   routing screenshots through that system would silently fail to work on
   exactly the screen this pillar names first. `ScreenshotCapture` is its
   own autoload instead (see project.godot's `[autoload]` section),
   registering its own `InputMap` action in `_ready()`, which for an
   autoload runs before the first scene's own `_ready()` -- before the main
   menu, before anything.
2. **Fixed key, not rebindable -- deliberately.** F12 is a long-standing
   cross-application screenshot convention and isn't used by any entry in
   `Keybindings.ACTIONS`. Making it rebindable would mean either duplicating
   Keybindings' persistence/settings-menu machinery for a single action, or
   coupling this autoload to a system that (per pillar 1) isn't even live on
   the screens this feature most needs to work on. Not a permanent
   position, just not worth the weight for one key today.
3. **One data source, reused.** `./screenshots/` already exists in this repo
   -- it holds the hand-picked PNGs the README embeds (see
   `d57f8a9`/`c3c9db4`'s history). Auto-captured screenshots land in that
   exact same top-level folder rather than a new subfolder, so there's one
   obvious place to look, not two. Their timestamped names (never a bare
   `screenshot.webp`) keep them visually distinct from the README's
   deliberately-named files without needing a separate directory to do it.
4. **Never silently overwrite, never crash.** Two presses inside the same
   second get two files (a numbered suffix), not one clobbering the other.
   A capture attempted somewhere a real frame can't be read (this project's
   own `--headless` test runs, chiefly) fails into a clean signal instead of
   an engine error.

## Naming

`DD-MM-YY HH-MM-SS.webp` -- e.g. `06-09-26 08-03-09.webp`. A literal `:` is
illegal in a Windows filename, so the time portion reuses the date's own
hyphen separator rather than inventing a second convention. Collisions
(two presses within the same second) get `" (2)"`, `" (3)"`, ... appended
before the extension, the same shape Windows Explorer's own "keep both"
uses.

## Mechanism

- `ScreenshotNaming` (`src/ui/screenshot_naming.gd`) -- pure: `filename_for`/
  `path_for`/`unique_path_for`. Takes a
  `Time.get_datetime_dict_from_system()`-shaped `Dictionary` rather than
  reading the clock itself, and `unique_path_for` takes an injected
  `path_exists` predicate rather than calling `FileAccess.file_exists`
  itself -- both purely so the exact filename/collision-suffix logic is a
  deterministic unit test, not a wall-clock race or a real-filesystem
  dependency.
- `ScreenshotCapture` (`src/ui/screenshot_capture.gd`, autoload) -- the thin
  glue: registers the `"screenshot"` InputMap action (F12) in `_ready()`,
  listens in `_unhandled_input`, and on press reads `get_viewport()
  .get_texture().get_image()`, ensures `screenshots/` exists
  (`DirAccess.make_dir_recursive`), and calls `Image.save_webp()` at
  `ScreenshotNaming.unique_path_for(...)`. Emits `screenshot_saved(path)` or
  `screenshot_failed(reason)` -- nothing currently listens for either (no
  on-screen "Screenshot saved!" toast yet, see Non-goals), but the signals
  exist so a future UI layer can hook in without changing this class.
  `take_screenshot()` is also callable directly, independent of any key
  event (a dev-console command, say).
- Both the real viewport read and the real system clock are swapped for
  injected `Callable`s (`_image_source`, `_now`) specifically so
  `test_screenshot_capture.gd` can drive every branch -- including the
  "no real frame available" failure path -- without ever touching a real
  window. Calling the real viewport-image path under `--headless` raises
  its own engine-level error regardless of how gracefully the resulting
  `null` is handled afterward (the same landmine `test_river_flow_render_
  smoke.gd` already works around), so exactly one test
  (`test_take_screenshot_captures_the_real_viewport`) exercises the real
  path, gated behind the same `DisplayServer.get_name() == "headless"` ->
  `pending(...)` pattern every other GPU-readback test in this repo uses.

## Non-goals (for now)

- No on-screen confirmation toast when a screenshot saves -- `screenshot_
  saved`/`screenshot_failed` exist for exactly this, unwired.
- No rebindable key / settings-menu entry (see pillar 2).
- No format choice (PNG, etc.) or quality/compression setting -- always a
  default-quality WEBP.
- No screenshot gallery/viewer inside the game itself -- the folder is
  meant to be opened in a real file browser.
