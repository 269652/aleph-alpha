extends Node

## Enforces "the game refuses to run without a valid serial" (see
## docs/licensing.md). Registered as an autoload (see project.godot) so
## this runs BEFORE the main scene loads -- the earliest possible gate,
## same "*res://..." autoload convention world_item_bus.gd/
## console_focus_bus.gd already use.
##
## Split deliberately: evaluate() is the pure decision (fully unit-tested,
## no file I/O, no quit()), _ready()/require_licensed() are the thin glue
## that actually reads a real file and ends the process on failure -- kept
## as small as possible so there is as little untested surface as this can
## have, the same pure/glue split every other system in this project uses.
##
## Removing this file entirely fails the game closed, not open: any script
## that still references the LicenseGate autoload by name fails to compile
## the moment the referenced script is missing (see world.gd's own
## redundant require_licensed() call) -- Godot cannot silently skip a
## missing autoload's script and keep running the scripts that depend on
## it.

const SerialVerifier = preload("res://src/licensing/serial_verifier.gd")
const LicenseStore = preload("res://src/licensing/license_store.gd")
const EmbeddedPublicKeys = preload("res://src/licensing/embedded_public_keys.gd")
const KeyFingerprint = preload("res://src/licensing/key_fingerprint.gd")

## Set once verification runs. Other boot-critical code can read this
## after the fact, but should prefer calling require_licensed() itself
## (see that function's own doc comment) rather than trusting this cached
## flag alone -- a flag is a far easier single point for a save/memory
## edit to flip than genuinely defeating the RSA check.
var is_licensed := false
var product_mask := 0

var _verifier: SerialVerifier


## `verifier`: defaults to the real production verifier (reading
## EmbeddedPublicKeys' real embedded keys) -- Godot itself constructs
## autoloads with a bare, argument-less `new()`, so this default is what
## actually runs in the shipped game. Tests inject a verifier built from a
## real test keypair instead (see test_license_gate.gd), the same
## "inject the real dependency, default to the production one" shape
## TerrainRelief/StoneRenderer already use elsewhere in this project.
func _init(verifier: SerialVerifier = null) -> void:
	if verifier != null:
		_verifier = verifier
		return
	# Key-swap resistance (see KeyFingerprint, docs/licensing.md): only the
	# PRODUCTION default path checks this -- an injected test verifier
	# never touches EmbeddedPublicKeys at all, so it has nothing to swap.
	# A mismatch here means embedded_public_keys.gd was edited to a
	# different key than KeyFingerprint expects -- fail closed with an
	# empty ring (rejects every code) rather than trust an unverified key.
	var pems: Array[String] = []
	if KeyFingerprint.matches_expected(EmbeddedPublicKeys.PUBLIC_KEY_PEMS):
		pems = EmbeddedPublicKeys.PUBLIC_KEY_PEMS
	_verifier = SerialVerifier.new(pems)


func _ready() -> void:
	# Godot's own "editor" feature tag exists ONLY when running via the
	# editor's Play button -- it is never present in an exported/shipped
	# build, so this branch creates no bypass in what actually ships; it
	# only lets normal in-editor development/playtesting proceed without
	# needing a real serial every time. Remove this if you'd rather the
	# check apply in-editor too.
	if OS.has_feature("editor"):
		is_licensed = true
		return
	require_licensed()


## The real enforcement call: read the license file, verify it, and end
## the process if it isn't valid. Deliberately re-reads and re-verifies
## from scratch every time rather than trusting `is_licensed` -- so a
## second, independent call site (see world.gd) genuinely re-checks rather
## than trusting a flag that only THIS function's own _ready() call set,
## which would make patching just this one _ready() enough to bypass
## every other call site too.
##
## `code_override`: normally left empty (reads the real license file);
## tests pass an explicit code instead of depending on real file I/O, the
## same "inject what varies" shape SerialVerifier.verify_code's
## current_unix_time parameter already uses.
func require_licensed(code_override: String = "") -> void:
	var code := code_override if not code_override.is_empty() else LicenseStore.read_code(LicenseStore.default_candidate_paths())
	var result := evaluate(code)
	is_licensed = result.licensed
	product_mask = result.product_mask
	if not result.licensed:
		push_error("License check failed: %s" % result.reason)
		printerr(
			"This copy could not be verified. Place a valid license.txt " +
			"next to the game and restart."
		)
		if get_tree() != null:
			get_tree().quit(1)


## The pure decision: given whatever code was read (possibly ""), does
## this game session get to run? No file I/O, no quit() -- fully testable.
## Returns {"licensed": bool, "product_mask": int, "reason": String}.
func evaluate(code: String) -> Dictionary:
	if code.is_empty():
		return {"licensed": false, "product_mask": 0, "reason": "no license code found"}
	var result := _verifier.verify_code(code)
	if not result.valid:
		return {"licensed": false, "product_mask": 0, "reason": result.reason}
	return {"licensed": true, "product_mask": result.product_mask, "reason": ""}
