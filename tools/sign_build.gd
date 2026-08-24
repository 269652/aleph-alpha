extends SceneTree

## NEVER SHIP THIS FILE (see docs/licensing.md). Run yourself, with your
## real private key (see tools/generate_keypair.gd), AFTER exporting the
## game, to produce the signature file SelfIntegrity checks at boot. Same
## "developer tooling, not shipped logic" status as generate_serial.gd --
## not part of this project's TDD-covered game code.
##
## Sign the FINAL exported artifact, not the raw src/*.gd files in this
## repo -- export compiles/packs scripts into the .pck, so a hash taken
## before export will never match what SelfIntegrity reads from the
## shipped .pck at runtime. Re-run this after every export, including
## patches -- an old signature will correctly fail verification against a
## newer build.
##
## Usage:
##   "<godot-path>" --headless --path "<repo-path>" -s tools/sign_build.gd -- \
##     --key my_private_key.pem --file "C:\path\to\export\AlephAlfa.pck" [--out <path>]
##
## --key: path to the FULL private key file (see generate_keypair.gd).
## --file: the exported artifact to sign -- the .pck next to the exported
##   executable ("Embed PCK" left unchecked, the common case), or the
##   executable itself if that option was checked (see
##   src/licensing/integrity_paths.gd).
## --out: where to write the signature. Defaults to `--file` + ".sig",
##   which is exactly where SelfIntegrity looks for it -- only override
##   this for a dry run.

const SignatureRing = preload("res://src/licensing/signature_ring.gd")
const IntegrityPaths = preload("res://src/licensing/integrity_paths.gd")


func _initialize():
	var args := _parsed_args(OS.get_cmdline_user_args())
	if not (args.has("key") and args.has("file")):
		printerr("Usage: sign_build.gd -- --key <path> --file <path-to-export> [--out <path>]")
		quit(1)
		return

	var private_key := _load_private_key(args.key)
	if private_key == null:
		quit(1)
		return

	if not FileAccess.file_exists(args.file):
		printerr("File to sign not found: ", args.file)
		quit(1)
		return

	var file_bytes := FileAccess.get_file_as_bytes(args.file)
	if file_bytes.is_empty():
		printerr("File to sign is empty or unreadable: ", args.file)
		quit(1)
		return

	var file_hash := SignatureRing.sha256(file_bytes)
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, file_hash, private_key)

	var out_path: String = args.get("out", IntegrityPaths.signature_path_for(args.file))
	var out_file := FileAccess.open(out_path, FileAccess.WRITE)
	if out_file == null:
		printerr("Failed to open output path for writing: ", out_path)
		quit(1)
		return
	out_file.store_buffer(signature)
	out_file.close()

	print("Signed ", args.file, " (", file_bytes.size(), " bytes)")
	print("Signature written to: ", out_path)
	print("Ship both files together -- the .sig must sit next to the file it signs.")
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
