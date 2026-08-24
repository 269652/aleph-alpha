extends GutTest

## SignatureRing is the shared "load N public keys, check a raw hash's
## signature against any of them" primitive (see docs/licensing.md) --
## used by both SerialVerifier (signed serials) and SelfIntegrity (signed
## build hashes) so there is exactly one place that loads a PEM and calls
## Crypto.verify, not two copies to keep in sync.

const SignatureRing = preload("res://src/licensing/signature_ring.gd")

var _crypto := Crypto.new()
var _private_key: CryptoKey


func before_all():
	_private_key = _crypto.generate_rsa(2048)


func _sign(data: PackedByteArray) -> PackedByteArray:
	var file_hash := SignatureRing.sha256(data)
	return _crypto.sign(HashingContext.HASH_SHA256, file_hash, _private_key)


func test_accepts_a_genuine_signature():
	var ring := SignatureRing.new([_private_key.save_to_string(true)])
	var data := "hello world".to_utf8_buffer()
	var signature := _sign(data)
	assert_true(ring.verify_hash(SignatureRing.sha256(data), signature))


func test_rejects_a_tampered_hash():
	var ring := SignatureRing.new([_private_key.save_to_string(true)])
	var signature := _sign("original".to_utf8_buffer())
	assert_false(ring.verify_hash(SignatureRing.sha256("tampered".to_utf8_buffer()), signature))


func test_rejects_a_signature_from_an_unregistered_key():
	var other_private := Crypto.new().generate_rsa(2048)
	var data := "hello world".to_utf8_buffer()
	var file_hash := SignatureRing.sha256(data)
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, file_hash, other_private)

	var ring := SignatureRing.new([_private_key.save_to_string(true)])
	assert_false(ring.verify_hash(file_hash, signature))


func test_accepts_either_of_two_registered_keys_for_rotation():
	var second_private := Crypto.new().generate_rsa(2048)
	var ring := SignatureRing.new([
		_private_key.save_to_string(true),
		second_private.save_to_string(true),
	])
	var data := "rotated".to_utf8_buffer()
	var file_hash := SignatureRing.sha256(data)
	var old_signature := _crypto.sign(HashingContext.HASH_SHA256, file_hash, _private_key)
	var new_signature := Crypto.new().sign(HashingContext.HASH_SHA256, file_hash, second_private)
	assert_true(ring.verify_hash(file_hash, old_signature))
	assert_true(ring.verify_hash(file_hash, new_signature))


## CryptoKey.load_from_string logs a real engine ERROR when a PEM fails
## to parse (confirmed via probe: "Error parsing key" from
## crypto_mbedtls.cpp) -- unavoidable, not something GDScript can
## suppress. The engine's return code is still FAILED and our code still
## correctly skips the key, so assert_engine_error acknowledges the
## expected log line rather than the test failing on it.
func test_skips_a_malformed_pem_without_crashing():
	var ring := SignatureRing.new(["not a real pem"])
	assert_eq(ring.key_count(), 0)
	assert_engine_error("Error parsing key")


func test_key_count_reflects_only_successfully_loaded_keys():
	var ring := SignatureRing.new([_private_key.save_to_string(true), "garbage"])
	assert_eq(ring.key_count(), 1)
	assert_engine_error("Error parsing key")


func test_empty_ring_verifies_nothing():
	var ring := SignatureRing.new([])
	var data := "hello".to_utf8_buffer()
	var signature := _sign(data)
	assert_false(ring.verify_hash(SignatureRing.sha256(data), signature))


## Known NIST test vector -- SHA-256 of the empty string. Pinning a
## published cryptographic constant, not an eyeballed value (see this
## project's "no manual tuning" rule -- a real standard's fixed output
## is exactly the kind of constant that rule is fine with pinning).
func test_sha256_matches_the_published_empty_string_vector():
	var digest := SignatureRing.sha256(PackedByteArray())
	var hex := digest.hex_encode()
	assert_eq(hex, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")


func test_sha256_is_deterministic_and_input_sensitive():
	var a := SignatureRing.sha256("abc".to_utf8_buffer())
	var b := SignatureRing.sha256("abc".to_utf8_buffer())
	var c := SignatureRing.sha256("abd".to_utf8_buffer())
	assert_eq(a, b)
	assert_ne(a, c)
	assert_eq(a.size(), 32)
