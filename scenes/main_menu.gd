extends PanelContainer

## The start-up main menu and character creator (see concept/progression.md
## character creation). Shown over the world before anything spawns; the world
## stays paused until the player chooses. Screens: root (New Game / Host /
## Join / Quit), character creation (New Game + Host both route through it),
## and a join screen (IP entry).
##
## The creation screen is a real character creator: pick a class on the left,
## cycle five appearance axes on the right (skin, hair color, hair style,
## beard, eyes -- see HeroAppearance.AXES), and watch a live animated preview
## in the middle -- the character actually walking through grass, swinging
## its sword, and picking up/throwing a pebble (see CharacterPreviewStage),
## not a static pose. Purely glue -- World owns actually spawning the player,
## starting ENet, and applying the chosen class's stat lens (ClassArchetype);
## HeroAppearance/ProceduralCharacterSprite/CharacterPreviewStage own the look.

const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const PlayerSave = preload("res://src/gameplay/player_save.gd")
const HeroDna = preload("res://src/gameplay/hero_dna.gd")
const CharacterPreviewStageScene = preload("res://scenes/character_preview_stage.tscn")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")

## Friendly labels for a rolled genome's rarity (see HeroDna) -- purely
## presentational, the mechanics live in HeroDna itself.
const RARITY_LABELS := {
	HeroDna.RARITY_COMMON: "Common",
	HeroDna.RARITY_RARE: "Rare",
	HeroDna.RARITY_LEGENDARY: "★ Legendary ★",
}

## Human-readable blurbs for the archetypes (ClassArchetype has the stats).
const CLASS_BLURBS := {
	"warrior": "Tanky melee bruiser. High health and attack.",
	"mage": "Glass-cannon caster. Big mana pool, frail body.",
	"ranger": "Agile skirmisher. Balanced, stamina-heavy.",
	"beastmaster": "Tamer and support. Rounded stats.",
	"artisan": "Crafter. Sturdy, with deep stamina.",
	"herbalist": "Medic and caster. Mana over might.",
	"overseer": "Organizer. Modest mana, steady all round.",
}

## Friendly labels for the appearance axes, in display order.
const AXIS_LABELS := {
	"skin": "Skin",
	"hair_color": "Hair Colour",
	"hair_style": "Hair Style",
	"beard": "Beard",
	"eyes": "Eyes",
}

## The live preview's on-screen footprint -- close to the old static
## portrait's (PORTRAIT_SIZE(26,40) * the old PORTRAIT_SCALE(5) == (130,200))
## so swapping it in doesn't reflow the rest of the creator's layout.
const PREVIEW_SIZE := Vector2(150, 200)
## Renders the stage at a fraction of PREVIEW_SIZE and scales the result up
## (nearest-neighbour, via the container's own texture_filter below) --
## keeps the same crisp, chunky pixel-art look the old 5x-scaled portrait
## had, rather than a smoothly-antialiased render.
const PREVIEW_STRETCH_SHRINK := 2

const PANEL_SIZE := Vector2(760, 520)

## Emitted once the player has committed to a start mode + class.
## mode is "single" or "host"; chosen_class is a ClassArchetype name.
## `appearance` is the authored look (see HeroAppearance). `dna_stat_
## modifiers` is the rolled genome's stat swing (see HeroDna) -- World adds
## it on top of the class's own base stats before spawning.
signal start_requested(
	mode: String, chosen_class: String, appearance: Dictionary, dna_stat_modifiers: Dictionary
)
## Emitted to join a remote host at `address`.
signal join_requested(address: String)
## Emitted from the root screen's Load Game button (only shown when a save
## exists -- see docs/concept/persistence.md). Bypasses the character
## creator entirely; World restores the saved class/appearance/state itself.
signal load_requested()

## Path PlayerSave checks for "does a save exist" when deciding whether to
## offer Load Game -- overridable so tests never touch the real save file.
var save_path := PlayerSave.SAVE_PATH
## Where the DNA reroll budget (rerolls used + when it last reset) persists
## across menu sessions -- reused PlayerSave's generic path-taking I/O
## rather than a whole second file-format module for one small Dictionary.
## Overridable, same reason as save_path.
var reroll_save_path := "user://hero_dna_rerolls.bin"

