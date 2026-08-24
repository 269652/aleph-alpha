extends GutTest

## KeyFingerprint pins the EXPECTED fingerprint of the real embedded
## public key(s) (see docs/licensing.md's "Key-swap resistance") --
## checked independently of embedded_public_keys.gd itself, so simply
## editing THAT file's PUBLIC_KEY_PEMS to a different (attacker-
## controlled) key no longer silently "just works": the pinned
## fingerprint here would no longer match.

const KeyFingerprint = preload("res://src/licensing/key_fingerprint.gd")


func test_fingerprint_of_is_deterministic():
	var pems: Array[String] = ["key one", "key two"]
	assert_eq(KeyFingerprint.fingerprint_of(pems), KeyFingerprint.fingerprint_of(pems))


func test_fingerprint_of_is_sensitive_to_the_key_contents():
	var a: Array[String] = ["real public key"]
	var b: Array[String] = ["attacker's own public key"]
	assert_ne(KeyFingerprint.fingerprint_of(a), KeyFingerprint.fingerprint_of(b))


func test_fingerprint_of_is_sensitive_to_key_order():
	var a: Array[String] = ["key one", "key two"]
	var b: Array[String] = ["key two", "key one"]
	assert_ne(KeyFingerprint.fingerprint_of(a), KeyFingerprint.fingerprint_of(b))


func test_fingerprint_of_is_sensitive_to_how_many_keys_are_present():
	var one: Array[String] = ["key one"]
	var two: Array[String] = ["key one", "key two"]
	assert_ne(KeyFingerprint.fingerprint_of(one), KeyFingerprint.fingerprint_of(two))


## The placeholder state (an EMPTY expected fingerprint, matching
## embedded_public_keys.gd's own "empty until a real key exists"
## convention before one was embedded): nothing pinned yet means nothing
## counts as a swap -- an empty pinned expectation must not itself be
## treated as tampering. Exercised via the injectable `expected` param
## (see matches_expected's own doc comment) rather than the real constant,
## since a real fingerprint is pinned below now that a real key exists.
func test_an_empty_expected_fingerprint_matches_anything():
	var pems: Array[String] = ["whatever happens to be embedded right now"]
	assert_true(KeyFingerprint.matches_expected(pems, ""))


func test_matches_expected_accepts_the_real_pinned_keys():
	var real_pems: Array[String] = ["the real embedded key"]
	var pinned := KeyFingerprint.fingerprint_of(real_pems)
	assert_true(KeyFingerprint.matches_expected(real_pems, pinned))


func test_matches_expected_rejects_a_swapped_key():
	var real_pems: Array[String] = ["the real embedded key"]
	var pinned := KeyFingerprint.fingerprint_of(real_pems)
	var swapped_pems: Array[String] = ["an attacker's own key, pasted over the real one"]
	assert_false(KeyFingerprint.matches_expected(swapped_pems, pinned))


func test_matches_expected_with_an_explicit_empty_expectation_also_accepts_anything():
	var pems: Array[String] = ["whatever"]
	assert_true(KeyFingerprint.matches_expected(pems, ""))


## Real regression guard, not a synthetic example: whatever's ACTUALLY
## embedded in embedded_public_keys.gd right now must match what's
## ACTUALLY pinned in KeyFingerprint right now -- if someone edits one
## file without the other (an accidental drift, or an attacker's swap),
## this fails.
func test_the_real_embedded_keys_match_the_real_pinned_fingerprint():
	var EmbeddedPublicKeys = preload("res://src/licensing/embedded_public_keys.gd")
	assert_true(KeyFingerprint.matches_expected(EmbeddedPublicKeys.PUBLIC_KEY_PEMS))
