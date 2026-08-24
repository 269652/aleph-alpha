extends PanelContainer

## The start-up main menu and character creator (see concept/progression.md
## character creation). Shown over the world before anything spawns; the world
## stays paused until the player chooses. Screens: root (New Game / Host /
## Join / Quit), character creation (New Game + Host both route through it),
## and a join screen (IP entry).
##
## The creation screen is a real character creator: pick a class on the left,
## cycle five appearance axes on the right (skin, hair color, hair style,
## beard, eyes -- see HeroAppearance.AXES), and watch a live full-body
## portrait update in the middle. Purely glue -- World owns actually spawning
## the player, starting ENet, and applying the chosen class's stat lens
## (ClassArchetype); HeroAppearance/ProceduralCharacterSprite own the look.

const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")
const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const PlayerSave = preload("res://src/gameplay/player_save.gd")
const HeroDna = preload("res://src/gameplay/hero_dna.gd")
const SkillTree = preload("res://src/gameplay/skill_tree.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## Shared look, reusing UiTheme's palette (the same dark/rounded/gold-accent
## theme World assigns to every other menu/window -- see World._ui_theme) so
## the creator's own extra styling (class/skill cards, tabs) matches the
## rest of the app exactly instead of picking its own slightly-different
## colors (reported: "it looks poor and not detailed/fleshed out").
const ACCENT := UiTheme.ACCENT
const PANEL_BG := UiTheme.PANEL_BG
const PANEL_BORDER := UiTheme.PANEL_BORDER
const CARD_BG := Color(0.19, 0.21, 0.27, 1.0)  # matches UiTheme.BUTTON_NORMAL
const CARD_BG_SELECTED := Color(0.34, 0.27, 0.13, 1.0)  # accent-tinted BUTTON_NORMAL

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
	"trim": "Trim Color",
}

## The portrait renders at ProceduralCharacterSprite.PORTRAIT_SIZE and is
## scaled up by this much -- nearest-neighbour, so it stays crisp pixel art.
const PORTRAIT_SCALE := 5

## Widened/heightened for the tabbed creator (Character + Skills, see
## _build_create_screen) -- the old 760x520 already fit its 3-column layout
## tightly with nothing to spare for a tab bar or a skills grid.
const PANEL_SIZE := Vector2(880, 620)

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
var _char_sprite := ProceduralCharacterSprite.new()
var _player_save := PlayerSave.new()
var _dna := HeroDna.new()
var _skill_tree := SkillTree.new()

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
var _class_buttons: Dictionary = {}  # archetype -> PanelContainer (see _build_class_card)
## archetype -> the small "★" resonance badge on its icon card (see
## _build_class_card/_refresh_dna) -- only one is ever visible at a time,
## whichever archetype the current DNA roll resonates with most.
var _resonance_badges: Dictionary = {}
## Cached per-class mini portraits for the icon row -- generated once each
## (that class's own default look, seed 0), never per-frame.
var _class_icon_textures: Dictionary = {}
var _portrait: TextureRect
## The glow ring behind the portrait, repainted to the rolled DNA's rarity
## color (see _refresh_dna) -- the "DNA moment" made visible, not just read.
var _dna_glow: PanelContainer
var _dna_glow_tween: Tween
var _axis_value_labels: Dictionary = {}  # axis -> Label
var _dna_detail: Label
var _reroll_button: Button
## The big class-name heading above the blurb/stats -- separate Label so it
## can carry its own bigger accent-colored font (see _select_class).
var _class_name_label: Label

