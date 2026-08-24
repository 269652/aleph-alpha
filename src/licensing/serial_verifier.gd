extends RefCounted

## Verifies an entered/pasted serial code end to end (see docs/licensing.md):
## Base32-decode, split payload from signature, check the signature against
## every registered public key, check expiry. Never touches a private key
## -- this is the ONLY half that ships in the game.

const SerialBase32 = preload("res://src/licensing/serial_base32.gd")
const SerialCodec = preload("res://src/licensing/serial_codec.gd")

## RSA-2048 signature length in bytes -- see docs/licensing.md's size math.
const SIGNATURE_SIZE := 256

var _public_keys: Array[CryptoKey] = []
var _crypto := Crypto.new()


## `public_key_pems`: one or more PEM-encoded PUBLIC-only keys (see
## docs/licensing.md's "Key rotation") -- a code verifying against ANY
## registered key is accepted, so a lost/rotated private key doesn't
## invalidate already-issued serials once the new public key ships
## alongside the old one in a future patch. A PEM string that fails to
## load is silently skipped rather than erroring the whole verifier --
## one malformed embedded constant shouldn't take every other key down
## with it.
func _init(public_key_pems: Array[String] = []) -> void:
	for pem in public_key_pems:
		var key := CryptoKey.new()
		if key.load_from_string(pem, true) == OK:
			_public_keys.append(key)


## Full verification of one pasted code. `current_unix_time` defaults to
## the real system clock; tests pass an explicit value so expiry logic is
## deterministic rather than dependent on when the test happens to run.
##
## Returns {"valid": bool, "product_mask": int, "license_id": int,
## "expiry_unix": int, "reason": String}. `reason` exists for logs/
## diagnostics only -- see docs/licensing.md's "generic failure message"
## rule: nothing that surfaces to the player should show `reason`, since
## distinguishing "bad checksum" from "bad signature" from "expired" in the
## UI would hand a would-be keygen author a debugging oracle for free.
func verify_code(code: String, current_unix_time: int = -1) -> Dictionary:
	var raw := SerialBase32.decode(code)
	if raw.size() != SerialCodec.PAYLOAD_SIZE + SIGNATURE_SIZE:
		return _invalid("malformed code")

	var payload := raw.slice(0, SerialCodec.PAYLOAD_SIZE)
	var signature := raw.slice(SerialCodec.PAYLOAD_SIZE)
	var decoded := SerialCodec.decode_payload(payload)
	if decoded.is_empty():
		return _invalid("unrecognized payload format")

	if not _signature_matches_any_key(payload, signature):
		return _invalid("signature does not match any known key")

	var expiry: int = decoded.expiry_unix
	if expiry != 0:
		var now: float = float(current_unix_time) if current_unix_time >= 0 else Time.get_unix_time_from_system()
		if now > float(expiry):
			return _invalid("expired")

	return {
		"valid": true,
		"product_mask": decoded.product_mask,
		"license_id": decoded.license_id,
		"expiry_unix": expiry,
		"reason": "",
	}


func _signature_matches_any_key(payload: PackedByteArray, signature: PackedByteArray) -> bool:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload)
	var hash := context.finish()
	for key in _public_keys:
		if _crypto.verify(HashingContext.HASH_SHA256, hash, signature, key):
			return true
	return false


func _invalid(reason: String) -> Dictionary:
	return {"valid": false, "product_mask": 0, "license_id": 0, "expiry_unix": 0, "reason": reason}
