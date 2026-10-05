extends SceneTree

## Live-gameplay probe for two user reports this unit-test suite never
## caught: "Tab doesn't target and cycle enemies anymore" and "spark/
## fireball are still not homing". Drives REAL input (Input.action_press,
## the same InputMap World._apply_keybindings sets up) through REAL
## Player._physics_process over real frames, with a real GPU render each
## step -- the same "code tracing alone is not enough evidence" technique
## probe_spell_distortion_render.gd already established, extended from a
## single static frame to a driven sequence.
##
## Needs a REAL GPU/window, not --headless. Run:
##   xvfb-run -a <godot> --path . --rendering-driver opengl3 -s tools/probe_tab_cycle_and_homing.gd

## Loaded at RUNTIME inside _init (not top-level `const ... = preload`):
## compiling Player/CreatureRenderer/EarthChunkManager together at parse
## time, in a bare `-s script.gd` entry point, cascades into "Identifier
## not found: ConsoleFocus/WorldItemBus" (the autoload singletons) and
## leaves some of the depended scripts as broken GDScript references --
## GUT's own cmdln entry point does not hit this (its test scripts load
## these same classes fine), so this is specific to compiling them all
## into ONE top-level const list in a non-GUT entry script. `load()` after
## the scene tree is already running sidesteps it entirely.
var PlayerScene
var CreatureRenderer
var CreatureMarker
var CreatureInfo
var EarthChunkManager
var TerrainRenderer
var Keybindings
var SpellProjectileMarker
var SpellEffectMarker

const OUT_DIR := "res://tools/live_probe_renders"

var viewport: SubViewport
var player
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var manager
var renderer


func _init():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame
	PlayerScene = load("res://scenes/player.tscn")
	CreatureRenderer = load("res://src/rendering/creature_renderer.gd")
	CreatureMarker = load("res://src/rendering/creature_marker.gd")
	CreatureInfo = load("res://src/world/creature_info.gd")
	EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	TerrainRenderer = load("res://src/rendering/terrain_renderer.gd")
	Keybindings = load("res://src/gameplay/keybindings.gd")
	SpellProjectileMarker = load("res://src/rendering/spell_projectile_marker.gd")
	SpellEffectMarker = load("res://src/rendering/spell_effect_marker.gd")
	_register_all_keybindings()
	await process_frame
	await process_frame
	await _setup_scene()
	await _probe_tab_cycle()
	await _probe_homing()
	print("DONE")
	quit()


func _register_all_keybindings() -> void:
	for entry in Keybindings.ACTIONS:
		if not InputMap.has_action(entry["action"]):
			InputMap.add_action(entry["action"])
		InputMap.action_erase_events(entry["action"])
		var event := InputEventKey.new()
		event.physical_keycode = entry["default"]
		InputMap.action_add_event(entry["action"], event)


func _capture(label: String) -> Image:
	RenderingServer.force_draw()
	await process_frame
	RenderingServer.force_draw()
	var img: Image = viewport.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, label])
	print("saved %s.png" % label)
	return img