var _archetypes := ClassArchetype.new()
var _appearance_maker := HeroAppearance.new()
var _item_sprite_generator := ProceduralItemSprite.new()
var _player_save := PlayerSave.new()
var _dna := HeroDna.new()

var _root_screen: Control
var _create_screen: Control
var _join_screen: Control

var _pending_mode := "single"
var _selected_class := "warrior"
## axis name -> chosen option index (see HeroAppearance.appearance_from_choices).
var _choices: Dictionary = {}

## The genotype -- appearance is DERIVED from this same seed (see
## _reroll_dna), never rolled independently, so genotype really does define
## phenotype rather than visuals and DNA being two unrelated random draws.
## Starts at a fixed seed (0) rather than a fresh random one so a menu that's
## never touched Randomise still shows a stable, reproducible default look
## (matching HeroAppearance's own existing seed-0 default in _ready).
var _dna_seed := 0
## How many DNA rerolls have been spent since the last daily reset (see
## HeroDna.can_reroll/MAX_FREE_REROLLS) -- persisted to reroll_save_path
## (see _load_reroll_state), NOT reset just by reopening the menu: the whole
## point of a real-world 24h gate is that it survives quitting the game.
var _rerolls_used := 0
## Unix timestamp (real-world, Time.get_unix_time_from_system) the reroll
## budget last refreshed -- persisted alongside _rerolls_used.
var _last_reset_unix := 0

var _class_detail: Label
var _class_buttons: Dictionary = {}  # archetype -> Button
var _preview_stage: CharacterPreviewStage
var _axis_value_labels: Dictionary = {}  # axis -> Label
var _dna_detail: Label
var _reroll_button: Button


func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	_choices = _appearance_maker.choices_from_appearance(
		_appearance_maker.appearance_for(_selected_class, 0)
	)
	_load_reroll_state()

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)

	var stack := Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(stack)

	_root_screen = _build_root_screen()
	_create_screen = _build_create_screen()
	_join_screen = _build_join_screen()
	for s in [_root_screen, _create_screen, _join_screen]:
		s.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(s)
	_show(_root_screen)

	# PRESET_CENTER alone only re-anchors the reference point to 0.5/0.5/0.5/
	# 0.5 -- Godot's set_anchor recomputes offsets to PRESERVE the control's
	# CURRENT on-screen rect under the new anchor fraction, it does not derive
	# offsets from size (verified against control.cpp). Since MainMenu is
	# never otherwise positioned, that left it pinned to the parent's
	# top-left corner regardless of when size was set. Centering needs the
	# four offsets explicitly set to a symmetric half-size box around the
	# anchor point -- the same pattern every other centered popup in this
	# codebase uses (SettingsOverlay/InventoryWindow/DevConsole, wired in
	# world.gd) -- pinned by
	# test_panel_is_actually_centered_not_pinned_to_a_corner.
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_SIZE.x / 2.0
	offset_top = -PANEL_SIZE.y / 2.0
	offset_right = PANEL_SIZE.x / 2.0
	offset_bottom = PANEL_SIZE.y / 2.0


# -- root ---------------------------------------------------------------------

func _build_root_screen() -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)

	box.add_child(_title_label("ALEPH ALFA", 44))
	var tagline := _muted_label("A living world, simulated from the ground up.")
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tagline)
	box.add_child(_spacer(28))

	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)

	buttons.add_child(_menu_button("New Game", func():
		_pending_mode = "single"
		_show(_create_screen), true))
	buttons.add_child(_menu_button("Host Game (LAN)", func():
		_pending_mode = "host"
		_show(_create_screen)))
	buttons.add_child(_menu_button("Join Game", func(): _show(_join_screen)))
	# Only offered when there's actually something to load -- no disabled
	# button pointing nowhere (see docs/concept/persistence.md). Bypasses the
	# character creator: a load restores a character, it doesn't author one.
	if _player_save.has_save(save_path):
		buttons.add_child(_menu_button("Load Game", func(): load_requested.emit()))
	buttons.add_child(_menu_button("Quit", func(): get_tree().quit()))
	return box


