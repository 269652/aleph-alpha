# Release tooling

Two PowerShell scripts that build, sign, package, and publish a Windows
build of the game to GitHub Releases. Ops/developer tooling, not game
code — same "not part of this project's TDD-covered game code" status
`tools/sign_build.gd`/`tools/generate_keypair.gd` already carry.

The version itself lives in a single place: `project.godot`'s
`application/config/version` (Godot's own canonical version field —
Project Settings > Application > Config > Version).

## Prerequisites

- **[GitHub CLI](https://cli.github.com/) (`gh`)**, installed and
  authenticated (`gh auth login`) — this is how a release actually gets
  created/updated on GitHub. `build_release.ps1` checks for both up front
  and fails with a clear message if either is missing.
- **Godot 4.7.2 export templates** installed for the version this project
  uses (Editor > Manage Export Templates, or they're already installed if
  you've exported from the editor before). `--export-release` fails with
  its own error if a required template is missing.
- **An `export_presets.cfg`** in the repo root with a configured preset
  (default: `"Windows Desktop"`). This file is gitignored — a fresh
  checkout needs one created once via the editor's Project > Export
  dialog, same as any local Godot project.
- **Your private signing key** (`.pem`, from `tools/generate_keypair.gd`),
  kept **outside this repository entirely** — a password manager
  attachment or an encrypted offline drive is
  [`docs/licensing.md`](../../docs/licensing.md)'s own recommendation; a
  plain folder outside any repo (e.g. next to your Godot install) is the
  accepted minimum as long as you control that machine. **Never** put it
  inside this repo, inside the export/dist output folder as anything
  other than a throwaway local-test copy, or anywhere
  `build_release.ps1`'s packaging step might see it — see that script's
  own `Assert-NoPrivateKeyAmong` safety check, which refuses to package
  anything that looks like a key.

  Pass it via `-KeyPath` each time, or set it once as an environment
  variable so you don't have to retype it:

  ```powershell
  # Add to your PowerShell profile ($PROFILE) -- this lives under your own
  # user profile and is never committed to this repo, unlike a script
  # default would be.
  $env:ALEPH_ALPHA_SIGNING_KEY = "C:\path\to\your-signing-key.pem"
  ```

  `build_release.ps1` falls back to this variable whenever `-KeyPath` is
  omitted. Deliberately no hardcoded default and no filesystem
  auto-discovery in the script itself: a script committed to this repo
  that hardcoded your real key's literal path would permanently document
  exactly where to look for it to anyone who ever gets read access to
  this source.

## Usage

**Rebuild and republish the CURRENT version** (e.g. you found a packaging
problem and want to fix it without bumping the version number):

```powershell
.\tools\release\build_release.ps1 -KeyPath D:\secure\aleph-alpha-signing-key.pem
```

This exports the "Windows Desktop" preset, signs the executable, zips the
`.exe` + its `.sig` sidecar, then either creates a new GitHub Release for
`vX.Y.Z` or — if one already exists for that version — re-uploads the
asset to it (`--clobber`). Safe to run repeatedly for the same version.

**Ship a NEW version:**

```powershell
.\tools\release\bump_version.ps1                  # patch bump: 0.1.0 -> 0.1.1
.\tools\release\bump_version.ps1 -Part minor      # 0.1.4 -> 0.2.0
.\tools\release\bump_version.ps1 -Part major      # 0.9.9 -> 1.0.0
.\tools\release\bump_version.ps1 -Version 1.0.0   # set an exact version

.\tools\release\build_release.ps1 -KeyPath D:\secure\aleph-alpha-signing-key.pem
```

`bump_version.ps1` edits `project.godot`, commits (`chore: bump version to
X.Y.Z`), and pushes by default (pass `-NoPush` to skip the push and do it
yourself later). `build_release.ps1` then builds/signs/packages/publishes
against whatever version is now current.

**Dry run** (prints what would happen — version, export path, package
name — without actually exporting, signing, tagging, or touching GitHub):

```powershell
.\tools\release\build_release.ps1 -KeyPath D:\secure\aleph-alpha-signing-key.pem -DryRun
```

## What `build_release.ps1` actually does, in order

1. Resolves the signing key from `-KeyPath`, or `$env:ALEPH_ALPHA_SIGNING_KEY`
   if omitted. Preflight: key file exists, Godot binary exists, `gh`
   installed and authenticated.
2. Reads the current version from `project.godot`.
3. Reads the export output path for the chosen preset straight out of
   `export_presets.cfg` (never a second, hand-maintained copy of it).
4. `godot --headless --export-release "<preset>"` — a real build.
5. `tools/sign_build.gd` against the exported executable, using your
   `-KeyPath` — produces the `.sig` sidecar `SelfIntegrity` checks at
   boot (see `docs/licensing.md`).
6. Zips **exactly** the `.exe` and its `.sig` — an explicit allowlist, not
   a whole-directory zip, so nothing else that might be sitting in the
   dist folder (a locally-entered `license.txt`, a local-testing
   `private_key.pem`) can end up in a customer-facing package.
7. Pushes the current branch, then creates (or reuses, if re-running the
   same version) an annotated git tag `vX.Y.Z`, pushed to origin.
8. Creates the GitHub Release for that tag (`gh release create`, with
   `--generate-notes`), or if one already exists, uploads the fresh zip
   to it (`gh release upload --clobber`).

## Not included (possible follow-ups, not silently assumed done)

- **No test-suite gate.** Neither script runs the GUT test suite before
  releasing — the full suite can take a long time (see `CONTRIBUTING.md`),
  and this wasn't asked for. Run it yourself first if you want that
  guarantee before publishing.
- **Windows only.** `export_presets.cfg` currently defines only a
  "Windows Desktop" preset; `-Preset` exists on `build_release.ps1` so a
  future Linux/macOS preset can reuse the same script once one exists.
- **No in-game version display.** `config/version` is read by these
  scripts only; nothing in the game itself shows it on screen yet.
