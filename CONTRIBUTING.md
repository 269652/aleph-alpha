# Contributing to Aleph Alpha

Aleph Alpha is closed-source and proprietary (see [LICENSE.md](LICENSE.md))
— this isn't a "fork it, PR it" open-source project. Repo write access is
granted individually, by application, and reviewed by the project owner.
This document covers how to apply, and what's expected once you're in.

## Before you apply

Read these first — the application asks you to confirm you have:

- **[LICENSE.md](LICENSE.md), section 5 ("Contributions")** — by
  submitting code, art, or any other material to this repository, you
  grant the copyright holder a perpetual, worldwide, irrevocable,
  royalty-free license to that contribution, and you represent that you
  actually have the rights to grant it. There is no separate CLA to
  countersign; submitting a contribution *is* the agreement.
- **This file**, for how the project runs day to day.

## Applying as a contributor

Open a **Contributor Application** issue in this repository (issue type
selectable from *New Issue*; template lives at
[`.github/ISSUE_TEMPLATE/contributor-application.md`](.github/ISSUE_TEMPLATE/contributor-application.md)).
Include:

- Your GitHub handle (should match the account filing the issue).
- What you want to work on — naming a specific system from
  [docs/progress.md](docs/progress.md) or [docs/concept/](docs/concept)
  makes for a stronger application than "anything."
- Relevant background (Godot/GDScript or comparable work) — no formal bar
  to clear, just say what you've built before.
- Confirmation you've read `LICENSE.md` §5 and this file.

The owner reviews and replies on the issue itself, and may ask follow-up
questions there before deciding. On acceptance:

1. The issue is labeled `accepted` and closed.
2. You get a GitHub collaborator invite with **write access** to this
   repository.
3. Once you accept the invite, you push branches and open PRs directly —
   no fork needed.

A declined application gets a reason on the issue. You're welcome to
reapply later if that reason no longer applies.

## What contributor access grants — and what it doesn't

Accepted contributors get **repo write access**: push branches, open PRs,
push to branches under review. That's the entire scope of the grant.

It does **not** include the project's release-signing key. Aleph Alpha
separately signs shipped builds and player license serials with an
RSA keypair described in [docs/licensing.md](docs/licensing.md)
(`tools/sign_build.gd`, `tools/generate_serial.gd`, `src/licensing/`).
That private key is deliberately single-owner — it's never committed to
this repository, never distributed to contributors at any level, and
isn't something contributor access grants a path to, no matter how the
application is worded. Handing it out would let anyone who has it mint
valid paid-product license serials and re-sign a tampered build as
genuine, for every player, permanently — that's the exact failure mode
`docs/licensing.md` is written around avoiding. If your application meant
that system specifically rather than general code/content contribution,
say so explicitly on the issue so it can be discussed on its own — it
won't be granted through the standard contributor flow described here.

## Signing your commits

Every commit you push should carry a **`Signed-off-by` trailer**
(`git commit -s`) — the standard Developer Certificate of Origin practice,
and the commit-level record of the same representation LICENSE.md §5
already requires. GPG- or SSH-signing your commits on top of that
(`git commit -S`, shows as "Verified" on GitHub) is encouraged, to
authenticate that commits under your name actually came from you. This is
commit provenance — unrelated to the release-signing key described above.

## Once you're in: how work actually happens here

### Strict TDD — red, then green, then refactor

Full detail in [CLAUDE.md](CLAUDE.md) / [AGENTS.md](AGENTS.md); in short:

- Write a failing test before any implementation code, and confirm it
  fails for the expected reason.
- Write the minimum code to pass it, then refactor only with the suite
  green.
- Never hand-tune a value/threshold as an eyeballed comment — it must be a
  tested function or a test-pinned constant.

Tests run via the [GUT](addons/gut) addon against `.gutconfig.json`
(`res://tests/unit`, subdirs included) — from the Godot editor's GUT
panel, or headless via GUT's command-line runner. Run just the file(s) you
touched per change:

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://tests/unit/test_foo.gd -gexit
```

The `-gconfig=` (empty value, skips loading `.gutconfig.json`) is required,
not optional: that config sets `dirs: ["res://tests/unit"]`, and GUT adds
that whole directory unconditionally on top of whatever `-gtest=` lists.
Drop `-gconfig=` and `-gtest=` stops scoping anything — you silently get a
full-suite run under what looks like a fast, single-file one.

Save a full-suite pass for natural checkpoints (end of a feature, before
merging) — this one deliberately omits `-gconfig=` so it picks up
`.gutconfig.json` and needs no `-gtest=`:

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gexit
```

`tests/unit/test_earth_chunk_manager.gd` is the known long pole of a full
run: it's the largest test file (492 tests), `EarthChunkManager.update()`
is a genuinely expensive real operation (~100s/call, measured), and ~237
of this file's tests call it with the same fixed tile — so a *complete*
pass of just this file can run for hours (see the note at the top of the
file's test body). Not a bug to fix before merging; when iterating, scope
to one test with `-gconfig= -gtest=res://tests/unit/test_earth_chunk_manager.gd
-gunit_test_name=<substring>` instead of waiting on the whole file.

### Concept docs are the spec

Before implementing a mechanic, read the relevant `docs/concept/*.md` file
and build what it specifies; if none exists, write or extend one first.
After implementing, update [docs/progress.md](docs/progress.md)
(✅/🚧/⬜) to reflect reality exactly — including noting it if you
deliberately diverged from the concept doc, in which case update that doc
to match. Full detail in [CLAUDE.md](CLAUDE.md).

### `main` is live and concurrently edited

There's no long-lived develop branch — `main` is the checkout actually
run/played, and other work (the owner's, other contributors') may land on
it while yours is in flight. In practice:

- Branch off `main` per change; open a PR rather than pushing directly to
  `main`.
- Immediately before merging, re-read the current state of any file
  you're touching on `main` — don't assume it still matches what you
  branched from.
- Never stage with a broad `git add -A` / "commit everything" on a shared
  checkout without first checking `git status` and skimming recent log
  history for anything mid-resolution (restores, reverts, "kept both"
  merges) a blind add could re-delete. Stage explicit paths when you know
  exactly what you changed.
- A feature counts as done once it's merged into `main` and re-verified
  there — not when its tests pass in isolation on your branch.

## Opening a PR

- Keep PRs scoped to one mechanic/fix — large unrelated changes are
  harder to review and more likely to collide with concurrent work on
  `main`.
- Describe what changed and why, and which tests cover it.
- Note any `docs/concept/*.md` / `docs/progress.md` updates the change
  required.

## Questions

Open an issue, or ask on your contributor-application issue thread if
you're already mid-application.