# -- character creation -------------------------------------------------------

func _build_create_screen() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	box.add_child(_title_label("Create your character", 26))
	box.add_child(_separator())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(cols)

	cols.add_child(_build_class_column())
	cols.add_child(_build_portrait_column())
	cols.add_child(_build_appearance_column())

	box.add_child(_separator())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(_menu_button("Back", func(): _show(_root_screen)))
	row.add_child(_menu_button("Begin", func():
		start_requested.emit(
			_pending_mode, _selected_class, current_appearance(), current_dna().stat_modifiers
		), true))
	box.add_child(row)

	_select_class(_selected_class)
	return box


func _build_class_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(210, 0)
	col.add_theme_constant_override("separation", 6)
	col.add_child(_section_label("CLASS"))

	for archetype in _archetypes.archetype_names():
		var b := Button.new()
		b.text = archetype.capitalize()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 28)
		b.pressed.connect(func(): _select_class(archetype))
		_class_buttons[archetype] = b
		col.add_child(b)

	_class_detail = _muted_label("")
	_class_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_detail.custom_minimum_size = Vector2(0, 72)
	col.add_child(_class_detail)
	return col


## The live preview -- the whole point of the creator screen. A real
## CharacterPreviewStage (walking through grass, swinging its sword, picking
## up/throwing a pebble -- see its own doc comment) rendered into a
## SubViewport rather than a static portrait image, so the creator actually
## shows off the character instead of just a pose.
func _build_portrait_column() -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)

	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.9)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.14)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	frame.add_theme_stylebox_override("panel", style)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var viewport_container := SubViewportContainer.new()
	viewport_container.custom_minimum_size = PREVIEW_SIZE
	viewport_container.stretch = true
	viewport_container.stretch_shrink = PREVIEW_STRETCH_SHRINK
	# Pixel art must not blur when scaled up.
	viewport_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.handle_input_locally = false
	_preview_stage = CharacterPreviewStageScene.instantiate()
	viewport.add_child(_preview_stage)
	viewport_container.add_child(viewport)
	frame.add_child(viewport_container)
	col.add_child(frame)

	# The DNA moment (see HeroDna/docs/concept/dna.md): rarity + trait name +
	# best-fit class, so a rare/legendary roll is visibly an event, not a
	# number buried in a stat sheet.
	_dna_detail = _muted_label("")
	_dna_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dna_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dna_detail.custom_minimum_size = Vector2(0, 48)
	col.add_child(_dna_detail)

	_reroll_button = _menu_button("Reroll DNA", func(): _reroll_dna())
	col.add_child(_reroll_button)
	return col


func _build_appearance_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(220, 0)
	col.add_theme_constant_override("separation", 6)
	col.add_child(_section_label("APPEARANCE"))

	for axis in HeroAppearance.AXES:
		col.add_child(_build_axis_row(axis))
	return col


## One "◀  Label: value  ▶" row cycling a single appearance axis.
func _build_axis_row(axis: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	row.add_child(_arrow_button("<", func(): _cycle_axis(axis, -1)))

	var value := Label.new()
	value.text = ""
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 12)
	_axis_value_labels[axis] = value
	row.add_child(value)

	row.add_child(_arrow_button(">", func(): _cycle_axis(axis, 1)))
	return row


