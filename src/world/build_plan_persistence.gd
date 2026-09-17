extends RefCounted

## Plans outliving a reload -- docs/concept/planner_mode.md's pillar 3: a
## wireframe is world state, not screen state, because walking back to one
## later is the entire point of planning ahead.
##
## Mirrors WorldClockPersistence's own shape exactly (SAVE_PATH, has_save,
## save, load, wipe, and an empty default on a missing file -- the contract
## PlayerSave.load_data and EventStorePersistence.load_store already
## follow) rather than inventing a second persistence idiom.
##
## ONE file for every plan rather than the per-chunk directories chunk
## modifications use (EarthChunkManager.MODIFICATIONS_DIR and friends): a
## settlement's worth of plans is tens of records, not the thousands per
## chunk that made per-chunk files worth their complexity there, and plans
## are read whole (the wireframe layer draws all of them) rather than a
## chunk at a time.

const BuildPlanLedger = preload("res://src/world/build_plan_ledger.gd")
const BuildPlan = preload("res://src/world/build_plan.gd")

const SAVE_PATH := "user://build_plans.bin"


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


## Writes every plan, including none: saving an empty ledger is how
## cancelling the last wireframe persists, so it must overwrite rather than
## leave the previous file standing.
##
## JSON rather than `store_var`, unlike WorldClockPersistence's single
## float: a malformed `get_var()` raises an engine error that cannot be
## caught, so a file truncated by a crash would take the boot down with it
## instead of degrading to "no plans". `JSON.parse_string` returns null on
## garbage, which is checkable. Being readable on disk is a real second
## benefit for a file a player might want to inspect.
func save(ledger, path: String = SAVE_PATH) -> void:
	var rows: Array = []
	for plan in ledger.plans():
		rows.append({
			"chunk_x": plan.chunk_coord.x, "chunk_y": plan.chunk_coord.y,
			"origin_x": plan.origin.x, "origin_y": plan.origin.y,
			"blueprint_id": plan.blueprint_id,
			"planned_at": plan.planned_at,
		})
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(rows))
	file.close()


## A real, working ledger -- not a bag of records. Rebuilt by replaying the
## rows into a fresh one so its overlap refusal knows about everything it
## loaded; a ledger that had forgotten would silently allow a second plan
## on top of an existing one after every reload.
##
## Anything unreadable -- no file, a file from an older build, one
## truncated by a crash mid-write -- gives an EMPTY ledger rather than a
## broken game, the "narrows, never crashes" contract this codebase keeps
## everywhere it reads from disk.
func load_ledger(path: String = SAVE_PATH):
	var ledger := BuildPlanLedger.new()
	if not FileAccess.file_exists(path):
		return ledger
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ledger
	var text := file.get_as_text()
	file.close()
	# JSON.new().parse rather than JSON.parse_string: the latter PUSHES an
	# engine error on malformed input, which is exactly the noise a
	# "degrade quietly to no plans" path must not make (and which GUT
	# rightly fails a test for). This returns a code instead.
	var json := JSON.new()
	if json.parse(text) != OK:
		return ledger
	var rows = json.data
	if not (rows is Array):
		return ledger
	for row in rows:
		if not (row is Dictionary):
			continue
		if not (row.has("chunk_x") and row.has("origin_x") and row.has("blueprint_id")):
			continue
		ledger.plan(
			Vector2i(int(row["chunk_x"]), int(row["chunk_y"])),
			Vector2i(int(row["origin_x"]), int(row["origin_y"])),
			String(row["blueprint_id"]), float(row.get("planned_at", 0.0)),
			# Ground that was buildable when the plan was laid is taken on
			# trust here: re-checking would need the chunk loaded, and a
			# river that moved since should drop the wireframe at the moment
			# somebody tries to raise it, not silently at load with no
			# explanation.
			func(_cell: Vector2i) -> bool: return true
		)
	return ledger


func wipe(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
