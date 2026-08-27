extends RefCounted

## Verifies an entered/pasted serial code end to end (see docs/licensing.md):
## Base32-decode, split payload from signature, check the signature against
## every registered public key, check expiry. Never touches a private key
## -- this is the ONLY half that ships in the game.

const SerialBase32 = preload("res://src/licensing/serial_base32.gd")
const SerialCodec = preload("res://src/licensing/serial_codec.gd")
const SignatureRing = preload("res://src/licensing/signature_ring.gd")

## RSA-2048 signature length in bytes -- see docs/licensing.md's size math.
const SIGNATURE_SIZE := 256

var _ring: SignatureRing


## `public_key_pems`: one or more PEM-encoded PUBLIC-only keys (see
## docs/licensing.md's "Key rotation") -- a code verifying against ANY
## registered key is accepted, so a lost/rotated private key doesn't
## invalidate already-issued serials once the new public key ships
## alongside the old one in a future patch. Delegates the actual
## multi-key load-and-verify to SignatureRing, the same shared primitive
## SelfIntegrity uses for signed build hashes -- one malformed embedded
## constant still can't take every other key down with it (see
## SignatureRing's own doc comment).
func _init(public_key_pems: Array[String] = []) -> void:
	_ring = SignatureRing.new(public_key_pems)


## Full verification of one pasted code. `current_unix_time` defaults to
## the real system clock; tests pass an explicit value so expiry logic is
## deterministic rather than dependent on when the test happens to run.
##
## Returns {"valid": bool, "product_mask": int, "license_id": int,
## "expiry_unix": int, "github_user_id": int, "reason": String}. `reason`
## exists for logs/diagnostics only -- see docs/licensing.md's "generic
## failure message" rule: nothing that surfaces to the player should show
## `reason`, since distinguishing "bad checksum" from "bad signature" from
## "expired" in the UI would hand a would-be keygen author a debugging
## oracle for free.
func verify_code(code: String, current_unix_time: int = -1) -> Dictionary:
	var raw := SerialBase32.decode(code)
	# The payload can be either of two known lengths (see SerialCodec's own
	# doc comment: V1, or V2 with an appended GitHub-bound user id) --
	# whichever the total length implies is what gets sliced off; if it
	# matches neither, decode_payload() below rejects it anyway.
	var payload_size := raw.size() - SIGNATURE_SIZE
	var is_known_size := (
		payload_size == SerialCodec.PAYLOAD_SIZE
		or payload_size == SerialCodec.PAYLOAD_SIZE_WITH_GITHUB_BINDING
	)
	if not is_known_size:
		return _invalid("malformed code")

	var payload := raw.slice(0, payload_size)
	var signature := raw.slice(payload_size)
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
		"github_user_id": decoded.github_user_id,
		"reason": "",
	}


func _signature_matches_any_key(payload: PackedByteArray, signature: PackedByteArray) -> bool:
	return _ring.verify_hash(SignatureRing.sha256(payload), signature)


func _invalid(reason: String) -> Dictionary:
	return {
		"valid": false,
		"product_mask": 0,
		"license_id": 0,
		"expiry_unix": 0,
		"github_user_id": 0,
		"reason": reason,
	}