func _arrow_button(glyph: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = glyph
	b.custom_minimum_size = Vector2(30, 26)
	b.pressed.connect(on_press)
	return b


func _cycle_axis(axis: String, step: int) -> void:
	_choices[axis] = int(_choices.get(axis, 0)) + step
	_refresh_appearance()


## Reads the persisted reroll budget (rerolls used + when it last reset --
## see reroll_save_path) and immediately applies a daily refresh if a full
## real-world day has already passed since then. A brand-new player (no save
## file yet) starts the clock now rather than at unix epoch, which would
## otherwise read as "a reset is overdue" on their very first visit.
func _load_reroll_state() -> void:
	var data := _player_save.load_data(reroll_save_path)
	_rerolls_used = int(data.get("rerolls_used", 0))
	_last_reset_unix = int(data.get("last_reset_unix", 0))
	if _last_reset_unix == 0:
		_last_reset_unix = int(Time.get_unix_time_from_system())
		_persist_reroll_state()
	_maybe_reset_rerolls()


func _seconds_since_last_reset() -> float:
	return float(Time.get_unix_time_from_system()) - float(_last_reset_unix)


## If a full real-world day has passed, refreshes the budget and re-stamps
## the reset time to now -- called on load and before every reroll attempt,
## so the very reroll that crosses the day boundary is itself allowed.
func _maybe_reset_rerolls() -> void:
	if not _dna.reroll_budget_has_reset(_seconds_since_last_reset()):
		return
	_rerolls_used = 0
	_last_reset_unix = int(Time.get_unix_time_from_system())
	_persist_reroll_state()


func _persist_reroll_state() -> void:
	_player_save.save(
		{"rerolls_used": _rerolls_used, "last_reset_unix": _last_reset_unix}, reroll_save_path
	)


## Rolls a fresh DNA seed (see HeroDna) -- appearance is then DERIVED from
## that SAME seed below, so this is genuinely "reroll the genotype", not two
## independent random draws for looks vs. stats. Gated on HeroDna.
## can_reroll: "rerolls should reset every 24h real world hours so you have
## to wait a whole day if your rerolls are empty forcing the player to make
## wise choices" -- the free budget is real-world-time gated (see
## _maybe_reset_rerolls), not just session-scoped. `has_premium` stays a
## hook for wherever a real payment flow eventually plugs in (dna.md's
## original premium-credits idea) -- no such system exists in this project
## yet, so it's always false here.
func _reroll_dna() -> void:
	_maybe_reset_rerolls()
	if not _dna.can_reroll(_rerolls_used, _seconds_since_last_reset(), false):
		return
	_rerolls_used += 1
	_persist_reroll_state()
	_dna_seed = randi()
	_choices = _appearance_maker.choices_from_appearance(
		_appearance_maker.appearance_for(_selected_class, _dna_seed)
	)
	_refresh_appearance()


## The look the player has authored so far -- handed to World on Begin.
func current_appearance() -> Dictionary:
	return _appearance_maker.appearance_from_choices(_selected_class, _choices)


## The rolled genome for the creator's current DNA seed (see HeroDna.roll) --
## handed to World on Begin alongside the appearance it was also derived
## from.
func current_dna() -> Dictionary:
	return _dna.roll(_dna_seed)


func _refresh_appearance() -> void:
	var appearance := current_appearance()
	if _preview_stage != null:
		_preview_stage.apply_appearance(appearance)
		# Re-equipping every refresh (rather than once at setup) sidesteps
		# any node-readiness ordering question -- cheap, and apply_appearance
		# above already regenerates textures on every refresh the same way.
		_preview_stage.equip_weapon(_item_sprite_generator.generate_texture("iron_sword"))
	for axis in _axis_value_labels:
		var label: Label = _axis_value_labels[axis]
		label.text = "%s: %s" % [AXIS_LABELS.get(axis, axis), _axis_value_text(axis, appearance)]
	_refresh_dna()


## The rarity/trait "moment" plus a reroll-budget readout, and which stat
## this genome swings up vs. down -- so a player can actually see "excellent
## magic attack but no defense" before committing.
func _refresh_dna() -> void:
	if _dna_detail == null:
		return
	var genome := current_dna()
	var lines: Array[String] = [RARITY_LABELS.get(genome.rarity, genome.rarity)]
	if genome.trait_name != "":
		lines.append(genome.trait_name)
	var swing := _stat_swing_text(genome.stat_modifiers)
	if swing != "":
		lines.append(swing)
	var rerolls_left := maxi(0, HeroDna.MAX_FREE_REROLLS - _rerolls_used)
	if rerolls_left > 0:
		lines.append("Rerolls left: %d" % rerolls_left)
	else:
		lines.append("Rerolls left: 0 (resets in %s)" % _time_until_reset_text())
	_dna_detail.text = "\n".join(lines)
	_reroll_button.disabled = not _dna.can_reroll(_rerolls_used, _seconds_since_last_reset(), false)


## "Xh Ym" style countdown to the next daily reroll refresh -- purely
## presentational.
func _time_until_reset_text() -> String:
	var remaining := maxf(0.0, HeroDna.RESET_INTERVAL_SECONDS - _seconds_since_last_reset())
	var hours := int(remaining) / 3600
	var minutes := (int(remaining) % 3600) / 60
	return "%dh %dm" % [hours, minutes]


## "ATK +14 / DEF -14" style readout of a genome's buffed/deficit stats --
## empty for a common roll with no material swing worth calling out.
func _stat_swing_text(stat_modifiers: Dictionary) -> String:
	var parts: Array[String] = []
	for key in stat_modifiers:
		var value: float = stat_modifiers[key]
		if absf(value) < 0.5:
			continue
		parts.append("%s %+d" % [_STAT_ABBREVIATIONS.get(key, key), int(value)])
	return " / ".join(parts)


const _STAT_ABBREVIATIONS := {
	"max_health": "HP", "attack_damage": "ATK", "max_mana": "Mana", "max_stamina": "Stam",
}


## What a given axis currently reads as -- a name where one exists (hair/
## beard styles), otherwise a 1-based "3 / 6" position within its pool.
func _axis_value_text(axis: String, appearance: Dictionary) -> String:
	match axis:
		"hair_style":
			return String(appearance.hair_style_name).capitalize()
		"beard":
			return String(appearance.beard_name).capitalize()
		_:
			var count := _appearance_maker.option_count(axis)
			var indices := _appearance_maker.choices_from_appearance(appearance)
			return "%d / %d" % [int(indices.get(axis, 0)) + 1, count]


func _select_class(archetype: String) -> void:
	_selected_class = archetype
	var stats: Dictionary = _archetypes.stats_for(archetype)
	_class_detail.text = "%s\n\nHP %+d   ATK %+d\nMana %+d   Stam %+d" % [
		CLASS_BLURBS.get(archetype, archetype),
		int(stats.get("max_health", 0.0)),
		int(stats.get("attack_damage", 0.0)),
		int(stats.get("max_mana", 0.0)),
		int(stats.get("max_stamina", 0.0)),
	]
	# Highlight the picked class; dim the rest. (Loop var deliberately not
	# called `name` -- that shadows Node.name on this PanelContainer.)
	for class_id in _class_buttons:
		var button: Button = _class_buttons[class_id]
		button.modulate = Color(1, 1, 1) if class_id == archetype else Color(1, 1, 1, 0.55)
	_refresh_appearance()


# -- join ---------------------------------------------------------------------

func _build_join_screen() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	box.add_child(_title_label("Join a host", 26))
	box.add_child(_separator())

	var hint := _muted_label("Enter the host's address (a LAN IP, or a tunnel host for internet play).")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var field := LineEdit.new()
	field.placeholder_text = "127.0.0.1"
	field.custom_minimum_size = Vector2(0, 32)
	box.add_child(field)

	box.add_child(_spacer(8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(_menu_button("Back", func(): _show(_root_screen)))
	row.add_child(_menu_button("Connect", func():
		var addr: String = field.text.strip_edges()
		join_requested.emit(addr if addr != "" else "127.0.0.1"), true))
	box.add_child(row)
	return box


# -- shared widgets -----------------------------------------------------------

func _title_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.modulate = Color(1, 1, 1, 0.55)
	return l


func _muted_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.7)
	return l


func _separator() -> Control:
	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.25)
	return sep


func _spacer(height: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	return s


## `primary` marks the screen's main call to action, drawn wider.
func _menu_button(text: String, on_press: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240 if primary else 150, 38 if primary else 34)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(on_press)
	return b


func _show(screen: Control) -> void:
	for s in [_root_screen, _create_screen, _join_screen]:
		s.visible = s == screen


## Called by World to hide the menu once a game has started.
func close() -> void:
	visible = false
