extends RefCounted

## Embedded public keys the shipped game verifies serials against (see
## docs/licensing.md). ONLY the public half ever belongs here -- the
## private key that SIGNS real serials must never be embedded, committed,
## or shipped anywhere near this repository. Generate it yourself, once,
## on a machine you control, and keep it somewhere that never touches git
## (see docs/licensing.md's "Operational security").
##
## PLACEHOLDER: this list is empty until you generate your real keypair
## (see tools/generate_keypair.gd) and paste the PUBLIC half's PEM string
## in below. Until then, by design, EVERY code fails verification --
## LicenseGate has no key to check a signature against, so the game
## refuses to start for anyone, including you in development (see
## world.gd's editor-only bypass for how to keep playtesting without one).
##
## Supports more than one entry for key rotation (docs/licensing.md's own
## section on it): a serial verifying against ANY listed key is accepted,
## so adding a new key here alongside an old one lets you rotate without
## invalidating already-issued serials signed under the old key.
const PUBLIC_KEY_PEMS: Array[String] = [
	# "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----",
]
