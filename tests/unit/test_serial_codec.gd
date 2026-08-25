extends GutTest

const SerialCodec = preload("res://src/licensing/serial_codec.gd")


func test_encoded_payload_has_the_documented_fixed_length():
	var bytes := SerialCodec.encode_payload(1, 42, 0)
	assert_eq(bytes.size(), SerialCodec.PAYLOAD_SIZE)


func test_round_trips_product_mask_license_id_and_expiry():
	var bytes := SerialCodec.encode_payload(0b1011, 123456, 1893456000)
	var decoded := SerialCodec.decode_payload(bytes)
	assert_eq(decoded.product_mask, 0b1011)
	assert_eq(decoded.license_id, 123456)
	assert_eq(decoded.expiry_unix, 1893456000)


func test_zero_expiry_means_never_expires():
	var bytes := SerialCodec.encode_payload(1, 1, 0)
	var decoded := SerialCodec.decode_payload(bytes)
	assert_eq(decoded.expiry_unix, 0)


func test_encodes_the_current_format_version():
	var bytes := SerialCodec.encode_payload(1, 1, 0)
	assert_eq(bytes[0], SerialCodec.VERSION)


func test_decode_reports_the_version_it_read():
	var bytes := SerialCodec.encode_payload(1, 1, 0)
	assert_eq(SerialCodec.decode_payload(bytes).version, SerialCodec.VERSION)


func test_decode_rejects_the_wrong_byte_length():
	var too_short := PackedByteArray([1, 2, 3])
	assert_true(SerialCodec.decode_payload(too_short).is_empty())


func test_decode_rejects_an_unknown_format_version():
	var bytes := SerialCodec.encode_payload(1, 1, 0)
	bytes[0] = SerialCodec.VERSION + 1
	assert_true(SerialCodec.decode_payload(bytes).is_empty())


## A 64-bit-wide bitmask (one bit per product: bit 0 = base game, bits 1+
## = each DLC) has to actually preserve the high bits, not just the low
## ones a smaller int type would silently truncate.
func test_product_mask_preserves_high_bits_for_many_products():
	var high_bit_mask := 1 << 40
	var bytes := SerialCodec.encode_payload(high_bit_mask, 1, 0)
	assert_eq(SerialCodec.decode_payload(bytes).product_mask, high_bit_mask)


# -- GitHub-bound personal keys (see docs/licensing.md's "Personal /
# GitHub-bound keys") -- an OPTIONAL extra field, backward compatible
# with every already-issued V1 serial (no github_user_id at all). ------

## The default (no github_user_id passed) must stay byte-identical to the
## original V1 format -- every already-issued serial (the public trial
## key, the owner key) was signed against exactly this layout, and
## re-signing them isn't possible without the private key.
func test_omitting_github_user_id_produces_the_original_v1_format():
	var bytes := SerialCodec.encode_payload(1, 42, 0)
	assert_eq(bytes.size(), SerialCodec.PAYLOAD_SIZE)
	assert_eq(bytes[0], SerialCodec.VERSION)


func test_decode_of_a_v1_payload_reports_github_user_id_zero():
	var bytes := SerialCodec.encode_payload(1, 42, 0)
	assert_eq(SerialCodec.decode_payload(bytes).github_user_id, 0)


func test_a_nonzero_github_user_id_produces_a_longer_v2_payload():
	var bytes := SerialCodec.encode_payload(1, 42, 0, 123456)
	assert_eq(bytes.size(), SerialCodec.PAYLOAD_SIZE_WITH_GITHUB_BINDING)
	assert_eq(bytes[0], SerialCodec.VERSION_WITH_GITHUB_BINDING)


func test_round_trips_a_github_user_id():
	var bytes := SerialCodec.encode_payload(1, 42, 0, 123456)
	var decoded := SerialCodec.decode_payload(bytes)
	assert_eq(decoded.github_user_id, 123456)
	# The rest of the fields still round-trip correctly alongside it.
	assert_eq(decoded.product_mask, 1)
	assert_eq(decoded.license_id, 42)


## GitHub numeric user IDs are nowhere near 32 bits today, but there's no
## reason to bake in a truncation bug -- same "don't silently truncate a
## wide field" property product_mask's own high-bit test above checks.
func test_github_user_id_preserves_high_bits():
	var high_bit_id := 1 << 40
	var bytes := SerialCodec.encode_payload(1, 1, 0, high_bit_id)
	assert_eq(SerialCodec.decode_payload(bytes).github_user_id, high_bit_id)


func test_decode_rejects_a_v2_length_payload_with_a_v1_version_byte():
	var bytes := SerialCodec.encode_payload(1, 42, 0, 123456)
	bytes[0] = SerialCodec.VERSION
	assert_true(SerialCodec.decode_payload(bytes).is_empty())


func test_decode_rejects_a_v1_length_payload_with_the_v2_version_byte():
	var bytes := SerialCodec.encode_payload(1, 42, 0)
	bytes[0] = SerialCodec.VERSION_WITH_GITHUB_BINDING
	assert_true(SerialCodec.decode_payload(bytes).is_empty())


# -- product mask helpers: readable bit-per-product checks, not raw math ------

func test_grants_product_reads_a_set_bit():
	assert_true(SerialCodec.grants_product(0b0101, 0))
	assert_true(SerialCodec.grants_product(0b0101, 2))


func test_grants_product_reads_an_unset_bit():
	assert_false(SerialCodec.grants_product(0b0101, 1))
	assert_false(SerialCodec.grants_product(0b0101, 3))