func _setup_scene() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(400, 300)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	viewport.add_child(tile_map_layer)
	viewport.add_child(entities_parent)
	viewport.add_child(creatures_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	renderer = CreatureRenderer.new()

	player = PlayerScene.instantiate()
	viewport.add_child(player)
	# World.gd keeps players under _players, each NAMED
	# str(multiplayer.get_unique_id()) -- Player._is_local_player_instance
	# checks `name.to_int() == multiplayer.get_unique_id()`, so an
	# un-renamed instantiate() (default scene-root name, non-numeric) reads
	# as a REMOTE player and _controlled_locally() goes false, silently
	# skipping every Input.is_action_pressed() poll in the whole file. Real
	# setup, not a probe-only quirk -- matching it here. 1 is the default
	# unique id for an offline/unconnected peer (confirmed via DIAG print
	# below rather than assumed).
	print("DIAG player.get_multiplayer().get_unique_id(): ", player.get_multiplayer().get_unique_id())
	player.name = str(player.get_multiplayer().get_unique_id())
	# Player._authority_step's own FIRST line is `if _chunk_manager == null:
	# return` -- every single per-frame step below it (_dodge_step among
	# them) is skipped entirely without this. setup() is player.gd's own
	# documented "must be called before the first _physics_process" entry
	# point, the same one World.gd's real player-spawn path calls.
	player.setup(manager, TerrainRenderer.TILE_SIZE)
	player.position = Vector2(200, 150)
	player.apply_class("mage", {"max_mana": 70.0})
	player.mana = player.max_mana
	player._last_facing_direction = Vector2.RIGHT

	await process_frame


func _spawn_boar(offset: Vector2):
	return renderer.spawn_single(
		creatures_parent, "boar", player.position + offset, manager, TerrainRenderer.TILE_SIZE
	)


## Drives one physics step with a given input action held, the same shape
## the real SceneTree main loop would deliver it, over `frames` frames.
func _hold(actions_down: Array, frames: int) -> void:
	for a in ["dodge", "sprint"]:
		if actions_down.has(a):
			Input.action_press(a)
		else:
			Input.action_release(a)
	for _i in frames:
		player._physics_process(1.0 / 60.0)
		await process_frame


func _probe_tab_cycle() -> void:
	print("--- Tab cycle probe ---")
	var near = _spawn_boar(Vector2(40, 0))
	var far = _spawn_boar(Vector2(80, 30))
	print("explicit_target before: ", player.explicit_target())
	print("DIAG _controlled_locally: ", player._controlled_locally())
	print("DIAG _is_local_player_instance: ", player._is_local_player_instance())
	print("DIAG is_multiplayer_authority: ", player.is_multiplayer_authority())
	var ConsoleFocusAutoload = player.get_node_or_null("/root/ConsoleFocus")
	print("DIAG ConsoleFocus node: ", ConsoleFocusAutoload, " is_open=", ConsoleFocusAutoload.is_open if ConsoleFocusAutoload != null else "N/A")
	print("DIAG candidates: ", player._nearby_enemy_candidates())
	print("DIAG near.info.temperament: ", near.info.temperament, " is_predator: ", near.info.is_predator)
	print("DIAG distance to near: ", player.position.distance_to(near.position), " TARGET_RADIUS via candidates list above")

	# Hold Shift (sprint), tap Tab (dodge) -- one physics frame with both
	# down (rising edge of dodge), matching a real keypress.
	await _hold(["sprint", "dodge"], 1)
	await _hold(["sprint"], 1)  # Tab released, Shift still held
	print("explicit_target after first Shift+Tab: ", player.explicit_target())
	print("  is it the nearer boar? ", player.explicit_target() == near)
	print("  ring visible on near boar? is_targeted=", near.is_targeted() if near.has_method("is_targeted") else "no is_targeted method")
	await _capture("tab_cycle_after_first_press")

	# Release Shift, release Tab fully, then press again to cycle to the
	# second candidate.
	await _hold([], 1)
	await _hold(["sprint", "dodge"], 1)
	await _hold(["sprint"], 1)
	print("explicit_target after second Shift+Tab: ", player.explicit_target())
	print("  is it the farther boar? ", player.explicit_target() == far)
	await _hold([], 1)
	await _capture("tab_cycle_after_second_press")

	near.queue_free()
	far.queue_free()
	player._set_explicit_target(null)
	await process_frame


## Scans the WHOLE viewport, not just entities_parent -- _launch_projectile/
## _spawn_spell_effect both add their marker to Player.get_parent(), which
## in this probe's own setup is `viewport` itself, not `entities_parent`
## (that only holds what CreatureRenderer/EarthChunkManager place). An
## earlier version of this probe scanned the wrong node and always saw
## zero, which would have been misread as "no projectile ever launches."
func _spell_markers_in(node: Node) -> Dictionary:
	var bolts := 0
	var effects := 0
	for child in node.get_children():
		if is_instance_of(child, SpellProjectileMarker):
			bolts += 1
		if is_instance_of(child, SpellEffectMarker):
			effects += 1
	return {"bolts": bolts, "effects": effects}


func _probe_homing() -> void:
	print("--- Homing probe ---")
	var target = _spawn_boar(Vector2(100, 0))
	player.mana = player.max_mana
	player._cast_cooldown_remaining = 0.0
	player._set_explicit_target(target)

	await _capture("homing_00_before_cast")
	var cast_ok: bool = player.cast_spell("spark")
	print("cast accepted: ", cast_ok)
	var right_after := _spell_markers_in(viewport)
	print(
		"immediately after cast, SAME frame, before any process tick: bolts=%d effects=%d target.health=%.1f"
		% [right_after["bolts"], right_after["effects"], target.info.health]
	)

	# Real `await process_frame` (not a manual _process() call) so the
	# ENGINE drives the projectile exactly as it would in the running game
	# -- but under software rendering a real frame's delta is unpredictable
	# (could be far more than 1/60s), so this prints the REAL elapsed time
	# each step actually took rather than assuming 60fps.
	var clock := Time.get_ticks_usec()
	var total_elapsed := 0.0
	for i in range(1, 40):
		await process_frame
		var now := Time.get_ticks_usec()
		var step_seconds := float(now - clock) / 1_000_000.0
		clock = now
		total_elapsed += step_seconds
		var counts := _spell_markers_in(viewport)
		print(
			"frame %d  step=%.4fs  total=%.4fs  bolts=%d  effects=%d  target.health=%.1f"
			% [i, step_seconds, total_elapsed, counts["bolts"], counts["effects"], target.info.health]
		)
		if counts["bolts"] > 0 and i % 3 == 0:
			await _capture("homing_frame_%02d" % i)
		if counts["bolts"] == 0 and counts["effects"] > 0:
			print("bolt has resolved (SpellEffectMarker now exists, no SpellProjectileMarker remains)")
			break
	await _capture("homing_99_after_flight_window")
	print("target.info.health final: ", target.info.health)

	target.queue_free()
	await process_frame
