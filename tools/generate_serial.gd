extends SceneTree

## NEVER SHIP THIS FILE (see docs/licensing.md). Run yourself, with your
## real private key (see tools/generate_keypair.gd), to mint a real serial
## for a sale. Not part of this project's TDD-covered game code --
## developer tooling, not shipped logic, same status as
## generate_keypair.gd. Reuses the exact same serial_codec.gd/
## serial_base32.gd the shipped game's verifier reads, so a code minted
## here is guaranteed to be in the format the game actually checks against
## -- no second, parallel format to keep in sync by hand.
##
## Usage:
##   "<godot-path>" --headless --path "<repo-path>" -s tools/generate_serial.gd -- \
##     --key my_private_key.pem --products 0,1 --id 1001 [--expiry 2026-12-31]
##
## --key: path to the FULL private key file (see generate_keypair.gd).
## --products: comma-separated bit indices to grant (0 = base game, 1+ =
##   each DLC in release order -- see serial_codec.gd's own doc comment
##   for the exact bit layout).
## --id: an arbitrary integer identifying THIS issued serial -- not a
##   secret, purely a name for later revocation (see docs/licensing.md).
##   Pick your own convention (an order number, an incrementing counter);
##   this tool doesn't track or dedupe it for you.
## --expiry: optional ISO date (YYYY-MM-DD); omitted means never expires.

const SerialCodec = preload("res://src/licensing/serial_codec.gd")
const SerialBase32 = preload("res://src/licensing/serial_base32.gd")

## Readable line width for the printed code (see docs/licensing.md: a
## paste-able block, not a typed-character-by-character serial).
const LINE_WIDTH := 40


func _initialize():
	var args := _parsed_args(OS.get_cmdline_user_args())
	if not (args.has("key") and args.has("products") and args.has("id")):
		printerr(
			"Usage: generate_serial.gd -- --key <path> --products <bit,bit,...> " +
			"--id <int> [--expiry YYYY-MM-DD]"
		)
		quit(1)
		return

	var private_key := _load_private_key(args.key)
	if private_key == null:
		quit(1)
		return

	var product_mask := _product_mask_from(args.products)
	var license_id := int(args.id)
	var expiry_unix := _expiry_unix_from(args.get("expiry", ""))

	var payload := SerialCodec.encode_payload(product_mask, license_id, expiry_unix)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload)
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, context.finish(), private_key)
	var code := SerialBase32.encode(payload + signature)

	print(
		"product_mask=%d license_id=%d expiry_unix=%d" % [product_mask, license_id, expiry_unix]
	)
	print("")
	print(_formatted(code))
	quit()


func _load_private_key(path: String) -> CryptoKey:
	if not FileAccess.file_exists(path):
		printerr("Private key file not found: ", path)
		return null
	var key := CryptoKey.new()
	if key.load(path, false) != OK:
		printerr("Failed to load private key from ", path)
		return null
	if key.is_public_only():
		printerr("That file only holds a PUBLIC key -- this tool needs the full private key.")
		return null
	return key


func _product_mask_from(products_arg: String) -> int:
	var mask := 0
	for bit_str in products_arg.split(","):
		mask |= 1 << int(bit_str.strip_edges())
	return mask


func _expiry_unix_from(expiry_arg: String) -> int:
	if expiry_arg.is_empty():
		return 0
	var parts := expiry_arg.split("-")
	if parts.size() != 3:
		printerr("--expiry must be YYYY-MM-DD, got: ", expiry_arg)
		return 0
	return Time.get_unix_time_from_datetime_dict({
		"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]),
		"hour": 0, "minute": 0, "second": 0,
	})


func _parsed_args(raw: Array) -> Dictionary:
	var result := {}
	var i := 0
	while i < raw.size():
		var token: String = raw[i]
		if token.begins_with("--") and i + 1 < raw.size():
			result[token.substr(2)] = raw[i + 1]
			i += 2
		else:
			i += 1
	return result


func _formatted(code: String) -> String:
	var lines: Array[String] = []
	var i := 0
	while i < code.length():
		lines.append(code.substr(i, LINE_WIDTH))
		i += LINE_WIDTH
	return "\n".join(lines)
