extends Control

## Node/rendering adapter for docs/concept/easter_eggs.md's "hidden retro
## handheld" entry -- the actual visible, playable screen the battered
## handheld prop (RetroHandheld) boots into once opened. Every real game
## rule lives in three separate pure modules this Control only reads/
## drives: HandheldBattle (turn resolution), HandheldCatch (catch chance),
## HandheldRoster (which species/stats exist) -- plus HandheldCollection,
## the pure catch-list model this Control owns and renders as a "world's
## smallest Pokédex" dex screen. Not held to those modules' own unit-test
## rigor -- this project's established convention (see test_crafting_
## window.gd's own "layout glue, not game rules" framing, and
## test_joust_match_view.gd's identical treatment of JoustMatchView) only
## demands that of a pure rules module; test_handheld_battle_view.gd covers
## this file's own thin glue instead.
##
## Built entirely from Control/ColorRect/Label/Button children (no new art
## asset for the CHROME -- matching JoustMatchView's own "prefer no art
## asset" precedent), styled as a small bordered device with a muted-green
## "screen" area so it reads as a handheld rather than a bare menu. Each
## creature is drawn with the EXISTING rendering this project already built
## (ProceduralAnimalSprite for a species with no illustrated sheet,
## IllustratedAnimalSprite's own idle frame for one that has one -- see
## _texture_for) at a small, fixed on-screen size -- "miniature... versions
## of this project's own already-built roster" per the doc, zero new
## creature art.
##
## KNOWN GAP, not fixed here (out of this stage's own scope -- see
## _texture_for's own doc comment): "wolf" has a full AnimalAnatomy body
## profile but no entry in ProceduralAnimalSprite's own SPECIES_BASE_COLORS/
## SPECIES_SHAPE_FAMILY tables, so it currently renders as the generic tan
## "herbivore" silhouette rather than a wolf-shaped one, both here and in
## the open world's own /spawn wolf. A pre-existing gap in the open world's
## own wolf wiring, not previously documented anywhere in this project (see
## docs/progress.md's Easter Eggs section for the full scope note) -- not
## something introduced or silently papered-over by this stage.
##
## A genuinely separate, self-contained mini-game loop, not just a modal
## window: scenes/world.gd pauses the whole tree while this is open
## (get_tree().paused = true, the same "acts like a real pause screen"
## pattern JoustMatchView/_toggle_settings_menu already use) and this
## Control runs via PROCESS_MODE_ALWAYS.
##
## Catching (HandheldCatch): the player spends a turn on a catch attempt
## INSTEAD of a battle move (see attempt_catch_now) -- the enemy still acts
## that round on a failed attempt (HandheldBattle resolves with the
## player's own move as MOVE_PASS), the real "a failed throw doesn't stop
## the wild creature from fighting back" convention. seed_value is derived
## from a hash of the encounter's own species id and a per-encounter
## attempt counter (never randf()) -- the same "hash real, already-known
## inputs" idiom CreatureRenderer's own wander_seed/species_seed already
## use, so repeated attempts on the same wild creature vary deterministically
## rather than literally rolling dice.

signal closed()

const HandheldBattle = preload("res://src/gameplay/handheld_battle.gd")
const HandheldCatch = preload("res://src/gameplay/handheld_catch.gd")
const HandheldRoster = preload("res://src/gameplay/handheld_roster.gd")
const HandheldCollection = preload("res://src/gameplay/handheld_collection.gd")
const HealthBar = preload("res://src/gameplay/health_bar.gd")
const ProceduralAnimalSprite = preload("res://src/rendering/procedural_animal_sprite.gd")
const IllustratedAnimalSprite = preload("res://src/rendering/illustrated_animal_sprite.gd")

const SCREEN_BATTLE := "battle"
const SCREEN_DEX := "dex"

## The player's own permanent companion for every encounter -- a fixed
## roster pick (a loyal wolf at the player's side), not a "choose your
## starter" flow; keeping this out of scope is a deliberate simplification
## (this whole mini-game is zero mechanical weight either way, per pillar 2)
## rather than an oversight.
const PLAYER_COMPANION_SPECIES := "wolf"

