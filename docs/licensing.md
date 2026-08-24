# Serial / License Verification

Offline, no-server-required serial verification for the base game and any
DLC: a serial can only be produced by whoever holds the developer's private
key, and the shipped game carries only the matching public key. This is
infrastructure, not a gameplay mechanic — it lives here rather than in
`docs/concept/` (which `docs/progress.md` tracks mechanism-by-mechanism
against; this doc deliberately isn't part of that ledger).

## Read first: what this actually defends against

A client-side check, however strong the cryptography, cannot stop someone
from patching the shipped game to skip the check entirely — the
verification code and "what happens if valid" branch both live in the
player's own copy of the game. This is a universal limitation of every
offline license scheme, not a gap specific to this design.

What signature-based verification *does* stop, cleanly: **keygens** —
anyone generating new, superficially-valid serials without holding the
private key. Without asymmetric signing, a determined person can write a
"keygen" once and hand it out; with it, forging a serial that passes
verification requires solving RSA, not reverse-engineering a checksum
algorithm. That's the realistic bar this is aiming for — raising casual/
keygen-based piracy to cryptographically infeasible, not defeating a
determined reverse engineer willing to patch the binary. Real DRM that
resists binary patching needs server-side validation or hardware-bound
licensing, both of which most solo/indie developers deliberately skip
because they punish legitimate customers more than they stop pirates. Worth
knowing which bar you're aiming for before building toward it.

Godot's exported `.pck` isn't encrypted by default (an export encryption
key option exists, but the decryption key ships inside the binary that
uses it, so it raises the bar only modestly against someone willing to
extract it) — GDScript logic in the shipped game is realistically readable
by anyone who wants to look. That's fine for this design: reading the
verification code doesn't help forge a serial without the private key, it
only helps someone find the check to patch out, which is the limitation
above already priced in.

## Grounded in what this project's actual Godot version supports

Checked directly against the real Godot 4.7 install this project uses
(`Crypto`/`CryptoKey`/`HashingContext`'s actual exposed methods), not
assumed from memory:

- `Crypto.generate_rsa(size)` — **RSA only**. No `generate_ec`/Ed25519/
  ECDSA method exists on this class at all.
- `Crypto.sign(hash_type, hash, key)` / `Crypto.verify(hash_type, hash,
  signature, key)` — real sign/verify, operating on an RSA `CryptoKey`.
- `HashingContext.HashType` exposes only `HASH_MD5`, `HASH_SHA1`,
  `HASH_SHA256` — SHA-256 is the only one of those still considered sound;
  MD5/SHA1 are broken for security purposes and shouldn't be used here.
- `CryptoKey.save`/`load`/`save_to_string`/`load_from_string`, each taking
  a `public_only` bool — exactly the "keep the private key separate, embed
  only the public one" split this needs, natively supported.
- `Crypto.constant_time_compare` also exists, useful elsewhere in this
  design (see Revocation below) even though `Crypto.verify` itself already
  handles signature comparison safely.

This settles the algorithm choice by what's actually available rather than
by preference: **RSA-2048, signing a SHA-256 hash of the payload.**
RSA-1024 would produce a shorter signature but is deprecated by current
standards (practically breakable by a well-resourced attacker) — not worth
the length savings.

## The real constraint this creates: RSA signatures don't fit a typed serial

An RSA-2048 signature is 256 bytes. Added to even a small payload (see
below, roughly 8–16 bytes), that's ~264–272 bytes to encode into whatever
the player enters. Base32 (safe for manual entry — no ambiguous 0/O, 1/I/l)
expands that to roughly **430–435 characters**. Even dense Base64 is
still roughly 360 characters. Neither is a "type 20 characters from a box"
classic serial key — that expectation is incompatible with RSA-2048's real
signature size, not a limitation of this particular design.

**Recommendation: ship it as a paste-able code, not a typed one.** The
player copies it from their purchase email/storefront page and pastes it
into a text field, formatted in short readable lines (e.g. 8 groups of 5
characters per line) the same way a PGP key or license file already reads —
legible, verifiable-by-eye that it copied cleanly, but never meant to be
typed character-by-character. This is what most real commercial RSA-based
offline licensing actually does, for exactly this reason.

**Noted, not recommended by default**: Ed25519 signatures are only 64
bytes — encoded, closer to 80–90 typeable characters, genuinely closer to a
classic short serial. Godot doesn't expose it natively, so getting there
means either a GDExtension (native compiled dependency, real cross-platform
build complexity for a solo project) or a hand-written pure-GDScript
Ed25519 implementation (elliptic-curve arithmetic is easy to get subtly
wrong even for verification-only use — no secret key is at risk on the
verifying side, but incorrect modular arithmetic can still open a forgery
gap). Worth revisiting later if the paste-able-code UX proves genuinely
unpopular; not worth the complexity/risk to chase shorter codes now when
Godot already provides a correct, tested RSA implementation for free.

## Payload format

Fixed-width fields, encoded before signing:

```
version:        1 byte  -- format version, so a future field layout
                            change doesn't break old already-issued serials
product_mask:    8 bytes -- bitmask, one bit per product (bit 0 = base game,
                            bits 1+ = each DLC in release order); a bundle
                            is just multiple bits set, no separate format
license_id:      4 bytes -- unique per issued serial, NOT a secret --
                            purely so a specific serial can be named later
                            (see Revocation)
expiry (opt.):   4 bytes -- unix timestamp, 0 = never expires; cheap to
                            include now for press/review/demo keys even if
                            unused for ordinary retail keys at launch
```

17 bytes payload (or 13 without expiry) + 256-byte RSA-2048 signature =
273 bytes total, matching the length estimate above.

## Signing (offline, developer-only, never shipped)

1. **Once**, generate the RSA-2048 keypair (`Crypto.generate_rsa(2048)`,
   run as a one-off local script — this can be Godot itself or any RSA
   tool, the key format is standard). Save the full key (private + public)
   somewhere that never touches this git repository — a password manager
   attachment or an encrypted offline drive, not `assets/`, not any
   tracked path. Losing it means never being able to issue a new valid
   serial for this product again (see Key rotation for a hedge).
2. Save the **public-only** half (`CryptoKey.save_to_string(true)`) and
   embed that string as a constant in the shipped game. This is the only
   half that ever ships.
3. Per sale: build the payload bytes for whatever product bitmask that
   purchase grants, hash with SHA-256, sign the hash with the private key
   (`Crypto.sign(HASH_SHA256, hash, private_key)`), concatenate
   `payload || signature`, Base32-encode, format into readable lines. This
   is what gets delivered to the customer (storefront automation, a
   fulfillment email, however sales actually happen).

## Verification (in the shipped game)

1. Base32-decode whatever the player pasted in. Malformed input (wrong
   length, invalid characters) fails immediately with a generic "invalid
   code" message — deliberately generic, not "bad checksum" vs. "bad
   signature" vs. "unknown format," so a would-be keygen author gets no
   debugging oracle from the failure message itself.
2. Split into `payload` (fixed length from the version byte) and
   `signature` (everything after).
3. Hash `payload` with SHA-256, call `Crypto.verify(HASH_SHA256, hash,
   signature, embedded_public_key)`.
4. If valid: check `license_id` against the local revocation list (see
   below); if not revoked, read `product_mask` and unlock exactly those
   products.
5. Cache the validated raw code (not just a bare "is_valid" boolean) in the
   player's save data, and re-verify it against the embedded public key at
   least once per session rather than trusting a cached flag forever — a
   flag is a far easier single point to flip via a save-file edit than
   understanding the actual cryptography, so re-checking the real code each
   session keeps the save file itself from becoming the weak point.

## DLC / entitlement model

**Recommended: one combined serial per customer, re-issued when their
entitlement changes**, not one serial per product. A customer who owns the
base game and later buys a DLC gets a *new* serial encoding the full
updated bitmask (base + all owned DLC), rather than juggling multiple
codes. Simpler for the player (one code to keep) and for the implementation
(one stored/verified code, one code path) — recommended default over a
multi-serial-per-product alternative, which is real and workable but adds
real complexity (storing N codes, verifying N codes, merging N bitmasks)
for a UX benefit that mostly matters if DLC purchases are expected to be
frequent and incremental for the same customer.

## Revocation (optional, still fully offline)

If a serial leaks publicly, there's no way to invalidate it via the
signature check alone (it's still a cryptographically valid signature).
The standard mitigation that stays offline: ship a small deny-list of
revoked `license_id` values as ordinary game-update content (a bundled
data file, not a network call) — step 4 above checks it. This is a manual,
occasional response to a known leak, not a live anti-piracy system; most
solo/indie titles never need to use it, but it costs nothing to design in
now versus retrofitting later once a real leak happens.

## Key rotation (optional future-proofing)

Ship more than one embedded public key and accept a signature verified
against *any* of them. Costs nothing until it's needed, and means a
compromised or lost private key can be recovered from by rotating to a
freshly generated one in a future patch — existing customers' old serials
(signed by the old key) keep working since the old public key stays
embedded alongside the new one, while new serials go out signed by the new
key.

## Source/build integrity verification

Separate concern from serial verification, same trust root: instead of
checking that the *player* holds a valid entitlement, this checks that
the *game files themselves* haven't been modified since they left the
signing machine — a genuinely different question (a legitimate customer
running a patched/repackaged binary is exactly what this catches; someone
running the unmodified game with a shared/leaked serial is a
serial-verification problem, not this one).

**What gets hashed.** Not individual source files — the single exported
data artifact: the `.pck` Godot produces next to the executable (the
default "Embed PCK" unchecked layout), or the executable itself when PCK
is embedded. Every compiled script, scene, and resource in the game lives
inside that one file, so any change to any of them changes its hash.
Whole-file hashing was chosen over a per-file manifest deliberately: it's
one `FileAccess` read of a normal OS path rather than enumerating
resources inside a mounted virtual filesystem at runtime (which has its
own quirks this design avoids relying on), and it's trivially testable
end to end with a throwaway file rather than depending on a real export
existing. The tradeoff is granularity — this answers "was anything
changed", not "which file" — acceptable for a refuse-to-run gate, where
the only actions on failure are "run" or "don't."

**Detached signature, not embedded.** The signed hash ships as a sidecar
`<file>.sig` next to whatever it signs, never bundled inside it — bundling
it would change the very hash it's certifying (a hash that includes its
own signed copy of itself is self-referential and can't be computed in
one pass). Same shape as `license.txt`: a plain file the build process
drops next to the executable, nothing baked into the export itself.

**Hashing the raw repo `src/*.gd` files would not work.** Export compiles
and packs scripts into the `.pck`; a hash taken before export never
matches what the running game reads from the `.pck` at runtime. The
signing tool must run *after* export, against the actual shipped
artifact — see `tools/sign_build.gd`'s own doc comment.

**What this does and doesn't add over the "read first" section above:**
still a client-side check, still patchable by someone willing to
reverse-engineer the binary and strip the call site (see this doc's
opening section — that limitation is universal, not specific to this
mechanism). What it raises the bar on specifically: a modified `.pck`
(a cracked build with the serial check patched out, a repackaged pirate
build with assets swapped, a corrupted/incomplete copy) now fails a
*second*, independent check before the first one is even reached, so
defeating both means patching two things, not one. It does **not**
protect the native Godot engine binary itself — only the data/`.pck`, or
the whole executable when embedded — and it does **not** detect tampering
that happens *after* the check passes (a debugger or memory patcher
altering the already-running process). Userspace/script-level integrity
checking cannot close that gap; only kernel-level anti-cheat/DRM can, and
this project isn't reaching for that.

**Shared trust root.** Uses the same `EmbeddedPublicKeys.PUBLIC_KEY_PEMS`
list as serial verification — one key (or rotated set) signs both serials
and builds, rather than maintaining two separate keys to protect and
rotate.

## Proposed file layout

- `src/licensing/serial_codec.gd` — pure encode/decode between the payload
  struct and raw bytes (version/product_mask/license_id/expiry). No crypto,
  no I/O — fully unit-testable pure logic, same pure/glue split this
  project already uses everywhere (`ChunkSerializer`/`EarthChunkManager`,
  `StoneSize`/`StoneRenderer`).
- `src/licensing/serial_verifier.gd` — owns the embedded public key
  constant(s), wraps `Crypto.verify`, decodes+verifies an entered code,
  returns entitlement info or a generic failure. The one place `Crypto`
  itself gets touched.
- A **separate, never-shipped** signing tool (e.g. `tools/generate_serial.gd`,
  or a small script outside this repo entirely) that holds/reads the
  private key and produces new serials — explicitly excluded from
  whatever the Godot export template packages, since accidentally shipping
  it would ship the private key alongside it.
- `src/licensing/signature_ring.gd` — the shared multi-key RSA
  verify-a-hash primitive both serial verification and integrity
  verification delegate to.
- `src/licensing/integrity_paths.gd` / `src/licensing/self_integrity.gd` —
  pure path derivation and the integrity enforcement gate (see "Source/
  build integrity verification" above).
- `tools/sign_build.gd` — never-shipped signing tool for the exported
  build artifact, parallel to `tools/generate_serial.gd`.

## Open questions

- Exact product-bitmask width — 8 bytes (64 products) is generous headroom
  for "main game + DLCs"; could shrink if that's excessive.
- Exact Base32 line-grouping/formatting for the paste-able code — a UX
  detail worth a quick real trial once this is built, not decided here.
- Whether to build a small in-game "enter license" text box now or treat
  this as launch-time/storefront-integration scope — depends on how
  distribution actually happens (Steam key vs. direct sale), not decided
  here.
- Revisit Ed25519 (GDExtension or a carefully-reviewed pure-GDScript
  implementation) if the paste-able RSA code turns out to be a genuine UX
  problem in practice — deferred, not rejected outright.

## Operational security

The private key that signs real serials and real builds
(`my_private_key.pem`) must never be committed. `.gitignore` covers it by
name and by extension (`private_key.pem`, `my_private_key.pem`, `*.pem`),
so a plain `git add` can't accidentally stage it — but `.gitignore` only
stops git from tracking it, it does nothing to protect the file itself.

It currently lives unencrypted in the repo root on the key owner's
machine, which is a deliberate trade for
`self_integrity.gd`'s auto-sign-for-local-testing convenience (see
"Status" below) — that feature only works if the private key sits next
to what's being verified. This is acceptable on a machine only the key
owner controls, but it means:

- Anyone with filesystem access to that machine can mint serials or
  re-sign builds. Treat that machine's access controls as part of this
  system's real security boundary, not just the RSA math.
- The only copy should not be *only* here — a password manager
  attachment or an encrypted offline backup is still recommended, since
  losing this file means every previously-issued serial keeps working
  (they don't depend on it) but minting new ones or re-signing future
  builds requires generating a new keypair, re-embedding a new public
  key, and re-fingerprinting (see "Key rotation" above) — existing
  serials signed under the old key still verify unless it's actively
  revoked.
- Never copy `my_private_key.pem` into an exported build's folder for a
  real release — that would ship the ability to forge signatures to
  every player. It belongs only on the developer's own machine.

## Status

Implemented and live-wired on `main`:

- `src/licensing/serial_base32.gd` — Crockford Base32 encode/decode
  (9/9 tests). Godot has no native Base32.
- `src/licensing/serial_codec.gd` — pure payload encode/decode as
  designed above (10/10 tests).
- `src/licensing/signature_ring.gd` — shared "load N public keys, verify
  a raw hash's signature against any of them" primitive (9/9 tests).
  `serial_verifier.gd` and `self_integrity.gd` both delegate to this
  rather than each loading PEMs and calling `Crypto.verify` themselves.
- `src/licensing/serial_verifier.gd` — RSA-2048/SHA-256 verification via
  `SignatureRing`, checks expiry (10/10 tests, using a real generated
  keypair).
- `src/licensing/license_store.gd` — reads the pasted code from a
  `license.txt` file next to the executable (or `user://license.txt`),
  not an in-game typed field (6/6 tests).
- `src/licensing/embedded_public_keys.gd` — the ship-side public key
  list. **A real public key is now embedded** (the matching private key
  lives only on the key owner's machine, gitignored — see "Operational
  security"). Before this, the list was empty, which meant the shipped
  game refused every code, including a genuinely valid one — the correct,
  safe default for that state, not a bug.
- `src/licensing/key_fingerprint.gd` — key-swap resistance (9/9 tests).
  `LicenseGate`/`SelfIntegrity`'s production `_init()` independently
  checks `EmbeddedPublicKeys.PUBLIC_KEY_PEMS`'s SHA-256 fingerprint
  against a value pinned here; a mismatch (someone editing
  `embedded_public_keys.gd` alone to point at a different key) makes
  both gates fall back to an empty ring, which fails closed, rather than
  silently trusting the swapped-in key. Editing both files together
  (a deliberate key rotation) is unaffected.
- `src/licensing/license_gate.gd` — the enforcement point. Split into a
  pure `evaluate()` decision function (fully unit-tested, 6/6) and thin
  Node glue (`_ready()`/`require_licensed()`) that calls
  `get_tree().quit(1)` on failure — the Node glue itself is intentionally
  left to contract-level testing only, per this project's existing
  "engine side effects aren't unit-tested" boundary
  (see `test_water_shader.gd`).
- Registered as the `LicenseGate` autoload in `project.godot`, so it runs
  at the earliest possible boot hook, before any scene loads.
- Checked a **second, independent time** in `scenes/world.gd`'s own
  `_ready()`, which calls `LicenseGate.require_licensed()` again from
  scratch — defense in depth, so bypassing the game requires patching
  more than the one autoload call site.
- A deliberate, transparent development bypass:
  `OS.has_feature("editor")` short-circuits the check to always-licensed.
  This tag is an engine-level distinction that does not exist in exported
  builds, so it opens no bypass in anything actually shipped — it exists
  purely so normal in-editor development/playtesting isn't blocked by an
  unfilled public key. It's a one-line removal if editor runs should be
  gated too.
- `tools/generate_keypair.gd` — never-shipped CLI tool, run once by the
  key owner, to generate the real RSA-2048 keypair.
- `tools/generate_serial.gd` — never-shipped CLI tool that mints a real
  signed serial from `--key`/`--products`/`--id`/`--expiry` args, using
  the exact same `serial_codec.gd`/`serial_base32.gd` the shipped
  verifier reads, so a minted serial is guaranteed to match the format
  the game actually checks.
- `src/licensing/integrity_paths.gd` — pure derivation of the target file
  to hash (the sidecar `.pck`, or the executable itself for an embedded-
  PCK export) and its `.sig` signature path (5/5 tests).
- `src/licensing/self_integrity.gd` — the integrity enforcement gate
  (see "Source/build integrity verification" above). Same pure/glue split
  as `license_gate.gd`: `evaluate()` is fully unit-tested (7/7, real
  generated keypair), `_ready()`/`require_verified()` is thin Node glue
  that reads the real target file + signature off disk and calls
  `get_tree().quit(1)` on failure.
- Registered as the `SelfIntegrity` autoload in `project.godot`, ordered
  **before** `LicenseGate` — verifying the code hasn't been tampered with
  logically comes before trusting that code's own license check.
- Checked a second, independent time in `scenes/world.gd`'s own
  `_ready()`, alongside the license re-check, same defense-in-depth
  reasoning.
- `self_integrity.gd`'s `_auto_sign_if_private_key_present()` —
  local-testing convenience: if `private_key.pem` sits next to the
  target being verified, it's re-signed fresh before every verification
  pass, so iterating on a local export doesn't need a separate manual
  `tools/sign_build.gd` run after every rebuild. A real customer's copy
  never has this file, so this path is never taken for anyone but the
  developer testing locally.
- `tools/sign_build.gd` — never-shipped CLI tool that hashes an exported
  artifact and writes its signature to the `.sig` sidecar `self_integrity.
  gd` reads. Must be run against the actual exported `.pck`/executable,
  never against the raw repo source (see "Source/build integrity
  verification" above for why).
- End-to-end smoke-tested twice (throwaway keypairs, generated in a
  scratch directory outside the repo and deleted immediately after):
  (1) keypair generation → `generate_serial.gd` signing → a valid
  paste-able code; (2) keypair generation → a stand-in package file →
  `sign_build.gd` signing → `self_integrity.gd`'s real `evaluate()`
  accepting the genuine file, rejecting a one-byte tamper, and rejecting
  a missing signature. Nothing from either run was committed anywhere,
  per "the private key must never touch this repository."

**Done** (steps 1-3 of what was originally left to the user):

1. ✅ `tools/generate_keypair.gd` was run, on the key owner's machine, to
   generate the real keypair.
2. ✅ The private-key file (`my_private_key.pem`) is kept only on disk,
   never committed — covered by `.gitignore` (`*.pem`,
   `private_key.pem`, `my_private_key.pem`). It currently sits in the
   repo root purely so `self_integrity.gd`'s auto-sign convenience
   (above) can find it during local testing; it is not otherwise treated
   as safely backed up (see "Operational security" below — a password
   manager attachment or encrypted offline copy is still recommended for
   the only real copy).
3. ✅ The printed public-key PEM is pasted into
   `src/licensing/embedded_public_keys.gd`'s `PUBLIC_KEY_PEMS` list, with
   its fingerprint pinned in `key_fingerprint.gd` (see above).

**Issued serials** (tracked here so a future revocation-list decision has
a record to work from — see "check `license_id` against the local
revocation list" above):

| license_id | product_mask | expiry (unix / date) | purpose |
|---|---|---|---|
| 90001 | 1 (base game) | 1788134400 / 2026-08-31 | Public 7-day trial key, published in `README.md`'s "License Key" section |

**Still left to the user, by design** (this repo intentionally contains
no *other* real signed serials beyond the public trial key above):

1. Use `tools/generate_serial.gd` with the private key to mint further
   real serials (e.g. alpha tester keys) for sale/distribution.
2. To test the full flow locally: drop a code into a `license.txt` next
   to the exported executable (or `user://license.txt`) and run the
   exported build — the editor bypass means Play-button testing
   in-editor won't exercise this path, only an actual export will.
3. **After every export, including patches:** run `tools/sign_build.gd`
   against the freshly exported `.pck` (or executable, for an embedded-PCK
   export) with the same private key, and ship the resulting `.sig`
   alongside it — unless `private_key.pem` is shipped next to that export
   too (never do this for a real release; the auto-sign path above is a
   local-testing-only convenience). An old signature correctly fails
   verification against a newer build — this step isn't optional per
   release, it's part of exporting.

**Known, deliberately unverified assumption:** if `license_gate.gd` or
`self_integrity.gd` were deleted from disk entirely, `project.godot`'s
autoload entry would point at a missing path, and any script referencing
the global `LicenseGate`/`SelfIntegrity` identifier (e.g. `world.gd`'s
own calls) should fail to resolve/compile — a fail-closed outcome
consistent with the "if the check mechanism is removed it should fail to
start" requirement. This was reasoned from how Godot's autoload-name
resolution works, not verified by actually deleting a real project file
and observing the result, since doing that against a live,
concurrently-edited `main` checkout wasn't a safe experiment to run.
Worth a real verification pass (in a disposable worktree, never on
`main`) before treating it as confirmed.

**Note specific to integrity verification:** deleting the check code
still doesn't help an attacker who *also* needs to pass it — but someone
willing to patch source before export can simply not sign the result, or
sign it and ship their own public key... except they can't: the public
key that verifies is embedded in the game binary the attacker doesn't
control the distribution of. What they *can* do is delete the `.sig`
sidecar or the `self_integrity.gd` call site from their own patched copy
before repackaging — which is exactly the "patching the binary" limit
this doc's opening section already prices in. This mechanism's honest
value is raising the cost of casual repackaging (game-crack sites that
redistribute a patched `.pck` without touching the loader/autoload
wiring), not stopping a determined reverse engineer.
