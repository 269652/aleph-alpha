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
## a real key IS now embedded, so the PRODUCTION gate (no injected ring --
## the constructor's real default) must still reject a signature made by
## any OTHER key -- `_sign()` signs with this test file's own throwaway
## keypair, never the real embedded one, so this is genuinely "signed by
## an unregistered key," not a stand-in for "no key exists yet."
func test_the_real_production_gate_rejects_a_signature_from_an_unregistered_key():
	assert_false(EmbeddedPublicKeys.PUBLIC_KEY_PEMS.is_empty(), "a real key should now be embedded")
	var production_gate := SelfIntegrity.new()
	var bytes := "anything at all".to_utf8_buffer()
	assert_false(production_gate.evaluate(bytes, _sign(bytes)).ok)
	production_gate.free()


func test_require_verified_does_not_error_when_given_valid_bytes_directly():
	var bytes := "pretend pck contents".to_utf8_buffer()
	gate.require_verified(bytes, _sign(bytes))
	assert_true(gate.is_verified)


# -- auto-sign for local testing (see docs/licensing.md, IntegrityPaths. --
# -- private_key_path_for) -- reported live: "make it so that the source --
# -- auto signs itself on every start if private key is present in ------
# -- source folder", so iterating locally doesn't need a separate manual --
# -- tools/sign_build.gd run after every rebuild. Real file I/O against ---
# -- real, GLOBALIZED OS paths (not Godot's user:// scheme) -- matches ----
# -- what OS.get_executable_path() actually returns in production, and ---
# -- CryptoKey.load/save (a lower-level engine API, unlike FileAccess) ----
# -- isn't confirmed to understand Godot's virtual path prefixes. ---------

var _test_dir: String
var _test_target_path: String
var _test_signature_path: String
var _test_key_path: String


func after_each():
	gate.free()
	if _test_dir != "" and DirAccess.dir_exists_absolute(_test_dir):
		for file_name in DirAccess.get_files_at(_test_dir):
			DirAccess.remove_absolute(_test_dir.path_join(file_name))
		DirAccess.remove_absolute(_test_dir)


func _use_real_scratch_dir() -> void:
	_test_dir = ProjectSettings.globalize_path("user://self_integrity_test")
	DirAccess.make_dir_absolute(_test_dir)
	_test_target_path = _test_dir.path_join("target.bin")
	_test_signature_path = _test_target_path + ".sig"
	_test_key_path = _test_dir.path_join("private_key.pem")


func _write(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


## A private key sitting next to the target (IntegrityPaths.
## private_key_path_for) gets used to sign the target fresh, and the
## freshly-signed target then verifies successfully -- no manual
## tools/sign_build.gd run needed.
func test_auto_signs_and_then_verifies_when_a_private_key_sits_next_to_the_target():
	_use_real_scratch_dir()
	_write(_test_target_path, "pretend pck contents".to_utf8_buffer())
	_private_key.save(_test_key_path, false)

	gate.require_verified_at(_test_target_path)

	assert_true(gate.is_verified, "a fresh auto-sign should verify successfully")
	assert_true(FileAccess.file_exists(_test_signature_path), "auto-sign should have written a real .sig file")


## Overwrites a STALE/wrong signature already sitting there -- the whole
## point is "don't need to remember to re-sign after every rebuild", which
## only works if a leftover old signature doesn't block the fresh one.
func test_auto_sign_overwrites_a_stale_signature():
	_use_real_scratch_dir()
	_write(_test_target_path, "new contents after a rebuild".to_utf8_buffer())
	_write(_test_signature_path, "stale signature bytes from an old build".to_utf8_buffer())
	_private_key.save(_test_key_path, false)

	gate.require_verified_at(_test_target_path)

	assert_true(gate.is_verified)


## No private key present -- exactly a real customer's copy -- must NOT
## auto-sign anything; falls through to the ordinary verify-only path
## (which fails here since there's no real signature either).
func test_does_not_auto_sign_when_no_private_key_is_present():
	_use_real_scratch_dir()
	_write(_test_target_path, "pretend pck contents".to_utf8_buffer())

	gate.require_verified_at(_test_target_path)

	# The real failure path push_error()s (assert_push_error) and
	# (harmlessly, since this bare SelfIntegrity was never added to a
	# scene tree) tries get_tree(), which logs a real engine-level
	# diagnostic (assert_engine_error) -- both expected, same "acknowledge
	# the real log rather than suppress it" pattern
	# test_skips_a_malformed_pem_without_crashing already established.
	assert_push_error("Integrity check failed")
	assert_engine_error("data.tree")
	assert_false(gate.is_verified)
	assert_false(FileAccess.file_exists(_test_signature_path), "no private key present -- nothing should get written")
