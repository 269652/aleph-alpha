extends GutTest

const SerialBase32 = preload("res://src/licensing/serial_base32.gd")


func test_empty_input_encodes_to_empty_string():
	assert_eq(SerialBase32.encode(PackedByteArray()), "")


func test_empty_string_decodes_to_empty_bytes():
	assert_eq(SerialBase32.decode(""), PackedByteArray())


func test_round_trips_a_single_byte():
	for value in [0, 1, 42, 127, 255]:
		var bytes := PackedByteArray([value])
		assert_eq(SerialBase32.decode(SerialBase32.encode(bytes)), bytes, "value %d failed to round-trip" % value)


func test_round_trips_arbitrary_byte_lengths():
	# Base32 packs 5 bits per character, so lengths that aren't a multiple
	# of 5 BITS (i.e. most byte counts) are exactly where padding bugs hide.
	for length in range(0, 20):
		var bytes := PackedByteArray()
		for i in length:
			bytes.append((i * 37 + 11) % 256)
		assert_eq(SerialBase32.decode(SerialBase32.encode(bytes)), bytes, "length %d failed to round-trip" % length)


func test_encoded_output_uses_only_alphabet_characters():
	var bytes := PackedByteArray([0, 255, 128, 17, 200])
	var encoded := SerialBase32.encode(bytes)
	for i in encoded.length():
		assert_true(SerialBase32.ALPHABET.contains(encoded[i]), "unexpected character %s" % encoded[i])


## Crockford-style alphabet: no ambiguous 0/O, 1/I/L, and no U (avoids
## accidental profanity) -- exactly the "safe for a human to read/type back"
## property docs/licensing.md's paste-able code relies on.
func test_alphabet_excludes_visually_ambiguous_and_flagged_characters():
	for excluded in ["I", "L", "O", "U"]:
		assert_false(SerialBase32.ALPHABET.contains(excluded), "%s should not be in the alphabet" % excluded)
	assert_eq(SerialBase32.ALPHABET.length(), 32)


func test_decode_rejects_a_character_outside_the_alphabet():
	# "I" is deliberately excluded from the alphabet above.
	assert_eq(SerialBase32.decode("AI"), PackedByteArray())


func test_decode_is_case_insensitive():
	var bytes := PackedByteArray([1, 2, 3, 4, 5])
	var encoded := SerialBase32.encode(bytes)
	assert_eq(SerialBase32.decode(encoded.to_lower()), bytes)


func test_encoding_is_deterministic():
	var bytes := PackedByteArray([9, 8, 7, 6])
	assert_eq(SerialBase32.encode(bytes), SerialBase32.encode(bytes))
