extends GutTest

## Real RSA round-trip tests, not mocked -- a genuine keypair is generated
## once for this whole file (RSA-2048 keygen is real work, not worth
## repeating per test) and used to actually sign test codes the same way
## the never-shipped signing tool will.

const SerialVerifier = preload("res://src/licensing/serial_verifier.gd")
const SerialCodec = preload("res://src/licensing/serial_codec.gd")
const SerialBase32 = preload("res://src/licensing/serial_base32.gd")

var _crypto := Crypto.new()
var _private_key: CryptoKey
var _public_key_pem: String
var verifier: SerialVerifier


func before_all():
	_private_key = _crypto.generate_rsa(2048)
	_public_key_pem = _private_key.save_to_string(true)


func before_each():
	verifier = SerialVerifier.new([_public_key_pem])


func _hash_of(payload: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(payload)
	return ctx.finish()


func _sign_with(private_key: CryptoKey, product_mask: int, license_id: int, expiry_unix: int = 0, github_user_id: int = 0) -> String:
	var payload := SerialCodec.encode_payload(product_mask, license_id, expiry_unix, github_user_id)
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, _hash_of(payload), private_key)
	return SerialBase32.encode(payload + signature)


func _sign_code(product_mask: int, license_id: int, expiry_unix: int = 0) -> String:
	return _sign_with(_private_key, product_mask, license_id, expiry_unix)


func test_a_genuinely_signed_code_verifies_as_valid():
	var code := _sign_code(0b1, 111)
	var result := verifier.verify_code(code)
	assert_true(result.valid)
	assert_eq(result.product_mask, 0b1)
	assert_eq(result.license_id, 111)


func test_a_tampered_payload_fails_verification():
	var code := _sign_code(0b1, 111)
	# Flip one character inside the code -- the signature no longer matches
	# whatever payload that produces, however it decodes.
	var flipped := "A" if code[1] != "A" else "B"
	var tampered := code.left(1) + flipped + code.substr(2)
	assert_false(verifier.verify_code(tampered).valid)


func test_a_code_signed_by_a_different_key_is_rejected():
	var other_private := Crypto.new().generate_rsa(2048)
	var code := _sign_with(other_private, 1, 1)
	assert_false(verifier.verify_code(code).valid)


func test_malformed_code_is_rejected_not_crashed_on():
	assert_false(verifier.verify_code("NOTAREALCODE").valid)
	assert_false(verifier.verify_code("").valid)


func test_expired_code_is_rejected():
	var code := _sign_code(1, 1, 1000)
	var result := verifier.verify_code(code, 2000)  # "now" is after expiry
	assert_false(result.valid)


func test_zero_expiry_never_expires():
	var code := _sign_code(1, 1, 0)
	var result := verifier.verify_code(code, 99999999999)
	assert_true(result.valid)


func test_unexpired_code_is_accepted():
	var code := _sign_code(1, 1, 2000)
	var result := verifier.verify_code(code, 1000)  # "now" is before expiry
	assert_true(result.valid)


## Key rotation (docs/licensing.md): once BOTH the old and new public keys
## are registered, a code signed by EITHER private key must still verify --
## a lost/rotated key must not silently invalidate already-issued serials.
func test_verifies_against_any_registered_key_not_just_the_first():
	var second_private := Crypto.new().generate_rsa(2048)
	var second_public_pem := second_private.save_to_string(true)
	var multi_verifier := SerialVerifier.new([_public_key_pem, second_public_pem])

	var code := _sign_with(second_private, 1, 1)
	assert_true(multi_verifier.verify_code(code).valid)


func test_reports_a_reason_string_on_failure_for_logs_not_the_player():
	var result := verifier.verify_code("garbage")
	assert_false(result.valid)
	assert_false(result.reason.is_empty())


func test_a_valid_result_reports_no_reason():
	var code := _sign_code(1, 1)
	assert_eq(verifier.verify_code(code).reason, "")


# -- GitHub-bound personal keys (see docs/licensing.md's "Personal /
# GitHub-bound keys") -- longer V2 payload, still verifies end to end. --

func test_a_github_bound_code_verifies_and_reports_the_bound_id():
	var code := _sign_with(_private_key, 0b1, 111, 0, 123456)
	var result := verifier.verify_code(code)
	assert_true(result.valid)
	assert_eq(result.github_user_id, 123456)


func test_an_unbound_code_reports_github_user_id_zero():
	var code := _sign_code(1, 1)
	assert_eq(verifier.verify_code(code).github_user_id, 0)


func test_a_tampered_github_bound_payload_fails_verification():
	var code := _sign_with(_private_key, 0b1, 111, 0, 123456)
	var flipped := "A" if code[1] != "A" else "B"
	var tampered := code.left(1) + flipped + code.substr(2)
	assert_false(verifier.verify_code(tampered).valid)


func test_a_github_bound_code_signed_by_a_different_key_is_rejected():
	var other_private := Crypto.new().generate_rsa(2048)
	var code := _sign_with(other_private, 1, 1, 0, 123456)
	assert_false(verifier.verify_code(code).valid)
