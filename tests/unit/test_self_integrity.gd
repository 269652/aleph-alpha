extends GutTest

## SelfIntegrity's DECISION logic (evaluate()) is fully unit-tested here
## with a real injected test keypair -- same shape as test_license_gate.gd.
## Its Node-lifecycle glue (_ready()/require_verified() reading the real
## running executable/pck off disk and calling get_tree().quit() on
## failure) is deliberately NOT exercised here, same "contract tests only"
## boundary test_license_gate.gd already accepts. A bare SelfIntegrity.new()
## is never added to a scene tree in these tests, so _ready() never fires.

const SelfIntegrity = preload("res://src/licensing/self_integrity.gd")
const SignatureRing = preload("res://src/licensing/signature_ring.gd")
const EmbeddedPublicKeys = preload("res://src/licensing/embedded_public_keys.gd")

var _crypto := Crypto.new()
var _private_key: CryptoKey
var gate: SelfIntegrity


func before_all():
	_private_key = _crypto.generate_rsa(2048)


func before_each():
	var ring := SignatureRing.new([_private_key.save_to_string(true)])
	gate = SelfIntegrity.new(ring)


func after_each():
	gate.free()


func _sign(bytes: PackedByteArray) -> PackedByteArray:
	var file_hash := SignatureRing.sha256(bytes)
	return _crypto.sign(HashingContext.HASH_SHA256, file_hash, _private_key)


func test_evaluate_accepts_bytes_with_a_genuine_signature():
	var bytes := "pretend this is the game's compiled pck".to_utf8_buffer()
	var result := gate.evaluate(bytes, _sign(bytes))
	assert_true(result.ok)


func test_evaluate_rejects_bytes_that_were_modified_after_signing():
	var signature := _sign("original bytes".to_utf8_buffer())
	var result := gate.evaluate("tampered bytes".to_utf8_buffer(), signature)
	assert_false(result.ok)
	assert_false(result.reason.is_empty())


func test_evaluate_rejects_a_signature_from_an_unregistered_key():
	var other_private := Crypto.new().generate_rsa(2048)
	var bytes := "some file contents".to_utf8_buffer()
	var file_hash := SignatureRing.sha256(bytes)
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, file_hash, other_private)
	assert_false(gate.evaluate(bytes, signature).ok)


func test_evaluate_rejects_empty_file_bytes():
	# Stands in for "the target file wasn't found" -- the thin glue passes
	# an empty PackedByteArray when FileAccess couldn't read anything.
	var result := gate.evaluate(PackedByteArray(), _sign("anything".to_utf8_buffer()))
	assert_false(result.ok)


func test_evaluate_rejects_a_missing_signature():
	var bytes := "some file contents".to_utf8_buffer()
	var result := gate.evaluate(bytes, PackedByteArray())
	assert_false(result.ok)


## Honest current-repo-state check, mirroring test_license_gate.gd's own:
## with no real key filled in yet, the PRODUCTION gate (no injected ring
## -- the constructor's real default) must reject everything, including
## genuinely well-formed input -- the correct, safe default, not a bug.
func test_the_real_production_gate_rejects_everything_while_no_key_is_embedded():
	assert_true(EmbeddedPublicKeys.PUBLIC_KEY_PEMS.is_empty(), "this test documents the placeholder state, not a permanent assumption")
	var production_gate := SelfIntegrity.new()
	var bytes := "anything at all".to_utf8_buffer()
	assert_false(production_gate.evaluate(bytes, _sign(bytes)).ok)
	production_gate.free()


func test_require_verified_does_not_error_when_given_valid_bytes_directly():
	var bytes := "pretend pck contents".to_utf8_buffer()
	gate.require_verified(bytes, _sign(bytes))
	assert_true(gate.is_verified)
