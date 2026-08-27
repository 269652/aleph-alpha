extends GutTest

## Everything New Game destroys -- and therefore everything it must copy
## aside first (see World._backup_persisted_world, WorldReset.backup_file/
## backup_directory and docs/concept/persistence.md's "New Game means new...
## and recoverable").
##
## A backup list is only worth anything if it is COMPLETE: a store missing
## from it is a store that is still destroyed with no undo, and nothing about
## the running game would look wrong. So this file pins the lists against the
## persistence classes' own SAVE_PATH constants, and then against the actual
## source text of `_wipe_persisted_world` -- if a future session adds a
## wipe_* call and forgets the backup, the count stops matching and this
## fails.
##
## Kept as its own tiny file (it only preloads scripts, builds no nodes) so
## it runs in about a second, rather than living in
## test_earth_chunk_manager.gd, which takes ten-plus minutes.

const World = preload("res://scenes/world.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const PlayerSave = preload("res://src/gameplay/player_save.gd")
const EventStorePersistence = preload("res://src/emergence/event_store_persistence.gd")
const MemoryStorePersistence = preload("res://src/emergence/memory_store_persistence.gd")
const HouseholdStorePersistence = preload("res://src/emergence/household_store_persistence.gd")
const ContractStorePersistence = preload("res://src/emergence/contract_store_persistence.gd")
const MarketStorePersistence = preload("res://src/emergence/market_store_persistence.gd")
const InstitutionStorePersistence = preload("res://src/emergence/institution_store_persistence.gd")
const WorldBossStorePersistence = preload("res://src/emergence/world_boss_store_persistence.gd")
const WorldClockPersistence = preload("res://src/world/world_clock_persistence.gd")


## The body of World._wipe_persisted_world, read straight from source -- the
## authority on what New Game actually destroys.
func _wipe_body() -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func _wipe_persisted_world()")
	assert_gt(start, -1, "World._wipe_persisted_world should still exist")
	var end := source.find("\nfunc ", start + 1)
	if end == -1:
		end = source.length()
	return source.substr(start, end - start)


func test_the_three_chunk_persistence_directories_are_backed_up():
	var dirs := World.backed_up_directories()
	assert_has(dirs, EarthChunkManager.MODIFICATIONS_DIR)
	assert_has(dirs, EarthChunkManager.PLANTED_TREES_DIR)
	assert_has(dirs, EarthChunkManager.FISH_POPULATION_DIR)


## Every single-file store the wipe removes, named by the persistence class
## that owns the path rather than by a restated string literal -- so moving a
## store's file moves its backup with it.
func test_every_single_file_store_the_wipe_removes_is_backed_up():
	var files := World.backed_up_files()
	for path in [
		EventStorePersistence.SAVE_PATH,
		MemoryStorePersistence.SAVE_PATH,
		HouseholdStorePersistence.SAVE_PATH,
		ContractStorePersistence.SAVE_PATH,
		MarketStorePersistence.SAVE_PATH,
		InstitutionStorePersistence.SAVE_PATH,
		WorldBossStorePersistence.SAVE_PATH,
		WorldClockPersistence.SAVE_PATH,
		PlayerSave.SAVE_PATH,
	]:
		assert_has(files, path, "%s is destroyed by New Game and must be backed up" % path)


## The drift pin. `_wipe_persisted_world` is the authority; these lists only
## mirror it. Counting the wipe calls in its own source means a store added
## to the wipe without a matching backup entry fails here instead of silently
## shipping as un-undoable data loss.
func test_the_backup_lists_cover_exactly_what_the_wipe_destroys():
	var body := _wipe_body()
	assert_eq(
		World.backed_up_directories().size(),
		body.count("_world_reset.wipe_directory("),
		"one backed-up directory per wipe_directory call in _wipe_persisted_world"
	)
	# The chunk manager's own wipe_* calls (seven stores plus the world
	# clock), plus the player save, which World wipes directly.
	assert_eq(
		World.backed_up_files().size(),
		body.count("_chunk_manager.wipe_") + body.count("_player_save.wipe()"),
		"one backed-up file per single-file store the wipe removes"
	)


func test_no_path_is_backed_up_twice():
	var seen := {}
	for path in World.backed_up_directories() + World.backed_up_files():
		assert_false(seen.has(path), "%s listed twice" % path)
		seen[path] = true


## Backups are written next to the originals, so every path has to be one we
## own -- a res:// path would be read-only at runtime and silently fail.
func test_everything_backed_up_lives_under_user():
	for path in World.backed_up_directories() + World.backed_up_files():
		assert_true(str(path).begins_with("user://"), "%s is not user-writable" % path)

## Roofs are chunk modifications like any other -- the same per-chunk
## `<x>_<y>.bin` shape as MODIFICATIONS_DIR, written by the same building
## code. They were simply added to the manager later than the three
## directories above and never joined the wipe. Leaving them behind means a
## brand new world loads the PREVIOUS world's roofs: a house's walls and
## floors are gone (MODIFICATIONS_DIR was wiped) but its roof still hangs
## over the empty ground it used to cover.
func test_the_roof_modification_directory_is_wiped_and_backed_up_like_its_siblings():
	assert_string_contains(
		_wipe_body(), "wipe_directory(EarthChunkManager.ROOF_MODIFICATIONS_DIR)"
	)
	assert_has(
		World.backed_up_directories(), EarthChunkManager.ROOF_MODIFICATIONS_DIR,
		"roof modifications are destroyed by New Game and must be backed up"
	)


## Land ecology and the player's kept animals are world state exactly like the
## four directories above: a grazed-down meadow and a tamed horse both belong
## to ONE world. Both were added to EarthChunkManager after this wipe was
## written and never joined it, so New Game neither copied them aside nor
## destroyed them.
##
## That is not a tidiness complaint. The stale files are READ BACK on the next
## chunk load -- `_apply_persisted_ecology` seeds the old world's herbivore,
## predator and land-health numbers, and `_restore_kept_animals` spawns the old
## world's tamed horses -- and neither record carries a world identity, so
## nothing can tell a previous world's file from its own. A new world inherited
## the last player's overgrazed pasture and their livestock.
func test_ecology_and_kept_animals_are_backed_up_like_every_other_chunk_store():
	var dirs := World.backed_up_directories()
	assert_true(
		dirs.has(EarthChunkManager.ECOLOGY_DIR),
		"a region's land health and populations survive New Game unbacked"
	)
	assert_true(
		dirs.has(EarthChunkManager.KEPT_ANIMALS_DIR),
		"the player's tamed animals survive New Game unbacked"
	)


## The general form of the bug above, and the part that matters in six months:
## every `user://` directory EarthChunkManager persists must be BOTH backed up
## and named by the wipe. Read off the script's own constant map rather than
## restated here, so the next directory someone adds fails on the day they add
## it instead of quietly bleeding across worlds until a player notices.
func test_every_persisted_chunk_directory_is_both_backed_up_and_wiped():
	var body := _wipe_body()
	var dirs := World.backed_up_directories()
	var checked := 0
	# The Script OBJECT, not the class reference -- get_script_constant_map is
	# an instance method on GDScript, so it cannot be reached through the
	# preloaded class name.
	var manager_script: GDScript = load("res://src/world/earth_chunk_manager.gd")
	var constants := manager_script.get_script_constant_map()
	for constant_name in constants:
		var value = constants[constant_name]
		if typeof(value) != TYPE_STRING or not str(value).begins_with("user://"):
			continue
		if not str(constant_name).ends_with("_DIR"):
			continue
		checked += 1
		assert_true(dirs.has(value), "%s is persisted but never backed up" % constant_name)
		# The trailing ")" makes the match unambiguous: MODIFICATIONS_DIR is a
		# substring of ROOF_MODIFICATIONS_DIR, so a bare name would match the
		# wrong line and pass while the real one was missing.
		assert_string_contains(body, "EarthChunkManager.%s)" % constant_name)
	assert_gt(checked, 0, "expected EarthChunkManager to declare some user:// directories")
