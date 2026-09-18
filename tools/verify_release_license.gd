extends SceneTree

## Answers one question for tools/release/build_release.ps1: may THIS
## license.txt be bundled into the release package being built right now?
##
## Asked for directly: *"make it so that the license.txt is included in the
## release if it's still valid at the time of build"*. See
## docs/licensing.md's "Bundling a license with a release".
##
## Developer/ops tooling, not shipped logic -- the same status
## tools/sign_build.gd and tools/generate_keypair.gd carry. Deliberately
## THIN: every decision it reports comes from ReleaseLicense, which is
## real TDD-covered game code (tests/unit/test_release_license.gd), and
## every judgement of validity comes from SerialVerifier, which the shipped
## game itself uses. This file only does the I/O and the exit code.
##
## It builds its key ring exactly the way LicenseGate does, INCLUDING the
## KeyFingerprint check that falls back to an empty ring on a mismatch. A
## build that used a laxer ring than the shipped game could bundle a serial
## the game itself would then reject -- a release that fails on the
## customer's machine and nowhere else.
##
## Usage:
##   "<godot-path>" --headless --path "<repo-path>" \
##     -s tools/verify_release_license.gd -- --file "C:\path\to\license.txt"
##
## Exit code 0: bundle it. 1: do not (the printed line says why). The
## reason is named in full because a release console is a developer
## surface -- docs/licensing.md's "generic failure message" rule is about
## the shipped player-facing UI, not this.

const SerialVerifier = preload("res://src/licensing/serial_verifier.gd")
const LicenseStore = preload("res://src/licensing/license_store.gd")
const EmbeddedPublicKeys = preload("res://src/licensing/embedded_public_keys.gd")
const KeyFingerprint = preload("res://src/licensing/key_fingerprint.gd")
const ReleaseLicense = preload("res://src/licensing/release_license.gd")


func _initialize():
	var args := _parsed_args(OS.get_cmdline_user_args())
	if not args.has("file"):
		printerr("Usage: verify_release_license.gd -- --file <path-to-license.txt>")
		quit(2)
		return

	var path: String = args.file
	if not FileAccess.file_exists(path):
		printerr("License file not found: ", path)
		quit(2)
		return

	var code := LicenseStore.read_code([path] as Array[String])
	var decision := ReleaseLicense.bundle_decision(
		code, _verifier().verify_code(code), int(Time.get_unix_time_from_system())
	)
	print(ReleaseLicense.report_line(decision))
	quit(0 if decision.bundle else 1)


## The SAME ring LicenseGate builds -- see this file's own header for why
## that matters more than it looks.
func _verifier() -> SerialVerifier:
	var pems: Array[String] = []
	if KeyFingerprint.matches_expected(EmbeddedPublicKeys.PUBLIC_KEY_PEMS):
		pems = EmbeddedPublicKeys.PUBLIC_KEY_PEMS
	else:
		printerr(
			"embedded_public_keys.gd does not match the fingerprint KeyFingerprint expects"
			+ " -- verifying against an EMPTY ring, exactly as the shipped game would."
		)
	return SerialVerifier.new(pems)


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
