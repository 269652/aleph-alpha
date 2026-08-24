extends RefCounted

## Base32 encode/decode for a fixed-length byte blob (see
## docs/licensing.md) -- turns a raw payload+signature into a string a
## customer can read and paste back without ambiguity.
##
## Crockford's alphabet, not RFC4648's: excludes I/L/O (visually
## confusable with 1/1/0) and U (avoids accidental profanity when
## characters are read aloud/combined). No "=" padding: every caller here
## knows the exact byte length it expects back (a fixed-width payload +
## a fixed-width RSA signature, see serial_codec.gd/serial_verifier.gd), so
## there is no ambiguity for decode to resolve that padding would exist to
## solve.
##
## Pure bit-packing, no cryptography of its own -- this only makes bytes
## readable, it does not protect them.

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


## Packs `bytes` 5 bits at a time into ALPHABET characters. A byte count
## that isn't a multiple of 5 BITS (almost always) leaves a final partial
## group, right-padded with zero bits -- decode() below drops that same
## padding on the way back rather than trying to interpret it as data.
static func encode(bytes: PackedByteArray) -> String:
	var result := ""
	var buffer := 0
	var bits_in_buffer := 0
	for byte in bytes:
		buffer = (buffer << 8) | byte
		bits_in_buffer += 8
		while bits_in_buffer >= 5:
			bits_in_buffer -= 5
			var index := (buffer >> bits_in_buffer) & 0x1F
			result += ALPHABET[index]
	if bits_in_buffer > 0:
		var index := (buffer << (5 - bits_in_buffer)) & 0x1F
		result += ALPHABET[index]
	return result


## Inverse of encode(). Case-insensitive (a customer retyping a code
## shouldn't have to match case exactly). Returns an EMPTY array -- never a
## partial/best-effort result -- the moment any character falls outside
## ALPHABET, so a caller can tell "malformed input" apart from "this
## legitimately decoded to zero bytes" only by checking the input wasn't
## already empty; every real caller here already knows it's passing a
## non-empty code.
static func decode(text: String) -> PackedByteArray:
	var result := PackedByteArray()
	var buffer := 0
	var bits_in_buffer := 0
	for character in text.to_upper():
		var index := ALPHABET.find(character)
		if index < 0:
			return PackedByteArray()
		buffer = (buffer << 5) | index
		bits_in_buffer += 5
		if bits_in_buffer >= 8:
			bits_in_buffer -= 8
			var byte := (buffer >> bits_in_buffer) & 0xFF
			result.append(byte)
	return result