## Skills tab (see _build_skills_tab/_refresh_skills_tab) -- a per-class
## preview over the one shared SkillTree (see docs/progress.md: full
## class-specific skill webs are still unbuilt), so a player can see what's
## available and which of it favors their picked class before committing.
var _skills_class_label: Label
var _skills_summary_label: Label
var _skill_node_cards: Dictionary = {}  # node_id -> PanelContainer


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
	var subtitle := _muted_label("Pick a class, preview its skills, then make it your own.")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	box.add_child(_accent_separator())

	# Tabs: Character (class/portrait/appearance -- the previous single
	# screen) and Skills (a preview of what's actually learnable, BEFORE
	# committing to a class -- reported: "there should be tabs with
	# character and skilltree so you can view each classes skills before
	# creating"). Both stay live as the player picks a class/rerolls DNA/
	# cycles appearance -- see _select_class/_refresh_dna/_refresh_appearance,
	# which now also refresh whichever tab reflects that state.
	var tabs := TabContainer.new()
	_style_tabs(tabs)
	tabs.add_child(_build_character_tab())
	tabs.add_child(_build_skills_tab())

	# Wrapped in a ScrollContainer, NOT given straight to `box`: MainMenu is
	# a fixed-size panel (see PANEL_SIZE/_ready's explicit offsets, not an
	# auto-growing one), and the tab content's real minimum height (the
	# portrait column's 5x-scaled preview, the skills grid, etc.) can
	# genuinely exceed it once real fonts/theme metrics are applied --
	# reported: "the character creation screen overflows and is not
	# scrollable so I can't start a new game because button is not
	# visible". A plain child would silently overflow the fixed panel and
	# push the Back/Begin row (added below, deliberately OUTSIDE this
	# scroll area) off-screen entirely with nothing to reach it by; this
	# guarantees the tab content scrolls internally while Begin always
	# stays visible and reachable at a fixed position.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(tabs)
	box.add_child(scroll)

	box.add_child(_accent_separator())
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


## The Character tab: a dominant HERO SHOWCASE on the left -- class icons
## sitting right on top of the character's own card, a big glowing portrait,
## class/DNA info -- and the appearance controls on the right. Replaces the
## old 3 equal text-heavy columns (a plain class name list off to the side)
## with the class picker literally layered onto the character preview it's
## picking a look for, since this is the first thing a new player ever sees
## and a name list reads as a settings form, not an introduction (reported:
## "make it genuinely captivating ... I want the classes to be icons and on
## top over the character").
func _build_character_tab() -> Control:
	var cols := HBoxContainer.new()
	cols.name = "Character"
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL

	cols.add_child(_build_hero_column())
	cols.add_child(_build_appearance_column())
	return cols


## The showcase card: class-icon strip -> glowing portrait -> class name/
## blurb/stats -> DNA readout -> Reroll button, all one continuous story
## about the character being built, top to bottom.
func _build_hero_column() -> Control:
	var col := _card_panel(Vector2(0, 0))
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 8)
	col.add_child(inner)

	inner.add_child(_build_class_icon_row())

	# The DNA "moment" made visible, not just read about: a glow ring sits
	# BEHIND the portrait and repaints to the rolled genome's rarity color
	# (see _refresh_dna) -- common stays a quiet accent glow, rare turns
	# cool blue, legendary a vivid pulsing gold, so a great roll is felt the
	# instant it lands instead of only readable in the text line below it.
	var glow_wrap := Control.new()
	glow_wrap.custom_minimum_size = Vector2(
		ProceduralCharacterSprite.PORTRAIT_SIZE.x * PORTRAIT_SCALE + 28,
		ProceduralCharacterSprite.PORTRAIT_SIZE.y * PORTRAIT_SCALE + 28
	)
	_dna_glow = PanelContainer.new()
	_dna_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(ACCENT, 0.35)
	glow_style.set_corner_radius_all(16)
	glow_style.set_expand_margin_all(0)
	_dna_glow.add_theme_stylebox_override("panel", glow_style)
	glow_wrap.add_child(_dna_glow)

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_CENTER)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.055, 0.075, 0.95)
	style.set_border_width_all(1)
	style.border_color = ACCENT * Color(1, 1, 1, 0.5)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	frame.add_theme_stylebox_override("panel", style)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(
		ProceduralCharacterSprite.PORTRAIT_SIZE * PORTRAIT_SCALE
	)
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Pixel art must not blur when scaled up.
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.add_child(_portrait)
	glow_wrap.add_child(frame)
	inner.add_child(glow_wrap)

	_class_name_label = _title_label("", 20)
	inner.add_child(_class_name_label)

	_class_detail = _muted_label("")
	_class_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_class_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_class_detail)
	inner.add_child(_accent_separator())

	# The DNA moment (see HeroDna/docs/concept/dna.md): rarity + trait name +
	# best-fit class, so a rare/legendary roll is visibly an event, not a
	# number buried in a stat sheet.
	_dna_detail = _muted_label("")
	_dna_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dna_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_dna_detail)

	_reroll_button = _menu_button("Reroll DNA", func(): _reroll_dna())
	inner.add_child(_reroll_button)
	return col


