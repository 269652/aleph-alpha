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

## Status

Pure design, nothing implemented. Depends on nothing else in this project
— no gameplay system reads or is gated by this, it's the first design pass
for this concern.
