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


## Real bug found live: tools/generate_serial.gd prints the code split
## across multiple lines for readability (docs/licensing.md's own "a
## paste-able block", README's "line breaks are fine"), and a customer
## pasting that whole block into a license.txt keeps the embedded
## newlines. Before this fix, decode() treated '\n' as just another
## out-of-alphabet character and rejected the whole thing -- silently
## turning the documented, encouraged way to save a code into "malformed
## code". Whitespace carries no bits of its own, so ignoring it is safe.
func test_decode_ignores_embedded_newlines_from_the_pretty_printed_block_format():
	var bytes := PackedByteArray()
	for i in 40:
		bytes.append((i * 53 + 7) % 256)
	var encoded := SerialBase32.encode(bytes)
	var with_line_breaks := ""
	for i in encoded.length():
		with_line_breaks += encoded[i]
		if i % 10 == 9:
			with_line_breaks += "\n"
	assert_eq(SerialBase32.decode(with_line_breaks), bytes)


func test_decode_ignores_carriage_returns_and_spaces_too():
	var bytes := PackedByteArray([1, 2, 3, 4, 5])
	var encoded := SerialBase32.encode(bytes)
	var padded := " " + encoded.substr(0, 3) + "\r\n" + encoded.substr(3) + " \t"
	assert_eq(SerialBase32.decode(padded), bytes)


## Whitespace is the only thing decode() should now treat as filler --
## a genuinely wrong character (see the excluded-alphabet test above)
## must still fail the whole decode, not be silently skipped like
## whitespace is.
func test_decode_still_rejects_a_real_invalid_character_alongside_whitespace():
	assert_eq(SerialBase32.decode("A\nI"), PackedByteArray())
