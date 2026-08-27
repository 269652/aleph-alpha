extends RefCounted

## Shared RSA multi-key verification primitive (see docs/licensing.md).
## Holds N registered PUBLIC keys and checks whether a raw SHA-256 hash
## was signed by ANY of them. Both SerialVerifier (signed serials) and
## SelfIntegrity (signed build hashes) delegate to this instead of each
## loading PEMs and calling Crypto.verify themselves -- one place to fix
## a bug in, not two copies that can silently drift apart.

const HASH_TYPE := HashingContext.HASH_SHA256

var _keys: Array[CryptoKey] = []
var _crypto := Crypto.new()


## `public_key_pems`: one or more PEM-encoded PUBLIC-only keys. A PEM that
## fails to load is silently skipped (see key_count()) rather than
## erroring the whole ring -- one malformed embedded constant shouldn't
## take every other key down with it.
func _init(public_key_pems: Array[String] = []) -> void:
	for pem in public_key_pems:
		var key := CryptoKey.new()
		if key.load_from_string(pem, true) == OK:
			_keys.append(key)


## How many of the given PEMs actually loaded -- mainly for diagnosing a
## malformed embedded constant (see EmbeddedPublicKeys' own placeholder
## comment).
func key_count() -> int:
	return _keys.size()


## True if `signature` is a valid RSA signature of `file_hash` under ANY
## registered key -- accepting any one of several keys is what makes key
## rotation possible (docs/licensing.md's "Key rotation": an old key stays
## registered alongside a new one so already-issued signatures don't stop
## verifying).
func verify_hash(file_hash: PackedByteArray, signature: PackedByteArray) -> bool:
	for key in _keys:
		if _crypto.verify(HASH_TYPE, file_hash, signature, key):
			return true
	return false


## SHA-256 of arbitrary bytes. Static + stateless so callers (SelfIntegrity
## hashing a multi-hundred-MB file) don't need a SignatureRing instance
## just to hash something before checking it.
##
## `update()` on a zero-length PackedByteArray logs a real engine ERROR
## (confirmed via probe: "Condition 'len == 0' is true" from
## hashing_context.cpp) even though start()+finish() alone already
## produces the correct digest for empty input -- skip the call rather
## than let a plausible edge case (an empty/corrupted target file) print
## a scary but harmless error every time it's hit.
static func sha256(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HASH_TYPE)
	if not bytes.is_empty():
		context.update(bytes)
	return context.finish()


## Signs `file_hash` with a PRIVATE key -- the inverse of verify_hash, used
## only by dev-side tooling that actually HOLDS a private key
## (tools/sign_build.gd, SelfIntegrity's own local-testing auto-sign path)
## -- never by anything that ships. Static: signing needs no registered key
## ring, just the one private key doing the signing.
static func sign_hash(file_hash: PackedByteArray, private_key: CryptoKey) -> PackedByteArray:
	return Crypto.new().sign(HASH_TYPE, file_hash, private_key)
