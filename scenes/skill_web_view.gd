extends Control

## The graph view of the passive web (docs/concept/skills.md) -- pan with a drag,
## zoom on the wheel, click a node to inspect or take it.
##
## Everything a player can misread lives here as pure logic rather than inside
## _draw(): which node is under the cursor (node_at), whether it is takeable or
## merely unaffordable (state_of -- two different answers a single "greyed out"
## cannot tell apart), and what it costs THIS character once resonance and DNA
## flavour are applied (node_label). _draw only paints what those already decided.
##
## Colours are DERIVED, not tabled: a wedge's hue is its index around the circle,
## exactly as its angle is (see wedge_color), so adding an eighth archetype
## recolours the map correctly with no palette to update.

const SkillWeb = preload("res://src/gameplay/skill_web.gd")
const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")
const SkillTreeWindow = preload("res://scenes/skill_tree_window.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const KeystonePassive = preload("res://src/gameplay/keystone_passive.gd")

## Emitted when the player clicks a node they can actually take. Inspection
## (selected_node_id) happens for any node, including locked ones.
signal node_clicked(node_id: String)
## Free respec (docs/concept/classes.md) needs a gesture on the map itself.
## Right-click is the one that cannot be mistaken for "take this".
signal node_refund_requested(node_id: String)

const STATE_ALLOCATED := "allocated"
const STATE_TAKEABLE := "takeable"
## Reachable and understood, just not paid for yet -- "come back next level",
## which is a different message from STATE_LOCKED's "walk over there first".
const STATE_UNAFFORDABLE := "unaffordable"
const STATE_LOCKED := "locked"

const MIN_ZOOM := 0.35
const MAX_ZOOM := 2.5
const ZOOM_STEP := 1.15

## Drawn radius per node kind, in world units. A keystone has to read as the end
## of a road at a glance, which is size, not colour.
const NODE_RADIUS := {
	SkillWeb.KIND_START: 15.0,
	SkillWeb.KIND_MINOR: 7.0,
	SkillWeb.KIND_NOTABLE: 11.0,
	SkillWeb.KIND_KEYSTONE: 16.0,
	SkillWeb.KIND_GATEWAY: 9.0,
	SkillWeb.KIND_SIGNATURE: 13.0,
}
const DEFAULT_NODE_RADIUS := 8.0

## Extra slack around a node's drawn radius when hit-testing, in view pixels --
## a 7px minor node is a hard target with a mouse and an impossible one on a
## trackpad without it.
const HIT_PADDING := 6.0

## Opacity per state. Allocated is fully lit; locked is present but clearly
## inert, never invisible -- you cannot plan a route through a map that hides
## the parts you have not reached.
const STATE_ALPHA := {
	STATE_ALLOCATED: 1.0,
	STATE_TAKEABLE: 0.85,
	STATE_UNAFFORDABLE: 0.5,
	STATE_LOCKED: 0.28,
}

## Zoom at or above which the small nodes get named too. Naming all 84 at once
## is an unreadable thicket at any distance; the big ones stay named always
## (they are the landmarks you navigate by) and the rest appear as you lean in,
## which is also when there is room for them.
const MINOR_LABEL_ZOOM := 1.0

## Node kinds that always carry their name on the map -- the landmarks. A
## gateway is deliberately absent: "gateway_mage_ranger" is not a name anyone
## needs, and seven of them crowding the centre would bury the wedge names.
const ALWAYS_LABELLED := [
	SkillWeb.KIND_START, SkillWeb.KIND_NOTABLE, SkillWeb.KIND_KEYSTONE,
	SkillWeb.KIND_SIGNATURE,
]

const EDGE_WIDTH := 2.0
const EDGE_COLOR := Color(0.55, 0.58, 0.66, 0.35)
const EDGE_COLOR_LIVE := Color(0.95, 0.88, 0.6, 0.9)
const GATEWAY_HUE_COLOR := Color(0.72, 0.74, 0.78)
const SELECTION_COLOR := Color(1.0, 1.0, 1.0, 0.9)
## The previewed route to whatever is hovered but not yet reachable.
const ROUTE_COLOR := Color(1.0, 0.85, 0.35, 0.95)
const ROUTE_WIDTH := 3.0
const LABEL_COLOR := Color(0.92, 0.93, 0.96, 0.85)
const WEDGE_LABEL_SIZE := 22
const NODE_LABEL_SIZE := 12
const TOOLTIP_PAD := 8.0
const TOOLTIP_LINE_HEIGHT := 17.0
const TOOLTIP_BG := Color(0.08, 0.09, 0.12, 0.97)
const TOOLTIP_BORDER := Color(0.45, 0.47, 0.56, 0.95)

## World point sitting at the centre of the view.
var pan := Vector2.ZERO
var zoom := 1.0
var selected_node_id := ""
## What the cursor is over right now, and the cheapest route to it when it is
## something the player cannot yet reach (see SkillWeb.cheapest_path). Both are
## recomputed on hover rather than every frame.
var hovered_node_id := ""
var preview_path: Array = []
var _hover_point := Vector2.ZERO

var _web: SkillWeb
## The four legacy keystones' own required_node_count floor (docs/concept/
## skills.md "a keystone is the end of a real investment") -- a fixed rules
## table, not per-character config, so it is built once rather than on every
## state_of() call.
var _keystones := KeystonePassive.new()
var _archetype := ""
var _resonance: Dictionary = {}
var _dna_seed := 0
var _allocated: Dictionary = {}
var _unspent_points := 0
var _dragging := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


## Points this view at one character's web. `resonance` is HeroDna.roll()'s
## per-archetype map and `dna_seed` its seed -- both are read for every label, so
## the numbers on screen are the ones this character will actually be charged.
func configure(web: SkillWeb, archetype: String, resonance: Dictionary, dna_seed: int) -> void:
	_web = web
	_archetype = archetype
	_resonance = resonance
	_dna_seed = dna_seed
	queue_redraw()


func set_allocation(allocated: Dictionary, unspent_points: int) -> void:
	_allocated = allocated
	_unspent_points = unspent_points
	queue_redraw()


# --- projection -----------------------------------------------------------

func world_to_view(world: Vector2) -> Vector2:
	return (world - pan) * zoom + size * 0.5


func view_to_world(view_point: Vector2) -> Vector2:
	return (view_point - size * 0.5) / zoom + pan


## Zooms about `view_anchor`, keeping whatever world point sits under it fixed --
## the map moves under a still finger rather than teleporting.
func set_zoom_at(new_zoom: float, view_anchor: Vector2) -> void:
	var anchored := view_to_world(view_anchor)
	zoom = clampf(new_zoom, MIN_ZOOM, MAX_ZOOM)
	pan = anchored - (view_anchor - size * 0.5) / zoom
	queue_redraw()


func focus_on(node_id: String) -> void:
	if _web == null or not _web.has(node_id):
		return
	pan = _web.position_of(node_id)
	queue_redraw()


## Margin left around a framed wedge, as a fraction of the viewport. Nodes are
## drawn as circles with labels that overhang their own centre, so framing the
## bare bounding box would clip the outermost ring's art even though every node
## CENTRE was technically inside. Pinned by
## test_framing_fits_the_whole_wedge_inside_the_view, which checks the node
## positions actually land on screen rather than checking this number.
const FRAME_MARGIN := 0.12


## Parks the view on ONE archetype's wedge: centred on it, zoomed so the whole
## wedge fits.
##
## The character creator shows this view inside a dialog tab for the single
## class being picked (see MainMenu._build_skills_tab). At that size the full
## seven-wedge wheel is a smudge and six sevenths of it is somebody else's
## class, so the view has to be able to park itself without the player panning
## there by hand.
##
## Zoom is DERIVED from the wedge's real bounds against the real viewport, not
## chosen: the layout constants (RING_STEP, WEDGE_COUNT, OUTER_RING) and the
## panel size both move, and a hand-picked zoom would silently stop fitting the
## moment either did. Clamped to the same MIN_ZOOM/MAX_ZOOM the wheel obeys, so
## a framed view is one the player can carry on driving.
func frame_archetype(archetype: String) -> void:
	if _web == null:
		return
	var bounds: Rect2 = _web.archetype_bounds(archetype)
	if bounds.size.x <= 0.0 and bounds.size.y <= 0.0:
		return
	var usable := size * (1.0 - FRAME_MARGIN)
	var fit_x := usable.x / bounds.size.x if bounds.size.x > 0.0 else MAX_ZOOM
	var fit_y := usable.y / bounds.size.y if bounds.size.y > 0.0 else MAX_ZOOM
	pan = bounds.get_center()
	zoom = clampf(minf(fit_x, fit_y), MIN_ZOOM, MAX_ZOOM)
	queue_redraw()


# --- hit testing ----------------------------------------------------------

## The node under `view_point`, or "" for open space. Picks the NEAREST
## candidate, so overlapping hit circles never hand the click to whichever node
## the table happened to list first.
func node_at(view_point: Vector2) -> String:
	if _web == null:
		return ""
	var best := ""
	var best_distance := INF
	for node_id in _web.node_ids():
		var centre := world_to_view(_web.position_of(node_id))
		var distance := centre.distance_to(view_point)
		if distance > radius_of(node_id) * zoom + HIT_PADDING:
			continue
		if distance < best_distance:
			best_distance = distance
			best = node_id
	return best


func radius_of(node_id: String) -> float:
	if _web == null or not _web.has(node_id):
		return DEFAULT_NODE_RADIUS
	return float(NODE_RADIUS.get(_web.node_info(node_id)["kind"], DEFAULT_NODE_RADIUS))


# --- state ----------------------------------------------------------------

func state_of(node_id: String) -> String:
	if _web == null or not _web.has(node_id):
		return STATE_LOCKED
	if _allocated.get(node_id, false):
		return STATE_ALLOCATED
	if not _web.is_reachable(node_id, _allocated, _archetype):
		return STATE_LOCKED
	if _web.node_info(node_id)["kind"] == SkillWeb.KIND_KEYSTONE:
		# Path adjacency alone can satisfy this well before the keystone's own
		# required_node_count floor does -- a cheap gateway hop can make a
		# neighbouring wedge's keystone reachable and affordable on far fewer
		# total nodes than the keystone itself demands. Player.unlock_keystone
		# already refuses that (KeystonePassive.can_unlock), so reporting
		# TAKEABLE here would light up a node whose click does nothing -- it
		# is really LOCKED for a different reason. Non-legacy keystone-ring
		# nodes (e.g. archmage) carry no such floor and fall through untouched.
		var gate := _keystones.keystone_info(node_id)
		if not gate.is_empty() and not _keystones.can_unlock(node_id, _allocated.size()):
			return STATE_LOCKED
	if _web.point_cost(node_id, _resonance) > _unspent_points:
		return STATE_UNAFFORDABLE
	return STATE_TAKEABLE


# --- labelling ------------------------------------------------------------

## Hue is the wedge's own index around the circle, the same way its angle is --
## so the map's colour and its geometry can never disagree.
func wedge_color(wedge_index: int) -> Color:
	return Color.from_hsv(float(wedge_index) / float(SkillWeb.WEDGE_COUNT), 0.55, 0.95)


func node_color(node_id: String) -> Color:
	if _web == null or not _web.has(node_id):
		return Color(0, 0, 0, 0)
	var info := _web.node_info(node_id)
	var base := GATEWAY_HUE_COLOR
	if info["kind"] != SkillWeb.KIND_GATEWAY:
		base = wedge_color(int(info["wedge_index"]))
	if info["kind"] == SkillWeb.KIND_SIGNATURE:
		# The one node nobody else has reads as gold rather than as more of its
		# wedge's hue -- see docs/concept/skills.md "The genome net".
		base = base.lerp(Color(1.0, 0.85, 0.35), 0.7)
	base.a = float(STATE_ALPHA.get(state_of(node_id), STATE_ALPHA[STATE_LOCKED]))
	return base


## What the player reads on hover: the node's name, what it grants THEM (DNA
## flavour resolved, resonance applied) and what it costs THEM. A reveal node
## (empty stat_name, e.g. land_sense) shows its real description instead of a
## "+0" that would be a lie -- the same special case SkillTreeWindow already
## makes for the list.
func node_label(node_id: String) -> String:
	if _web == null or not _web.has(node_id):
		return ""
	var info := _web.node_info(node_id)
	var title := String(info.get("description", ""))
	if info["kind"] == SkillWeb.KIND_KEYSTONE:
		title = SkillTreeWindow.keystone_title(node_id)
	elif info["kind"] != SkillWeb.KIND_GATEWAY and info["kind"] != SkillWeb.KIND_SIGNATURE:
		title = SkillTreeWindow.node_title(node_id)
	var cost := "%d pt" % _web.point_cost(node_id, _resonance)
	if String(info["stat_name"]) == "":
		return "%s — %s (%s)" % [title, String(info.get("description", "")), cost]
	var variant := _web.flavored_variant(node_id, _dna_seed)
	var amount := _web.effective_bonus(node_id, _resonance)
	return "%s   +%s %s (%s)" % [
		title, String.num(amount, 1).trim_suffix(".0"),
		SkillTreeWindow.stat_label(String(variant["stat_name"])), cost]


## Full hover text for `node_id`, one entry per line. Empty for an unknown node.
##
## Everything here is resolved for THIS character -- the DNA-chosen variant, the
## resonance-scaled bonus, the resonance-scaled price -- because a tooltip
## quoting the table's numbers instead of the player's own would be worse than
## no tooltip at all.
func node_tooltip(node_id: String) -> Array:
	if _web == null or not _web.has(node_id):
		return []
	var info := _web.node_info(node_id)
	var kind := String(info["kind"])
	var lines := [_title_of(node_id, info)]

	if kind == SkillWeb.KIND_GATEWAY:
		lines.append("Gateway between two wedges")
	else:
		lines.append("%s %s" % [String(info["archetype"]).capitalize(), kind])

	if String(info["stat_name"]) == "":
		var described := String(info.get("description", ""))
		if described != "":
			lines.append(described)
	else:
		var variant := _web.flavored_variant(node_id, _dna_seed)
		lines.append("+%s %s" % [
			String.num(_web.effective_bonus(node_id, _resonance), 1).trim_suffix(".0"),
			SkillTreeWindow.stat_label(String(variant["stat_name"]))])

	match state_of(node_id):
		STATE_ALLOCATED:
			lines.append("Owned — right-click to refund")
		STATE_TAKEABLE:
			lines.append("%d points — click to take" % _web.point_cost(node_id, _resonance))
		STATE_UNAFFORDABLE:
			lines.append("%d points — you have %d" % [
				_web.point_cost(node_id, _resonance), _unspent_points])
		_:
			var route := _route_to(node_id)
			lines.append("%d points to reach, %d nodes away" % [
				_web.route_cost(route, _resonance), route.size()])

	if not (info["variants"] as Array).is_empty():
		lines.append("This node\'s effect was chosen by your DNA")
	if kind == SkillWeb.KIND_SIGNATURE:
		lines.append("From your own genome — nobody else has this node")
	return lines


## A node's display name. Keystones carry a written name, signature nodes carry
## their generated one, everything else derives from its id.
func _title_of(node_id: String, info: Dictionary) -> String:
	var kind := String(info["kind"])
	if kind == SkillWeb.KIND_KEYSTONE:
		return SkillTreeWindow.keystone_title(node_id)
	if kind == SkillWeb.KIND_SIGNATURE or kind == SkillWeb.KIND_GATEWAY:
		return String(info.get("description", node_id))
	return SkillTreeWindow.node_title(node_id)


func _route_to(node_id: String) -> Array:
	if _web == null or _allocated.get(node_id, false):
		return []
	return _web.cheapest_path(node_id, _allocated, _archetype, _resonance)


## Records what the cursor is over and, for anything out of reach, works out the
## route there -- which is the actual answer to "what do these paths do".
func hover_at(view_point: Vector2) -> void:
	var node_id := node_at(view_point)
	_hover_point = view_point
	if node_id == hovered_node_id:
		return
	hovered_node_id = node_id
	preview_path = [] if node_id == "" or state_of(node_id) != STATE_LOCKED else _route_to(node_id)
	queue_redraw()


## `wedge_index`'s archetype, in words, for the name painted across its slice of
## the map -- the thing whose absence made it "unclear what paths do what".
func wedge_label(wedge_index: int) -> String:
	var archetypes := ClassArchetype.new().archetype_names()
	if wedge_index < 0 or wedge_index >= archetypes.size():
		return ""
	return String(archetypes[wedge_index]).capitalize()


func map_label(node_id: String) -> String:
	if _web == null or not _web.has(node_id):
		return ""
	return _title_of(node_id, _web.node_info(node_id))


## Whether `node_id`'s name is painted on the map at the current zoom.
func shows_label(node_id: String) -> bool:
	if _web == null or not _web.has(node_id):
		return false
	var kind := String(_web.node_info(node_id)["kind"])
	if kind == SkillWeb.KIND_GATEWAY:
		return false
	if ALWAYS_LABELLED.has(kind):
		return true
	return zoom >= MINOR_LABEL_ZOOM


# --- interaction ----------------------------------------------------------

## Selects whatever is under `view_point` (any node -- inspecting a locked node
## is how a route gets planned) and emits it if it is actually takeable.
func click_at(view_point: Vector2) -> void:
	var node_id := node_at(view_point)
	if node_id == "":
		return
	selected_node_id = node_id
	queue_redraw()
	if state_of(node_id) == STATE_TAKEABLE:
		node_clicked.emit(node_id)


## Asks to give `view_point`'s node back, if the player owns it. Selecting it
## first mirrors click_at, so the detail panel is showing what is about to go.
func right_click_at(view_point: Vector2) -> void:
	var node_id := node_at(view_point)
	if node_id == "":
		return
	selected_node_id = node_id
	queue_redraw()
	if state_of(node_id) == STATE_ALLOCATED:
		node_refund_requested.emit(node_id)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			set_zoom_at(zoom * ZOOM_STEP, event.position)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			set_zoom_at(zoom / ZOOM_STEP, event.position)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			right_click_at(event.position)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
			else:
				_dragging = false
				click_at(event.position)
			accept_event()
	elif event is InputEventMouseMotion:
		if _dragging:
			# Dragging moves the world under the cursor 1:1, so the map tracks
			# the mouse exactly regardless of zoom.
			pan -= event.relative / zoom
			hovered_node_id = ""
			preview_path = []
			queue_redraw()
			accept_event()
		else:
			hover_at(event.position)


func _draw() -> void:
	if _web == null:
		return
	var drawn_edges := {}
	for node_id in _web.node_ids():
		var from := world_to_view(_web.position_of(node_id))
		for neighbour in _web.neighbors(node_id):
			# Ordered pair key, so each undirected edge is painted once rather
			# than twice at double opacity.
			var key: String = "%s|%s" % ([node_id, neighbour] if node_id < neighbour else [neighbour, node_id])
			if drawn_edges.has(key):
				continue
			drawn_edges[key] = true
			var live: bool = _allocated.get(node_id, false) and _allocated.get(neighbour, false)
			draw_line(from, world_to_view(_web.position_of(neighbour)),
				EDGE_COLOR_LIVE if live else EDGE_COLOR, EDGE_WIDTH * zoom)

	_draw_route()

	var font := get_theme_default_font()
	for node_id in _web.node_ids():
		var centre := world_to_view(_web.position_of(node_id))
		var radius := radius_of(node_id) * zoom
		draw_circle(centre, radius, node_color(node_id))
		if node_id == selected_node_id or node_id == hovered_node_id:
			draw_arc(centre, radius + 4.0 * zoom, 0.0, TAU, 24, SELECTION_COLOR, 2.0, true)
		elif state_of(node_id) == STATE_TAKEABLE:
			draw_arc(centre, radius + 2.0 * zoom, 0.0, TAU, 20,
				Color(1, 1, 1, 0.55), 1.5, true)
		if font != null and shows_label(node_id):
			var text := map_label(node_id)
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				NODE_LABEL_SIZE).x
			draw_string(font, centre + Vector2(-width * 0.5, radius + NODE_LABEL_SIZE + 2.0),
				text, HORIZONTAL_ALIGNMENT_LEFT, -1, NODE_LABEL_SIZE, LABEL_COLOR)

	_draw_wedge_names(font)
	_draw_tooltip(font)


