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


# -- product mask helpers: readable bit-per-product checks, not raw math ------

func test_grants_product_reads_a_set_bit():
	assert_true(SerialCodec.grants_product(0b0101, 0))
	assert_true(SerialCodec.grants_product(0b0101, 2))


func test_grants_product_reads_an_unset_bit():
	assert_false(SerialCodec.grants_product(0b0101, 1))
	assert_false(SerialCodec.grants_product(0b0101, 3))