## The class picker, now a horizontal strip of small icon cards sitting
## directly above the portrait it dresses -- each icon is a genuine mini
## rendering of that class's own look (same portrait generator, that
## class's own default appearance), not a generic placeholder glyph, so
## picking a class previews it even before it's selected. A small star
## badge lights up on whichever class the CURRENT DNA roll resonates with
## best (see _refresh_dna/HeroDna.resonance) -- DNA influencing the class
## picker itself, not just a stat line underneath it.
func _build_class_icon_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for archetype in _archetypes.archetype_names():
		var card := _build_class_card(archetype)
		_class_buttons[archetype] = card
		row.add_child(card)
	return row


func _build_appearance_column() -> Control:
	var col := _card_panel(Vector2(230, 0))
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	col.add_child(inner)
	inner.add_child(_section_label("APPEARANCE"))

	for axis in HeroAppearance.AXES:
		inner.add_child(_build_axis_row(axis))
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


# -- skills tab ----------------------------------------------------------
#
# Reported: "there should be tabs with character and skilltree so you can
# view each classes skills before creating". SkillTree (skill_tree.gd) is
# currently one small pool SHARED by every class (see docs/progress.md's
# Soft Class System row: "Full skill-web pathing ... still to come") --
# there is no per-class skill web to preview yet. Rather than fabricate one,
# this tab shows the real shared pool, plus the picked class's own starting
# stat lens restated as a stat card, and highlights which shared nodes
# actually synergize with that class's strongest stat (see
# _class_dominant_stat) -- a genuine, honest preview of "what does this
# class get", not a placeholder.

## Maps a stat-lens key (ClassArchetype.stats_for) to the SkillTree node
## stat_name it corresponds to, for synergy highlighting -- the two use
## different vocabularies ("max_stamina" the class bonus vs. "stamina_regen"
## the skill node actually grants) since they're different systems that
## happen to both touch stamina.
const _CLASS_STAT_TO_SKILL_STAT := {
	"max_health": "max_health",
	"attack_damage": "attack_damage",
	"max_stamina": "stamina_regen",
	# max_mana has no corresponding skill node yet -- a mage-leaning genome
	# simply has no shared-pool node to highlight, which is honest rather
	# than forcing a false match.
}