## The name of each archetype, painted out past its own keystones in its own
## hue. Without these the map is 84 unattributed circles.
func _draw_wedge_names(font: Font) -> void:
	if font == null:
		return
	for wedge_index in SkillWeb.WEDGE_COUNT:
		var text := wedge_label(wedge_index)
		var at := world_to_view(_web.wedge_label_position(wedge_index))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			WEDGE_LABEL_SIZE).x
		var tint := wedge_color(wedge_index)
		tint.a = 0.75
		draw_string(font, at + Vector2(-width * 0.5, 0.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, WEDGE_LABEL_SIZE, tint)


## The previewed route to an out-of-reach node, drawn as a lit chain through the
## nodes you would have to buy -- so "what would it take to get there" is a
## picture, not arithmetic the player has to do themselves.
func _draw_route() -> void:
	if preview_path.size() < 1:
		return
	var previous := ""
	for node_id in preview_path:
		if previous != "":
			draw_line(world_to_view(_web.position_of(previous)),
				world_to_view(_web.position_of(node_id)), ROUTE_COLOR, ROUTE_WIDTH * zoom)
		previous = node_id
	for node_id in preview_path:
		draw_arc(world_to_view(_web.position_of(node_id)),
			radius_of(node_id) * zoom + 3.0 * zoom, 0.0, TAU, 20, ROUTE_COLOR, 2.0, true)


## Drawn last so nothing paints over it, and nudged back inside the view when it
## would otherwise run off the right or bottom edge.
func _draw_tooltip(font: Font) -> void:
	if font == null or hovered_node_id == "":
		return
	var lines := node_tooltip(hovered_node_id)
	if lines.is_empty():
		return
	var width := 0.0
	for line in lines:
		width = maxf(width, font.get_string_size(String(line), HORIZONTAL_ALIGNMENT_LEFT, -1,
			NODE_LABEL_SIZE + 1).x)
	var box := Vector2(width + TOOLTIP_PAD * 2.0,
		float(lines.size()) * TOOLTIP_LINE_HEIGHT + TOOLTIP_PAD * 2.0)
	var at := _hover_point + Vector2(16.0, 16.0)
	at.x = minf(at.x, size.x - box.x)
	at.y = minf(at.y, size.y - box.y)
	at = at.max(Vector2.ZERO)
	draw_rect(Rect2(at, box), TOOLTIP_BG)
	draw_rect(Rect2(at, box), TOOLTIP_BORDER, false, 1.0)
	for index in lines.size():
		var tint := LABEL_COLOR if index > 0 else Color(1.0, 0.88, 0.55, 1.0)
		draw_string(font, at + Vector2(TOOLTIP_PAD,
			TOOLTIP_PAD + TOOLTIP_LINE_HEIGHT * float(index + 1) - 4.0),
			String(lines[index]), HORIZONTAL_ALIGNMENT_LEFT, -1, NODE_LABEL_SIZE + 1, tint)
