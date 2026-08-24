extends RefCounted

## The signed payload's fixed byte layout (see docs/licensing.md's "Payload
## format"). Pure struct encode/decode -- no cryptography, no I/O, matching
## this project's pure/glue split (ChunkSerializer/EarthChunkManager,
## StoneSize/StoneRenderer): this only knows the byte layout, not what
## makes a signature valid (see serial_verifier.gd) or where a code comes
## from (see license_store.gd).
##
## Layout: 1 byte format version, 8 bytes product bitmask (one bit per
## product -- bit 0 the base game, bits 1+ each DLC in release order, so a
## bundle purchase is just multiple bits set), 4 bytes license id (not a
## secret -- purely a name for a specific issued serial, for the optional
## revocation list), 4 bytes expiry as a unix timestamp (0 = never
## expires).

const VERSION := 1
const PAYLOAD_SIZE := 17


## Builds the raw payload bytes for a serial about to be signed (see
## docs/licensing.md's "Signing" section -- this is called by the
## never-shipped signing tool, not by the game itself).
static func encode_payload(product_mask: int, license_id: int, expiry_unix: int = 0) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(PAYLOAD_SIZE)
	bytes[0] = VERSION
	bytes.encode_u64(1, product_mask)
	bytes.encode_u32(9, license_id)
	bytes.encode_u32(13, expiry_unix)
	return bytes


## Inverse of encode_payload -- an empty Dictionary on anything that isn't
## exactly a well-formed, current-version payload (wrong length, or a
## version byte this build doesn't understand). Deliberately does NOT try
## to partially interpret a wrong-version payload -- a future format change
## might reorder or resize fields entirely, so "close enough" decoding
## would risk silently misreading a newer payload's bytes as if they were
## this version's layout.
static func decode_payload(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() != PAYLOAD_SIZE:
		return {}
	if bytes[0] != VERSION:
		return {}
	return {
		"version": bytes[0],
		"product_mask": bytes.decode_u64(1),
		"license_id": bytes.decode_u32(9),
		"expiry_unix": bytes.decode_u32(13),
	}


## Whether `product_mask` grants the product at bit index `product_bit` --
## a readable name for the bit-test callers should use instead of raw
## mask/shift arithmetic at each call site.
static func grants_product(product_mask: int, product_bit: int) -> bool:
	return (product_mask & (1 << product_bit)) != 0
