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
const SkillTreeWindow = preload("res://scenes/skill_tree_window.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

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

const EDGE_WIDTH := 2.0
const EDGE_COLOR := Color(0.55, 0.58, 0.66, 0.35)
const EDGE_COLOR_LIVE := Color(0.95, 0.88, 0.6, 0.9)
const GATEWAY_HUE_COLOR := Color(0.72, 0.74, 0.78)
const SELECTION_COLOR := Color(1.0, 1.0, 1.0, 0.9)

## World point sitting at the centre of the view.
var pan := Vector2.ZERO
var zoom := 1.0
var selected_node_id := ""

var _web: SkillWeb
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
	elif event is InputEventMouseMotion and _dragging:
		# Dragging moves the world under the cursor 1:1, so the map tracks the
		# mouse exactly regardless of zoom.
		pan -= event.relative / zoom
		queue_redraw()
		accept_event()


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

	for node_id in _web.node_ids():
		var centre := world_to_view(_web.position_of(node_id))
		var radius := radius_of(node_id) * zoom
		draw_circle(centre, radius, node_color(node_id))
		if node_id == selected_node_id:
			draw_arc(centre, radius + 4.0 * zoom, 0.0, TAU, 24, SELECTION_COLOR, 2.0, true)
		elif state_of(node_id) == STATE_TAKEABLE:
			draw_arc(centre, radius + 2.0 * zoom, 0.0, TAU, 20,
				Color(1, 1, 1, 0.55), 1.5, true)
