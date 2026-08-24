extends GutTest

## LicenseGate's DECISION logic (evaluate()) is fully unit-tested here with
## a real injected test keypair. Its Node-lifecycle glue (_ready() reading
## the real license file and calling get_tree().quit() on failure) is
## deliberately NOT exercised here -- same "contract tests only, the real
## side effect can't be cleanly asserted headless" boundary
## test_water_shader.gd already accepts for its own engine-level effects.
## A bare LicenseGate.new() is never added to a scene tree in these tests,
## so _ready() never fires and evaluate() can be called directly and safely.

const LicenseGate = preload("res://src/licensing/license_gate.gd")
const SerialVerifier = preload("res://src/licensing/serial_verifier.gd")
const SerialCodec = preload("res://src/licensing/serial_codec.gd")
const SerialBase32 = preload("res://src/licensing/serial_base32.gd")
const EmbeddedPublicKeys = preload("res://src/licensing/embedded_public_keys.gd")

var _crypto := Crypto.new()
var _private_key: CryptoKey
var gate: LicenseGate


func before_all():
	_private_key = _crypto.generate_rsa(2048)


func before_each():
	var verifier := SerialVerifier.new([_private_key.save_to_string(true)])
	gate = LicenseGate.new(verifier)


func after_each():
	gate.free()


func _sign_code(product_mask: int, license_id: int) -> String:
	var payload := SerialCodec.encode_payload(product_mask, license_id)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload)
	var signature := _crypto.sign(HashingContext.HASH_SHA256, context.finish(), _private_key)
	return SerialBase32.encode(payload + signature)


func test_evaluate_accepts_a_genuinely_signed_code():
	var code := _sign_code(0b11, 42)
	var result := gate.evaluate(code)
	assert_true(result.licensed)
	assert_eq(result.product_mask, 0b11)


func test_evaluate_rejects_an_empty_code():
	var result := gate.evaluate("")
	assert_false(result.licensed)
	assert_false(result.reason.is_empty())


func test_evaluate_rejects_garbage():
	assert_false(gate.evaluate("NOT-A-REAL-CODE").licensed)


func test_evaluate_rejects_a_code_signed_by_an_unregistered_key():
	var other_private := Crypto.new().generate_rsa(2048)
	var payload := SerialCodec.encode_payload(1, 1)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload)
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, context.finish(), other_private)
	var code := SerialBase32.encode(payload + signature)
	assert_false(gate.evaluate(code).licensed)


## Honest current-repo-state check: a real key IS now embedded (see
## embedded_public_keys.gd), so the PRODUCTION gate (no injected verifier --
## the constructor's real default) must still reject a code signed by any
## OTHER key -- a genuine-accept test would need the real private key,
## which must never exist in this repo (see docs/licensing.md's
## "Operational security"), so this is the strongest check exercisable here.
func test_the_real_production_gate_rejects_a_code_signed_by_an_unregistered_key():
	assert_false(EmbeddedPublicKeys.PUBLIC_KEY_PEMS.is_empty(), "a real key should now be embedded")
	var production_gate := LicenseGate.new()
	var other_private := Crypto.new().generate_rsa(2048)
	var payload := SerialCodec.encode_payload(1, 1)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload)
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, context.finish(), other_private)
	var code := SerialBase32.encode(payload + signature)
	assert_false(production_gate.evaluate(code).licensed)
	production_gate.free()


## require_licensed() must not error just because this test never added
## the node to a real scene tree (get_tree() is null outside one) -- the
## happy path never reaches the quit() branch at all, so this is safe to
## call directly. Passes an explicit code rather than letting it read a
## real file, the same "inject what varies" shape verify_code's
## current_unix_time parameter already uses.
func test_require_licensed_does_not_error_on_a_valid_code():
	var code := _sign_code(1, 1)
	gate.require_licensed(code)
	assert_true(gate.is_licensed)


## check_licensed() is require_licensed() minus the quit() side effect --
## the non-fatal half World's boot uses so it can show an in-game "enter
## your key" screen instead of the process just ending (see
## scenes/world.gd, docs/licensing.md's "In-game license entry"). Same
## flag-setting/logging behavior, just never calls get_tree().quit().
func test_check_licensed_sets_is_licensed_true_on_a_valid_code():
	var code := _sign_code(0b1, 7)
	var result := gate.check_licensed(code)
	assert_true(gate.is_licensed)
	assert_eq(gate.product_mask, 0b1)
	assert_true(result.licensed)


## The whole point: an invalid/missing code must be safe to check
## (flags set, no crash) WITHOUT ending the process -- unlike
## require_licensed(), which would (if a real tree existed to quit).
## check_licensed() logging the failure via push_error() is expected,
## real, intentional behavior (see its own doc comment) -- claim it with
## assert_push_error() rather than let GUT flag it as an unexpected error.
func test_check_licensed_sets_is_licensed_false_on_an_invalid_code_without_quitting():
	var result := gate.check_licensed("NOT-A-REAL-CODE")
	assert_false(gate.is_licensed)
	assert_false(result.licensed)
	assert_push_error("License check failed:")