const SPRITE_SIZE := Vector2(72.0, 56.0)
const HP_BAR_WIDTH := 140.0
const HP_BAR_HEIGHT := 10.0

const SCREEN_BG := Color(0.16, 0.24, 0.14)
const DEVICE_BG := Color(0.12, 0.12, 0.13)
const HP_BAR_BG := Color(0.05, 0.05, 0.05)
const HP_BAR_FILL := Color(0.35, 0.75, 0.3)
const TEXT_COLOR := Color(0.78, 0.92, 0.72)

var _battle := HandheldBattle.new()
var _catcher := HandheldCatch.new()
var _roster := HandheldRoster.new()
var _collection := HandheldCollection.new()

var _state: Dictionary = {}
var _enemy_species := ""
var _active := false
var _screen := SCREEN_BATTLE
var _attempt_count := 0

var _battle_panel: Control
var _dex_panel: Control
var _player_sprite: TextureRect
var _enemy_sprite: TextureRect
var _player_hp_fill: ColorRect
var _enemy_hp_fill: ColorRect
var _player_hp_label: Label
var _enemy_hp_label: Label
var _message_label: Label
var _move_buttons: Dictionary = {}
var _catch_button: Button
var _new_encounter_button: Button
var _dex_label: Label


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.75)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.offset_left = 0.0
	backdrop.offset_top = 0.0
	backdrop.offset_right = 0.0
	backdrop.offset_bottom = 0.0
	add_child(backdrop)

	var device := ColorRect.new()
	device.color = DEVICE_BG
	device.custom_minimum_size = Vector2(340.0, 400.0)
	device.set_anchors_preset(Control.PRESET_CENTER)
	device.offset_left = -170.0
	device.offset_top = -200.0
	device.offset_right = 170.0
	device.offset_bottom = 200.0
	add_child(device)

	var screen_bg := ColorRect.new()
	screen_bg.color = SCREEN_BG
	screen_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_bg.offset_left = 14.0
	screen_bg.offset_top = 14.0
	screen_bg.offset_right = -14.0
	screen_bg.offset_bottom = -50.0
	device.add_child(screen_bg)

	var screen_root := VBoxContainer.new()
	screen_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_root.add_theme_constant_override("separation", 4)
	screen_bg.add_child(screen_root)

	_battle_panel = _build_battle_panel()
	screen_root.add_child(_battle_panel)
	_dex_panel = _build_dex_panel()
	screen_root.add_child(_dex_panel)

	var footer := HBoxContainer.new()
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 14.0
	footer.offset_top = -34.0
	footer.offset_right = -14.0
	footer.offset_bottom = -10.0
	device.add_child(footer)

	var dex_toggle := Button.new()
	dex_toggle.text = "Dex"
	dex_toggle.pressed.connect(func(): _toggle_screen())
	footer.add_child(dex_toggle)

	var close_button := Button.new()
	close_button.text = "Put Away"
	close_button.pressed.connect(func(): close())
	footer.add_child(close_button)


func _build_battle_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 4)

	var sprites_row := HBoxContainer.new()
	sprites_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sprites_row.add_theme_constant_override("separation", 24)
	panel.add_child(sprites_row)

	var player_col := VBoxContainer.new()
	_player_sprite = _make_sprite_rect()
	player_col.add_child(_player_sprite)
	_player_hp_label = _make_label("")
	player_col.add_child(_player_hp_label)
	_player_hp_fill = _make_hp_bar(player_col)
	sprites_row.add_child(player_col)

	var enemy_col := VBoxContainer.new()
	_enemy_sprite = _make_sprite_rect()
	enemy_col.add_child(_enemy_sprite)
	_enemy_hp_label = _make_label("")
	enemy_col.add_child(_enemy_hp_label)
	_enemy_hp_fill = _make_hp_bar(enemy_col)
	sprites_row.add_child(enemy_col)

	_message_label = _make_label("")
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.custom_minimum_size = Vector2(280.0, 0.0)
	panel.add_child(_message_label)

	var moves_row := HBoxContainer.new()
	moves_row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(moves_row)
	for move_id in HandheldBattle.PLAYER_MOVES:
		var button := Button.new()
		button.text = move_id.capitalize()
		button.pressed.connect(select_move.bind(move_id))
		moves_row.add_child(button)
		_move_buttons[move_id] = button

	var actions_row := HBoxContainer.new()
	actions_row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(actions_row)

	_catch_button = Button.new()
	_catch_button.text = "Catch"
	_catch_button.pressed.connect(func(): attempt_catch_now())
	actions_row.add_child(_catch_button)

	_new_encounter_button = Button.new()
	_new_encounter_button.text = "Next Encounter"
	_new_encounter_button.visible = false
	_new_encounter_button.pressed.connect(func(): start_encounter())
	actions_row.add_child(_new_encounter_button)

	return panel


