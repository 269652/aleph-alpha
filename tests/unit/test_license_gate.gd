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


## Honest current-repo-state check: with no real key filled in yet (see
## embedded_public_keys.gd's placeholder), the PRODUCTION gate (no injected
## verifier -- the constructor's real default) must reject every code,
## including a well-formed one -- "always refuses until a key exists" is
## the correct, safe default for this state, not a bug to fix later.
func test_the_real_production_gate_rejects_everything_while_no_key_is_embedded():
	assert_true(EmbeddedPublicKeys.PUBLIC_KEY_PEMS.is_empty(), "this test documents the placeholder state, not a permanent assumption")
	var production_gate := LicenseGate.new()
	var code := _sign_code(1, 1)
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
