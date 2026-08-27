extends GutTest

## Pure path derivation for SelfIntegrity (see docs/licensing.md's "Source/
## build integrity verification"). No file I/O here -- whether the pck
## sidecar actually exists is an injected bool, same "inject what varies"
## shape this project already uses (SerialVerifier's current_unix_time,
## LicenseGate's code_override) to keep decision logic testable without
## real disk state.

const IntegrityPaths = preload("res://src/licensing/integrity_paths.gd")


func test_pck_path_swaps_the_exe_extension_for_pck():
	var pck := IntegrityPaths.pck_path_for_executable("C:/Games/AlephAlfa/AlephAlfa.exe")
	assert_eq(pck, "C:/Games/AlephAlfa/AlephAlfa.pck")


func test_pck_path_handles_an_extensionless_executable():
	# Linux exports commonly ship with no extension at all.
	var pck := IntegrityPaths.pck_path_for_executable("/opt/alephalfa/AlephAlfa")
	assert_eq(pck, "/opt/alephalfa/AlephAlfa.pck")


func test_signature_path_appends_dot_sig():
	var sig := IntegrityPaths.signature_path_for("C:/Games/AlephAlfa/AlephAlfa.pck")
	assert_eq(sig, "C:/Games/AlephAlfa/AlephAlfa.pck.sig")


func test_target_path_prefers_the_pck_when_it_exists():
	var target := IntegrityPaths.target_path("C:/Games/AlephAlfa/AlephAlfa.exe", true)
	assert_eq(target, "C:/Games/AlephAlfa/AlephAlfa.pck")


func test_target_path_falls_back_to_the_executable_when_no_pck_exists():
	# Covers "Embed PCK" exports, where everything ships as one .exe.
	var target := IntegrityPaths.target_path("C:/Games/AlephAlfa/AlephAlfa.exe", false)
	assert_eq(target, "C:/Games/AlephAlfa/AlephAlfa.exe")


## The auto-sign-for-local-testing convenience (see SelfIntegrity, docs/
## licensing.md) looks for a private key sitting next to whatever's being
## verified -- same directory-adjacency convention signature_path_for
## already uses, but a FIXED filename (there is exactly one private key
## regardless of what's being signed), matching generate_keypair.gd's own
## default --out name so running that tool from inside the target's own
## folder already produces exactly the path this looks for.
func test_private_key_path_sits_next_to_the_target_with_a_fixed_name():
	var key_path := IntegrityPaths.private_key_path_for("C:/Games/AlephAlfa/AlephAlfa.pck")
	assert_eq(key_path, "C:/Games/AlephAlfa/private_key.pem")


func test_private_key_path_ignores_the_targets_own_filename():
	var a := IntegrityPaths.private_key_path_for("C:/Games/AlephAlfa/AlephAlfa.pck")
	var b := IntegrityPaths.private_key_path_for("C:/Games/AlephAlfa/AlephAlfa.exe")
	assert_eq(a, b)