func _build_dex_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.visible = false

	var title := _make_label("WILDLIFE LOG")
	panel.add_child(title)

	_dex_label = _make_label("")
	_dex_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_dex_label)

	return panel


func _make_sprite_rect() -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = SPRITE_SIZE
	rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return rect


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", TEXT_COLOR)
	return label


func _make_hp_bar(parent: Control) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = HP_BAR_BG
	bg.custom_minimum_size = Vector2(HP_BAR_WIDTH, HP_BAR_HEIGHT)
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.color = HP_BAR_FILL
	fill.position = Vector2.ZERO
	fill.size = Vector2(HP_BAR_WIDTH, HP_BAR_HEIGHT)
	bg.add_child(fill)
	return fill


## Real illustrated art (IllustratedAnimalSprite) when a species has it
## (currently the Germany-region legendaries: krampus/lindwurm/rubezahl),
## otherwise the procedural generator every other species already renders
## with in the open world -- the exact same "ask before you leap" fallback
## chain CreatureMarker's own _animation_step uses. seed_value is a plain
## hash of the species id (not per-individual) -- this mini-game's tiny
## roster of encounters has no per-creature identity worth varying coat
## jitter for.
func _texture_for(species: String) -> Texture2D:
	var illustrated := IllustratedAnimalSprite.new()
	if illustrated.has_species(species):
		var frames := illustrated.generate_textures(species, "idle")
		if not frames.is_empty():
			return frames[0]
	return ProceduralAnimalSprite.new().generate_texture(species, hash(species))


func _toggle_screen() -> void:
	if _screen == SCREEN_BATTLE:
		show_dex_screen()
	else:
		show_battle_screen()


func show_dex_screen() -> void:
	_screen = SCREEN_DEX
	_battle_panel.visible = false
	_dex_panel.visible = true
	_refresh_dex_visuals()


func show_battle_screen() -> void:
	_screen = SCREEN_BATTLE
	_battle_panel.visible = true
	_dex_panel.visible = false


## Opens the handheld: resets to the battle screen and starts a fresh
## encounter. scenes/world.gd calls this the moment RetroHandheld.can_open
## clears (see _check_retro_handheld).
func open() -> void:
	visible = true
	move_to_front()
	show_battle_screen()
	start_encounter()


func close() -> void:
	visible = false
	closed.emit()


## A fresh 1v1: the player's fixed companion (PLAYER_COMPANION_SPECIES)
## against a species drawn from HandheldRoster.encounter_species. The
## encounter roll itself is ordinary randf() (picking WHICH creature you
## run into, not a combat OUTCOME -- the same category of "which cameo
## appears" roll EasterEggCreatures.check_one already takes as a plain
## caller-supplied float), never inside HandheldBattle/HandheldCatch
## themselves, both of which stay fully deterministic.
func start_encounter() -> void:
	_enemy_species = _roster.encounter_species(randf())
	var player_stats := _roster.stats_for(PLAYER_COMPANION_SPECIES)
	var enemy_stats := _roster.stats_for(_enemy_species)
	_state = _battle.initial_state(player_stats, enemy_stats)
	_active = true
	_attempt_count = 0
	_message_label.text = "A wild %s appears!" % _enemy_species.capitalize()
	_new_encounter_button.visible = false
	_set_moves_enabled(true)
	_refresh_battle_visuals()


