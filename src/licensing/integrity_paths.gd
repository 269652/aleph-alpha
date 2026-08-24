extends RefCounted

## Pure path derivation for SelfIntegrity (see docs/licensing.md). No file
## I/O -- SelfIntegrity's thin Node glue is the only place that actually
## checks what exists on disk, the same pure/glue split every other
## licensing module in this project already uses.


## Godot's default export layout ships a separate `<name>.pck` next to the
## executable ("Embed PCK" left unchecked); this derives that expected
## path from wherever the running executable actually is, so nothing
## needs to hardcode an install location.
static func pck_path_for_executable(executable_path: String) -> String:
	var without_extension := executable_path.get_basename()
	return without_extension + ".pck"


## The detached signature file that sits next to whatever got signed --
## deliberately a separate sidecar file rather than bundled inside the
## thing it signs, which avoids the self-referential "signing the file
## changes its own hash" problem entirely.
static func signature_path_for(target_path: String) -> String:
	return target_path + ".sig"


## Which file SelfIntegrity should actually hash: the sidecar .pck if a
## separate one was exported ("Embed PCK" off, the common case), or the
## executable itself if not (an "Embed PCK" export ships everything as
## one file, so that's the only thing left to check). `pck_exists` is
## injected rather than checked here -- see this file's own doc comment.
static func target_path(executable_path: String, pck_exists: bool) -> String:
	if pck_exists:
		return pck_path_for_executable(executable_path)
	return executable_path


## The private key AUTO-SIGN-for-local-testing checks for (see
## SelfIntegrity, docs/licensing.md's "Auto-sign for local testing") --
## sits next to whatever's being verified, same directory-adjacency
## convention signature_path_for already uses, but a FIXED filename (there
## is exactly one private key regardless of what's being signed) matching
## generate_keypair.gd's own default --out name, so running that tool with
## no --out argument while its cwd is the export folder already produces
## exactly the path this looks for.
static func private_key_path_for(target_path: String) -> String:
	return target_path.get_base_dir().path_join("private_key.pem")
