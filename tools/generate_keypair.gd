extends SceneTree

## NEVER SHIP THIS FILE (see docs/licensing.md's "Operational security" and
## "Proposed file layout"). Run this ONCE, yourself, on a machine you
## control, to generate your real RSA-2048 keypair for signing serials.
## Not part of this project's TDD-covered game code -- it's a manual,
## you-run-it-yourself CLI tool with no shipped behavior to unit test, the
## same "developer tooling, not game logic" status the design doc already
## gives it.
##
## Usage:
##   "<godot-path>" --headless --path "<repo-path>" -s tools/generate_keypair.gd -- --out my_private_key.pem
##
## Prints the PUBLIC-only PEM to paste into
## src/licensing/embedded_public_keys.gd's PUBLIC_KEY_PEMS list. Saves the
## FULL keypair (private + public) to the path you gave via --out --
## move that file somewhere that never touches this git repository (a
## password manager attachment, an encrypted offline drive) immediately
## after. Losing it means never being able to issue a new valid serial for
## this product again unless you rotate to a fresh keypair (see
## docs/licensing.md's "Key rotation" -- old serials keep working once the
## new public key ships alongside the old one).

func _initialize():
	var args := OS.get_cmdline_user_args()
	var out_path := "private_key.pem"
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out_path = args[i + 1]

	if FileAccess.file_exists(out_path):
		printerr("Refusing to overwrite an existing file: ", out_path)
		printerr("(if you really mean to generate a NEW keypair, move or delete it first --")
		printerr(" see docs/licensing.md's Key rotation section for how to do that safely)")
		quit(1)
		return

	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var save_error := key.save(out_path, false)  # false = save the FULL key, private half included
	if save_error != OK:
		printerr("Failed to save keypair to ", out_path, " (error ", save_error, ")")
		quit(1)
		return

	print("Full keypair (private + public) saved to: ", out_path)
	print("Move that file somewhere that NEVER touches this git repository --")
	print("a password manager attachment or an encrypted offline drive.")
	print("")
	print("Paste the block below into src/licensing/embedded_public_keys.gd's")
	print("PUBLIC_KEY_PEMS list (as one string, keep the \\n line breaks):")
	print("")
	print(key.save_to_string(true))
	quit()