## Resolves one round: `move_id` is one of HandheldBattle.PLAYER_MOVES,
## selected by a move button. The AI's own move is decided from the
## enemy's OWN remaining-health fraction as of the START of this round
## (HandheldBattle.ai_choose_move), the same "caller supplies the real
## primitive" shape ai_should_flap already established for this doc's
## Easter-egg family.
func select_move(move_id: String) -> void:
	if not _active:
		return
	var enemy_fraction := float(_state["enemy"]["hp"]) / float(_state["enemy"]["max_hp"])
	var enemy_move := _battle.ai_choose_move(enemy_fraction)
	_state = _battle.resolve_round(_state, move_id, enemy_move)
	_refresh_battle_visuals()
	_check_battle_over()


## Spends the player's turn on a catch attempt instead of a battle move
## (see this file's own doc comment). `seed_override` lets a caller (tests
## only) force a specific seed rather than the real per-attempt hash derived
## below -- -1 (the default) always derives the real one.
func attempt_catch_now(seed_override: int = -1) -> void:
	if not _active:
		return
	var fraction := float(_state["enemy"]["hp"]) / float(_state["enemy"]["max_hp"])
	var seed_value := seed_override
	if seed_value < 0:
		seed_value = hash("%s_%d" % [_enemy_species, _attempt_count])
	_attempt_count += 1
	if _catcher.attempt_catch(fraction, seed_value):
		_collection.mark_caught(_enemy_species)
		_message_label.text = "Caught the wild %s!" % _enemy_species.capitalize()
		_end_encounter()
		return
	_message_label.text = "The wild %s broke free!" % _enemy_species.capitalize()
	var enemy_move := _battle.ai_choose_move(fraction)
	_state = _battle.resolve_round(_state, HandheldBattle.MOVE_PASS, enemy_move)
	_refresh_battle_visuals()
	_check_battle_over()


func _check_battle_over() -> void:
	if not bool(_state["over"]):
		return
	if String(_state["winner"]) == "player":
		_message_label.text = "The wild %s flees into the brush!" % _enemy_species.capitalize()
	else:
		_message_label.text = "Your companion can't continue -- time to retreat!"
	_end_encounter()


func _end_encounter() -> void:
	_active = false
	_set_moves_enabled(false)
	_new_encounter_button.visible = true


func _set_moves_enabled(enabled: bool) -> void:
	for move_id in _move_buttons:
		(_move_buttons[move_id] as Button).disabled = not enabled
	_catch_button.disabled = not enabled


func _refresh_battle_visuals() -> void:
	if _state.is_empty():
		return
	_player_sprite.texture = _texture_for(PLAYER_COMPANION_SPECIES)
	_enemy_sprite.texture = _texture_for(_enemy_species)
	var player: Dictionary = _state["player"]
	var enemy: Dictionary = _state["enemy"]
	_player_hp_label.text = "%s  %d/%d" % [
		PLAYER_COMPANION_SPECIES.capitalize(), roundi(player["hp"]), roundi(player["max_hp"])
	]
	_enemy_hp_label.text = "%s  %d/%d" % [
		_enemy_species.capitalize(), roundi(enemy["hp"]), roundi(enemy["max_hp"])
	]
	_player_hp_fill.size.x = HealthBar.new().fill_width(player["hp"], player["max_hp"], HP_BAR_WIDTH)
	_enemy_hp_fill.size.x = HealthBar.new().fill_width(enemy["hp"], enemy["max_hp"], HP_BAR_WIDTH)


func _refresh_dex_visuals() -> void:
	var lines: Array[String] = []
	var index := 0
	for entry in _collection.entries():
		index += 1
		var species: String = entry["species"]
		var tag := "LEGENDARY" if entry["tier"] == HandheldRoster.TIER_LEGENDARY else "common"
		var line := "%03d  %s" % [index, species.capitalize() if entry["caught"] else "???"]
		if entry["caught"]:
			line += "  [%s]" % tag
		lines.append(line)
	_dex_label.text = (
		"%d / %d caught\n" % [_collection.caught_count(), _collection.total_species()]
		+ "\n".join(lines)
	)
