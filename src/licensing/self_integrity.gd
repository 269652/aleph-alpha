extends Node

## Enforces "the game refuses to run if its own files have been tampered
## with" (see docs/licensing.md's "Source/build integrity verification").
## Registered as an autoload (see project.godot) so this runs BEFORE the
## main scene loads, the same earliest-possible-gate pattern LicenseGate
## already uses.
##
## What this actually checks: the exported game data file (the .pck next
## to the executable, or the executable itself for an "Embed PCK" export)
## is hashed with SHA-256 and that hash's signature is checked against the
## embedded public keys -- any change to any script, scene, or resource
## packed into it changes the hash and fails the check. See docs/licensing
## .md for what this does and does NOT defend against (it is not a
## general anti-cheat -- read that section before relying on this for more
## than "was the shipped package modified at rest").
##
## Split deliberately: evaluate() is the pure decision (fully unit-tested,
## no file I/O, no quit()), _ready()/require_verified() are the thin glue
## that actually reads real files and ends the process on failure -- the
## same pure/glue split LicenseGate uses for exactly the same reasons.
##
## Removing this file entirely fails the game closed, not open: any script
## that still references the SelfIntegrity autoload by name (see world.gd's
## own redundant require_verified() call) fails to compile the moment the
## referenced script is missing.

const SignatureRing = preload("res://src/licensing/signature_ring.gd")
const IntegrityPaths = preload("res://src/licensing/integrity_paths.gd")
const EmbeddedPublicKeys = preload("res://src/licensing/embedded_public_keys.gd")
const KeyFingerprint = preload("res://src/licensing/key_fingerprint.gd")

## Set once verification runs. Other boot-critical code can read this
## after the fact, but should prefer calling require_verified() itself
## (see LicenseGate's identical caveat on its own is_licensed flag) rather
## than trusting a cached flag alone.
var is_verified := false

var _ring: SignatureRing


## `ring`: defaults to the real production ring (reading EmbeddedPublicKeys'
## real embedded keys) -- Godot itself constructs autoloads with a bare,
## argument-less `new()`, so this default is what actually runs in the
## shipped game. Tests inject a ring built from a real test keypair
## instead, the same "inject the real dependency, default to the
## production one" shape LicenseGate already uses.
func _init(ring: SignatureRing = null) -> void:
	if ring != null:
		_ring = ring
		return
	# Key-swap resistance (see KeyFingerprint, docs/licensing.md): same
	# check LicenseGate's own production path runs, applied here too so a
	# swapped key can't slip a forged build-signature through either.
	var pems: Array[String] = []
	if KeyFingerprint.matches_expected(EmbeddedPublicKeys.PUBLIC_KEY_PEMS):
		pems = EmbeddedPublicKeys.PUBLIC_KEY_PEMS
	_ring = SignatureRing.new(pems)


func _ready() -> void:
	# There is no signed export artifact to check against while running
	# from the editor's Play button -- raw project files, not an exported
	# .pck, so this check is structurally inapplicable there, not merely
	# skipped for convenience (contrast LicenseGate's editor bypass, which
	# IS just convenience). Never present in an exported build.
	if OS.has_feature("editor"):
		is_verified = true
		return
	require_verified()


## The real enforcement call: read the real target file and its signature
## off disk, verify, and end the process if it doesn't check out.
## Deliberately re-reads and re-verifies from scratch every time rather
## than trusting `is_verified` -- so a second, independent call site (see
## world.gd) genuinely re-checks rather than trusting a flag only THIS
## function's own _ready() call set.
##
## `file_bytes_override`/`signature_override`: normally left empty (reads
## the real files); tests pass explicit bytes instead of depending on a
## real exported .pck existing on disk, the same "inject what varies"
## shape LicenseGate's code_override already uses. Both empty means "not
## overridden" -- an override that is genuinely empty bytes would fail
## evaluate() anyway, so collapsing the two cases costs nothing.
func require_verified(file_bytes_override: PackedByteArray = PackedByteArray(), signature_override: PackedByteArray = PackedByteArray()) -> void:
	if not file_bytes_override.is_empty() or not signature_override.is_empty():
		_finish_verification(file_bytes_override, signature_override)
		return
	require_verified_at(_target_path())


## The same real enforcement as require_verified(), against an EXPLICIT
## target path rather than the real running executable's own -- lets
## tests exercise the full real file-I/O flow (including auto-sign, see
## _auto_sign_if_private_key_present) against a controlled scratch
## location instead of depending on a real exported .pck existing on disk.
func require_verified_at(target: String) -> void:
	var file_bytes := FileAccess.get_file_as_bytes(target)
	_auto_sign_if_private_key_present(target, file_bytes)
	var signature := _signature_bytes_at(IntegrityPaths.signature_path_for(target))
	_finish_verification(file_bytes, signature)


func _finish_verification(file_bytes: PackedByteArray, signature: PackedByteArray) -> void:
	var result := evaluate(file_bytes, signature)
	is_verified = result.ok
	if not result.ok:
		push_error("Integrity check failed: %s" % result.reason)
		printerr(
			"This copy's game files could not be verified and may have " +
			"been modified. Reinstall from the original source."
		)
		if get_tree() != null:
			get_tree().quit(1)


## Local-testing convenience (see docs/licensing.md's "Auto-sign for local
## testing" -- NEVER present in a real distributed copy, and NEVER shipped
## itself: the private key file only matters if it happens to exist on
## whoever's disk is running this). If a private key sits next to the
## target being verified (IntegrityPaths.private_key_path_for), sign the
## target fresh and write the result out before verifying -- so iterating
## on a local export doesn't need a separate manual tools/sign_build.gd
## run after every rebuild. A real customer's copy never has this file,
## so this path is simply never taken for anyone but the developer
## testing locally. Overwrites any stale signature already there, since
## the whole point is "the freshest build always verifies."
func _auto_sign_if_private_key_present(target: String, file_bytes: PackedByteArray) -> void:
	if file_bytes.is_empty():
		return
	var key_path := IntegrityPaths.private_key_path_for(target)
	if not FileAccess.file_exists(key_path):
		return
	var private_key := CryptoKey.new()
	if private_key.load(key_path, false) != OK:
		return
	var signature := SignatureRing.sign_hash(SignatureRing.sha256(file_bytes), private_key)
	var sig_file := FileAccess.open(IntegrityPaths.signature_path_for(target), FileAccess.WRITE)
	if sig_file != null:
		sig_file.store_buffer(signature)


## The pure decision: given the bytes that were read (possibly empty) and
## whatever signature was found (possibly empty), does this game session
## get to run? No file I/O, no quit() -- fully testable.
## Returns {"ok": bool, "reason": String}.
func evaluate(file_bytes: PackedByteArray, signature: PackedByteArray) -> Dictionary:
	if file_bytes.is_empty():
		return {"ok": false, "reason": "target file not found or empty"}
	if signature.is_empty():
		return {"ok": false, "reason": "no signature file found"}
	if not _ring.verify_hash(SignatureRing.sha256(file_bytes), signature):
		return {"ok": false, "reason": "signature does not match -- files may have been modified"}
	return {"ok": true, "reason": ""}


func _target_path() -> String:
	var executable_path := OS.get_executable_path()
	var pck_path := IntegrityPaths.pck_path_for_executable(executable_path)
	return IntegrityPaths.target_path(executable_path, FileAccess.file_exists(pck_path))


func _signature_bytes_at(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)
