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
## expires). = 17 bytes, format version 1.
##
## OPTIONAL extension (docs/licensing.md's "Personal / GitHub-bound keys"):
## an omitted/zero github_user_id keeps the original 17-byte V1 layout
## byte-for-byte (every already-issued serial was signed against exactly
## that layout, and re-signing them isn't possible without the private
## key) -- a nonzero one appends 8 more bytes (a GitHub numeric user ID,
## not a login -- logins are renameable) under format version 2. 0 means
## "not bound to any GitHub account", the same "0 = no constraint yet"
## convention expiry_unix already uses.

const VERSION := 1
const PAYLOAD_SIZE := 17

const VERSION_WITH_GITHUB_BINDING := 2
const PAYLOAD_SIZE_WITH_GITHUB_BINDING := 25


## Builds the raw payload bytes for a serial about to be signed (see
## docs/licensing.md's "Signing" section -- this is called by the
## never-shipped signing tool, not by the game itself). `github_user_id`
## left at 0 (the default) produces the original V1 layout unchanged;
## nonzero switches to the V2 layout that also carries it.
static func encode_payload(product_mask: int, license_id: int, expiry_unix: int = 0, github_user_id: int = 0) -> PackedByteArray:
	var bytes := PackedByteArray()
	if github_user_id == 0:
		bytes.resize(PAYLOAD_SIZE)
		bytes[0] = VERSION
	else:
		bytes.resize(PAYLOAD_SIZE_WITH_GITHUB_BINDING)
		bytes[0] = VERSION_WITH_GITHUB_BINDING
	bytes.encode_u64(1, product_mask)
	bytes.encode_u32(9, license_id)
	bytes.encode_u32(13, expiry_unix)
	if github_user_id != 0:
		bytes.encode_u64(17, github_user_id)
	return bytes


## Inverse of encode_payload -- an empty Dictionary on anything that isn't
## exactly a well-formed, known-version payload (wrong length for its
## version byte, or a version byte this build doesn't understand at all).
## Deliberately does NOT try to partially interpret a wrong-version
## payload -- a future format change might reorder or resize fields
## entirely, so "close enough" decoding would risk silently misreading a
## newer payload's bytes as if they were this version's layout. Always
## includes `github_user_id` (0 for a V1 payload) so callers can read it
## uniformly without checking which version was actually decoded.
static func decode_payload(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() == PAYLOAD_SIZE and bytes[0] == VERSION:
		return {
			"version": bytes[0],
			"product_mask": bytes.decode_u64(1),
			"license_id": bytes.decode_u32(9),
			"expiry_unix": bytes.decode_u32(13),
			"github_user_id": 0,
		}
	if bytes.size() == PAYLOAD_SIZE_WITH_GITHUB_BINDING and bytes[0] == VERSION_WITH_GITHUB_BINDING:
		return {
			"version": bytes[0],
			"product_mask": bytes.decode_u64(1),
			"license_id": bytes.decode_u32(9),
			"expiry_unix": bytes.decode_u32(13),
			"github_user_id": bytes.decode_u64(17),
		}
	return {}


## Whether `product_mask` grants the product at bit index `product_bit` --
## a readable name for the bit-test callers should use instead of raw
## mask/shift arithmetic at each call site.
static func grants_product(product_mask: int, product_bit: int) -> bool:
	return (product_mask & (1 << product_bit)) != 0
