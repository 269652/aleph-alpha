extends RefCounted

## Pins the EXPECTED fingerprint of the real embedded public key(s) (see
## docs/licensing.md's "Key-swap resistance") -- checked independently of
## embedded_public_keys.gd itself, in LicenseGate's and SelfIntegrity's own
## _init(), so simply editing THAT file's PUBLIC_KEY_PEMS to a different
## (attacker-controlled) key no longer silently "just works": the
## fingerprint recorded HERE would no longer match, and both gates refuse
## to start rather than trust the swapped key.
##
## Like embedded_public_keys.gd, this is ordinary readable source -- it
## does NOT stop a determined person willing to edit both files correctly
## (see docs/licensing.md's own "Read first: what this actually defends
## against" -- the same universal limitation applies here). What it stops
## is the casual, single-file swap: someone who only patches
## embedded_public_keys.gd -- the obvious place to look for "the key
## check" -- gets a hard failure instead of a working keygen.

## SHA-256 hex digest of the real embedded PUBLIC_KEY_PEMS list (see
## fingerprint_of for exactly how it's computed). PLACEHOLDER while empty
## -- matches embedded_public_keys.gd's own "empty until a real key is
## generated" state, and matches_expected() treats an empty pin as
## "nothing to have swapped away from yet", not as tampering.
##
## Set this to fingerprint_of(EmbeddedPublicKeys.PUBLIC_KEY_PEMS) once a
## real key is embedded, and again whenever you deliberately rotate keys
## (docs/licensing.md's "Key rotation") -- test_the_real_embedded_keys_
## match_the_real_pinned_fingerprint fails loudly if the two ever drift
## apart, whether by an attacker's swap or your own forgetting to update
## both files together.
const EXPECTED_FINGERPRINT_HEX := "7713327705750006b44158732d0c0fdf1fb727340a9d813a4aee56def83a3871"


## SHA-256 hex digest of `pems`, joined in order with a delimiter that
## can't appear inside a PEM block itself -- order- and count-sensitive,
## so appending, removing, or reordering a key changes the fingerprint
## exactly as much as swapping one out does.
static func fingerprint_of(pems: Array[String]) -> String:
	return "\n---\n".join(pems).sha256_text()


## Whether `pems` matches the pinned expectation. `expected` defaults to
## the real EXPECTED_FINGERPRINT_HEX above -- what actually runs in the
## shipped game -- tests pass an explicit fingerprint instead, the same
## "inject what varies" shape SerialVerifier.verify_code's
## current_unix_time parameter already uses. An empty expected fingerprint
## (the placeholder state) accepts anything -- see this file's own doc
## comment.
static func matches_expected(pems: Array[String], expected: String = EXPECTED_FINGERPRINT_HEX) -> bool:
	if expected.is_empty():
		return true
	return fingerprint_of(pems) == expected