func _build_skills_tab() -> Control:
	var col := VBoxContainer.new()
	col.name = "Skills"
	col.add_theme_constant_override("separation", 10)

	_skills_class_label = _title_label("", 18)
	_skills_class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(_skills_class_label)

	_skills_summary_label = _muted_label("")
	_skills_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_skills_summary_label)
	col.add_child(_separator())

	col.add_child(_section_label("SHARED SKILL POOL"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for node_id in _skill_tree.node_ids():
		var card := _build_skill_node_card(node_id)
		_skill_node_cards[node_id] = card
		grid.add_child(card)
	scroll.add_child(grid)
	col.add_child(scroll)

	var footer := _muted_label(
		"Every class currently draws from this same shared pool -- full class-specific skill webs are still in development."
	)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(footer)
	return col


## One skill node as a small card: its name, what it grants, and its point
## cost -- _refresh_skills_tab repaints the border/background of whichever
## cards synergize with the currently picked class.
func _build_skill_node_card(node_id: String) -> PanelContainer:
	var card := _card_panel(Vector2(160, 64))
	var info := _skill_tree.node_info(node_id)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	card.add_child(inner)

	var title := Label.new()
	title.text = _skill_node_display_name(node_id)
	title.add_theme_font_size_override("font_size", 13)
	inner.add_child(title)

	var detail := _muted_label(
		"%s +%s" % [_STAT_ABBREVIATIONS.get(info.get("stat_name", ""), info.get("stat_name", "")), _format_number(info.get("bonus_amount", 0.0))]
	)
	detail.add_theme_font_size_override("font_size", 11)
	inner.add_child(detail)

	var cost := _muted_label("Cost: %d pt" % int(info.get("point_cost", 0)))
	cost.add_theme_font_size_override("font_size", 11)
	inner.add_child(cost)
	return card


## "vitality_1" -> "Vitality I". Falls back to a plain capitalized id for
## anything that doesn't fit the "<name>_<tier>" shape.
func _skill_node_display_name(node_id: String) -> String:
	const ROMAN := {"1": "I", "2": "II", "3": "III", "4": "IV", "5": "V"}
	var parts := node_id.split("_")
	if parts.size() == 2 and ROMAN.has(parts[1]):
		return "%s %s" % [parts[0].capitalize(), ROMAN[parts[1]]]
	return node_id.capitalize()


func _format_number(value: Variant) -> String:
	var as_float := float(value)
	return str(int(as_float)) if as_float == floor(as_float) else str(as_float)


## The one stat this class's own bonus lens favors most (ties broken by
## dictionary order) -- used to highlight which shared skill nodes actually
## synergize with the picked class. A class with no positive bonus anywhere
## (shouldn't happen for any real archetype) highlights nothing.
func _class_dominant_stat(archetype: String) -> String:
	var stats: Dictionary = _archetypes.stats_for(archetype)
	var best_stat := ""
	var best_value := 0.0
	for stat_name in stats:
		var value: float = stats[stat_name]
		if value > best_value:
			best_value = value
			best_stat = stat_name
	return best_stat


## Refreshes the skills tab for whichever class is currently selected --
## called from _select_class, so switching classes updates the preview live,
## before the player commits.
func _refresh_skills_tab() -> void:
	if _skills_class_label == null:
		return
	_skills_class_label.text = "%s Skills" % _selected_class.capitalize()
	_skills_summary_label.text = CLASS_BLURBS.get(_selected_class, "")

	var dominant := _class_dominant_stat(_selected_class)
	var synergy_skill_stat: String = _CLASS_STAT_TO_SKILL_STAT.get(dominant, "")
	for node_id in _skill_node_cards:
		var card: PanelContainer = _skill_node_cards[node_id]
		var style: StyleBoxFlat = card.get_theme_stylebox("panel")
		var node_stat: String = _skill_tree.node_info(node_id).get("stat_name", "")
		var synergizes := synergy_skill_stat != "" and node_stat == synergy_skill_stat
		style.bg_color = CARD_BG_SELECTED if synergizes else CARD_BG
		style.border_color = ACCENT if synergizes else PANEL_BORDER


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
	return _appearance_maker.appearance_from_choices(_selected_class, _choices, _dna_seed)


## The rolled genome for the creator's current DNA seed (see HeroDna.roll) --
## handed to World on Begin alongside the appearance it was also derived
## from.
func current_dna() -> Dictionary:
	return _dna.roll(_dna_seed)


func _refresh_appearance() -> void:
	var appearance := current_appearance()
	if _portrait != null:
		_portrait.texture = _char_sprite.generate_hero_portrait_texture(appearance)
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
	_update_dna_glow(genome.rarity)
	_update_resonance_badges(genome.resonance)


## The glow color/rarity pairing for _update_dna_glow -- common stays a
## quiet accent glow (barely different from the frame's own border), rare
## turns a cool blue, legendary a vivid gold that also pulses (see
## _update_dna_glow) -- so rarity is felt at a glance, not just read.
const RARITY_GLOW_COLORS := {
	HeroDna.RARITY_COMMON: ACCENT,
	HeroDna.RARITY_RARE: Color(0.4, 0.6, 0.95),
	HeroDna.RARITY_LEGENDARY: Color(1.0, 0.83, 0.25),
}


## Repaints the glow ring behind the portrait to the rolled genome's rarity
## color, and -- only for legendary, the genuinely rare "awesome, nice"
## moment (see HeroDna) -- sets it gently pulsing rather than static, so a
## legendary roll is unmistakably a different, more exciting event than a
## common one even before reading a word of the DNA readout.
func _update_dna_glow(rarity: String) -> void:
	if _dna_glow == null:
		return
	if _dna_glow_tween != null:
		_dna_glow_tween.kill()
	var style := _dna_glow.get_theme_stylebox("panel") as StyleBoxFlat
	var color: Color = RARITY_GLOW_COLORS.get(rarity, ACCENT)
	style.bg_color = Color(color, 0.35)
	_dna_glow.modulate = Color(1, 1, 1, 1)
	if rarity == HeroDna.RARITY_LEGENDARY:
		_dna_glow_tween = create_tween()
		_dna_glow_tween.set_loops()
		_dna_glow_tween.tween_property(_dna_glow, "modulate:a", 0.55, 0.7).set_trans(Tween.TRANS_SINE)
		_dna_glow_tween.tween_property(_dna_glow, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


## Lights up the "★" badge on whichever class icon the CURRENT DNA roll
## resonates with most (see HeroDna.resonance) -- DNA visibly steering the
## class picker itself, not just a number in a stat readout underneath it.
func _update_resonance_badges(resonance: Dictionary) -> void:
	var best_archetype := ""
	var best_value := -1.0
	for archetype in resonance:
		var value: float = resonance[archetype]
		if value > best_value:
			best_value = value
			best_archetype = archetype
	for archetype in _resonance_badges:
		var badge: Label = _resonance_badges[archetype]
		badge.visible = archetype == best_archetype


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
		"trim":
			var trim_index := maxi(HeroAppearance.TRIM_COLORS.find(appearance.trim), 0)
			return HeroAppearance.TRIM_NAMES[trim_index]
		_:
			var count := _appearance_maker.option_count(axis)
			var indices := _appearance_maker.choices_from_appearance(appearance)
			return "%d / %d" % [int(indices.get(axis, 0)) + 1, count]


func _select_class(archetype: String) -> void:
	_selected_class = archetype
	var stats: Dictionary = _archetypes.stats_for(archetype)
	_class_name_label.text = archetype.capitalize()
	_class_detail.text = "%s\n\nHP %+d   ATK %+d\nMana %+d   Stam %+d" % [
		CLASS_BLURBS.get(archetype, archetype),
		int(stats.get("max_health", 0.0)),
		int(stats.get("attack_damage", 0.0)),
		int(stats.get("max_mana", 0.0)),
		int(stats.get("max_stamina", 0.0)),
	]
	# Highlight the picked class card; dim the rest. (Loop var deliberately
	# not called `name` -- that shadows Node.name on this PanelContainer.)
	for class_id in _class_buttons:
		var card: PanelContainer = _class_buttons[class_id]
		var style: StyleBoxFlat = card.get_theme_stylebox("panel")
		style.bg_color = CARD_BG_SELECTED if class_id == archetype else CARD_BG
		style.border_color = ACCENT if class_id == archetype else PANEL_BORDER
		card.modulate = Color(1, 1, 1) if class_id == archetype else Color(1, 1, 1, 0.7)
	_refresh_appearance()
	_refresh_skills_tab()


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
	l.add_theme_color_override("font_color", ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## A section header with a thin accent underline -- previously just a dim
## 12pt label, which read as an afterthought rather than a real heading.
func _section_label(text: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", ACCENT)
	col.add_child(l)
	var rule := HSeparator.new()
	rule.add_theme_color_override("separator_color", Color(ACCENT, 0.4))
	col.add_child(rule)
	return col


func _muted_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.7)
	return l


func _separator() -> Control:
	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.25)
	return sep


## A separator tinted with the shared accent colour, for the creator
## screen's own major section breaks (between the title and the tabs, and
## between the tabs and the Back/Begin row) -- a plain grey line there read
## as an unstyled default rather than a deliberate divide.
func _accent_separator() -> Control:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator_color", Color(ACCENT, 0.5))
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


## A dark, bordered PanelContainer -- the one card style every section of the
## creator (class list, portrait, appearance, skills) shares, so the screen
## reads as one deliberately designed surface instead of default-grey
## Controls floating in empty space (reported: "it looks poor and not
## detailed/fleshed out"). Each call gets its OWN StyleBoxFlat instance
## (never a shared resource) since _select_class mutates a class card's
## style in place to highlight it.
func _card_panel(min_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.set_border_width_all(1)
	style.border_color = PANEL_BORDER
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	return panel


## One class in the CLASS column: a selectable card (icon-free for now --
## see the illustrated-art brief for a future class icon) rather than a bare
## text Button, so picking a class feels like choosing a card, not clicking
## a menu item. Selection state itself is applied by _select_class, which
## repaints every card's style each time the class changes.
const _CLASS_ICON_SIZE := 56.0


## One class as a small square icon card: a mini rendering of that class's
## own default look (not a generic glyph -- literally the same portrait
## generator, so the icon IS a tiny preview of picking it) plus a
## bottom-corner name-initial isn't needed since the tooltip carries the
## full name. A hidden "★" resonance badge (see _refresh_dna) sits in the
## top-right corner, shown only for whichever class the rolled DNA favors
## most.
func _build_class_card(archetype: String) -> PanelContainer:
	var card := _card_panel(Vector2(_CLASS_ICON_SIZE, _CLASS_ICON_SIZE))
	# Icon cards get a tighter margin than the default card padding -- the
	# portrait should fill almost the whole tile, not sit in a wide mat.
	(card.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 4
	(card.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 4
	(card.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_top = 4
	(card.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_bottom = 4
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "%s\n%s" % [archetype.capitalize(), CLASS_BLURBS.get(archetype, "")]

	var icon := TextureRect.new()
	icon.texture = _class_icon_texture(archetype)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)

	var badge := Label.new()
	badge.text = "★"
	badge.add_theme_color_override("font_color", ACCENT)
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	card.add_child(badge)
	_resonance_badges[archetype] = badge

	# PanelContainer has no click signal of its own -- a transparent Button
	# on top catches the press without needing its own visible styling.
	var hitbox := Button.new()
	hitbox.flat = true
	hitbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hitbox.pressed.connect(func(): _select_class(archetype))
	card.add_child(hitbox)
	return card


## That class's own default look (seed 0, its own palette), rendered once
## and cached -- the icon row's whole point is "the icon IS a tiny preview",
## so it has to be a real portrait, not a placeholder glyph.
func _class_icon_texture(archetype: String) -> ImageTexture:
	if not _class_icon_textures.has(archetype):
		_class_icon_textures[archetype] = _char_sprite.generate_hero_portrait_texture(
			_appearance_maker.appearance_for(archetype, 0)
		)
	return _class_icon_textures[archetype]


## Themes Godot's default (flat grey) TabContainer to match the rest of the
## screen: a dark bordered panel body and the shared accent colour on the
## selected tab, rather than the stock light-grey tab strip.
func _style_tabs(tabs: TabContainer) -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BG
	panel_style.set_border_width_all(1)
	panel_style.border_color = PANEL_BORDER
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(14)
	tabs.add_theme_stylebox_override("panel", panel_style)

	var selected := StyleBoxFlat.new()
	selected.bg_color = CARD_BG_SELECTED
	selected.set_corner_radius_all(4)
	selected.content_margin_left = 14
	selected.content_margin_right = 14
	selected.content_margin_top = 6
	selected.content_margin_bottom = 6
	tabs.add_theme_stylebox_override("tab_selected", selected)

	var unselected := StyleBoxFlat.new()
	unselected.bg_color = Color(1, 1, 1, 0.04)
	unselected.set_corner_radius_all(4)
	unselected.content_margin_left = 14
	unselected.content_margin_right = 14
	unselected.content_margin_top = 6
	unselected.content_margin_bottom = 6
	tabs.add_theme_stylebox_override("tab_unselected", unselected)

	tabs.add_theme_color_override("font_selected_color", ACCENT)
	tabs.add_theme_color_override("font_unselected_color", Color(1, 1, 1, 0.6))


func _show(screen: Control) -> void:
	for s in [_root_screen, _create_screen, _join_screen]:
		s.visible = s == screen


## Called by World to hide the menu once a game has started.
func close() -> void:
	visible = false
