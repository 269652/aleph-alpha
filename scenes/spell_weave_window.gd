extends PanelContainer
## The surface a player arranges spell motes on (docs/concept/
## spell_weaving.md) -- the authoring half of the Magicraft loop the game
## had every other piece of.
##
## The header is the point. It rewrites itself from the live draft, so the
## consequence of an arrangement is visible BEFORE it is committed: the
## name the atoms earn, what it will cost, and any reaction the current
## ORDER produces. Swapping two motes visibly changes it, which is what
## makes composition a craft rather than a form to fill in.
##
## This window never performs anything. It reports `weave_requested` with
## the draft on screen and `World` hands that to `Player.weave`, which owns
## the two gates (do you own these motes, does the validator accept the
## arrangement) -- the same division ConversationWindow keeps for the give
## verb, and for the same reason: a window that could weave would be a
## second opinion about what a legal spell is.

const SpellDraft = preload("res://src/gameplay/spell_draft.gd")
const SpellMote = preload("res://src/gameplay/spell_mote.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## The player committed the arrangement on screen. Carries the draft
## itself, so World never has to rebuild it from the widgets.
signal weave_requested(draft: Dictionary)

## A mote was clicked in the pouch, to be socketed next.
signal socket_requested(atom_id: String)

## A socketed mote was clicked, to be taken back out.
signal unsocket_requested(socket_index: int)

const WINDOW_SIZE := Vector2(520, 360)
const TITLE := "The Weave"

var _title_label: Label
var _header_label: Label
var _sockets_row: HBoxContainer
var _pouch_label: Label
var _pouch_row: HBoxContainer
var _weave_button: Button

var _motes: Dictionary = {}
var _draft: Dictionary = {}


func _ready() -> void:
	visible = false
	custom_minimum_size = WINDOW_SIZE
	var column := VBoxContainer.new()
	add_child(column)

	_title_label = Label.new()
	_title_label.text = TITLE
	column.add_child(_title_label)

	# The live reading of the current arrangement -- name, cost, delivery,
	# reactions. Wrapping, because a reacting three-mote weave is a
	# sentence, not a chip.
	_header_label = Label.new()
	_header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_header_label)

	_sockets_row = HBoxContainer.new()
	column.add_child(_sockets_row)

	_pouch_label = Label.new()
	column.add_child(_pouch_label)

	_pouch_row = HBoxContainer.new()
	column.add_child(_pouch_row)

	_weave_button = Button.new()
	_weave_button.text = "Weave"
	_weave_button.pressed.connect(request_weave)
	column.add_child(_weave_button)


func toggle() -> void:
	visible = not visible


func is_open() -> bool:
	return visible


## Redraws from the character's own pouch and current draft. Both are
## plain data owned by the Player; this window holds no state of its own
## that could drift from them.
func refresh(motes: Dictionary, draft: Dictionary) -> void:
	_motes = motes.duplicate()
	_draft = draft.duplicate(true)
	_header_label.text = header_text()
	_pouch_label.text = pouch_text()
	_rebuild_sockets()
	_rebuild_pouch()
	_weave_button.disabled = SpellDraft.atoms_of(_draft).is_empty()


## What the current arrangement really is, read live: the name these atoms
## in this order earn, the delivery, the mana it will cost, and every
## reaction the order produces. An empty weave says what to do instead of
## showing a blank.
func header_text() -> String:
	var atoms := SpellDraft.atoms_of(_draft)
	if atoms.is_empty():
		return "Socket a mote to begin. Order matters: what sits beside what is the craft."
	var lines: Array[String] = []
	lines.append(
		"%s  -  %s, %s mana"
		% [
			SpellDraft.name_for(_draft),
			SpellDraft.delivery_of(_draft),
			String.num(SpellDraft.cost_of(_draft), 1).trim_suffix(".0"),
		]
	)
	for reaction in SpellDraft.reactions_of(_draft):
		lines.append(
			"%s: %s" % [String(reaction.get("epithet", "")), _reaction_phrase(reaction)]
		)
	return "\n".join(lines)


## Whether a reaction helps or hinders, in words rather than a factor: a
## player reading a header wants to know if the arrangement is better, not
## to multiply anything.
func _reaction_phrase(reaction: Dictionary) -> String:
	var multiplier := float(reaction.get("multiplier", 1.0))
	if multiplier > 1.0:
		return "these two feed each other"
	if multiplier < 1.0:
		return "these two work against each other"
	return "these two meet"


## The parts this character owns, or an honest line when they own none --
## which is the ordinary state of a new character and should read as a
## thing to go and do, not as an error.
func pouch_text() -> String:
	if _motes.is_empty():
		return "You carry no motes yet. Live through something worth learning."
	# Named and counted in the line itself, not only on the buttons: the
	# pouch is what a player reads to decide what is POSSIBLE before they
	# start dragging, and a row of chips is not a sentence.
	var parts: Array[String] = []
	var atom_ids: Array = _motes.keys()
	atom_ids.sort()
	for atom_id in atom_ids:
		var count := int(_motes[atom_id])
		if count > 0:
			parts.append("%s x%d" % [SpellMote.display_name_for(String(atom_id)), count])
	return "Motes: %s" % ", ".join(parts)


func _rebuild_sockets() -> void:
	for child in _sockets_row.get_children():
		_sockets_row.remove_child(child)
		child.queue_free()
	var atoms := SpellDraft.atoms_of(_draft)
	for index in SpellDraft.MAX_SOCKETS:
		var button := Button.new()
		if index < atoms.size():
			button.text = SpellMote.display_name_for(String(atoms[index]))
			var slot := index
			button.pressed.connect(func(): unsocket_requested.emit(slot))
		else:
			button.text = "-"
			button.disabled = true
		_sockets_row.add_child(button)


func _rebuild_pouch() -> void:
	for child in _pouch_row.get_children():
		_pouch_row.remove_child(child)
		child.queue_free()
	var atom_ids: Array = _motes.keys()
	atom_ids.sort()
	for atom_id in atom_ids:
		var count := int(_motes[atom_id])
		if count <= 0:
			continue
		var button := Button.new()
		button.text = "%s x%d" % [SpellMote.display_name_for(String(atom_id)), count]
		var id := String(atom_id)
		button.pressed.connect(func(): socket_requested.emit(id))
		_pouch_row.add_child(button)


## Commits the arrangement on screen. An empty weave asks for nothing --
## there is no spell there to make, and a button that fires on nothing
## teaches a player that buttons lie.
func request_weave() -> void:
	if SpellDraft.atoms_of(_draft).is_empty():
		return
	weave_requested.emit(_draft.duplicate(true))
