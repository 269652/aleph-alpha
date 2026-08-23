extends RefCounted

## A TallGrass cell rendered as several deterministic cards from the illustrated atlas.
const ATLAS_PATH := "res://assets/sprites/grass_blades.png"
## The delivered sheet is 1254×1254 and contains 10×10 blade variants. Its
## source art is roughly 128px per cell; regions derive from its true size.
const ATLAS_COLUMNS := 10
const ATLAS_ROWS := 10
const DEFAULT_ATLAS_SIZE := Vector2i(1254, 1254)
const CARD_COUNT := 4
const WORLD_SIZE := 16.0

const SHADER_CODE := """
shader_type canvas_item;
uniform vec2 player_world_position = vec2(-100000.0);
uniform float walker_radius = 22.0;
uniform float wind_speed = 1.6;
void vertex() {
	float top_weight = 1.0 - UV.y;
	vec2 root = (MODEL_MATRIX * vec4(vec2(0.0), 0.0, 1.0)).xy;
	vec2 from_walker = root - player_world_position;
	float distance_to_walker = length(from_walker);
	vec2 away = from_walker / max(distance_to_walker, 0.001);
	float wake = 1.0 - smoothstep(0.0, walker_radius, distance_to_walker);
	float wind = sin(TIME * wind_speed + root.x * 0.071 + root.y * 0.043) * 1.25;
	VERTEX.x += (wind + away.x * wake * 5.0) * top_weight;
}
"""

var _material: ShaderMaterial
var _texture: Texture2D

static func atlas_region_for_seed(seed_value: int, atlas_size: Vector2i = DEFAULT_ATLAS_SIZE) -> Rect2i:
	var index := posmod(seed_value, ATLAS_COLUMNS * ATLAS_ROWS)
	var column := index % ATLAS_COLUMNS
	var row := index / ATLAS_COLUMNS
	var from := Vector2i(column * atlas_size.x / ATLAS_COLUMNS, row * atlas_size.y / ATLAS_ROWS)
	var to := Vector2i((column + 1) * atlas_size.x / ATLAS_COLUMNS, (row + 1) * atlas_size.y / ATLAS_ROWS)
	return Rect2i(from, to - from)

static func card_specs_for_seed(seed_value: int) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	for index in CARD_COUNT:
		var h := hash("%d_grass_card_%d" % [seed_value, index])
		specs.append({"seed": h, "offset": Vector2(float(posmod(h, 13) - 6) * 0.55, float(posmod(h / 13, 9) - 4) * 0.35), "depth": CARD_COUNT - index})
	return specs

func material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
	return _material

func set_walker_position(world_position: Vector2) -> void:
	material().set_shader_parameter("player_world_position", world_position)

func create_cards(seed_value: int, ground_position: Vector2, parent: Node) -> Array[Sprite2D]:
	if _texture == null:
		_texture = load(ATLAS_PATH) as Texture2D
	var cards: Array[Sprite2D] = []
	if _texture == null:
		push_error("Missing long-grass atlas: %s" % ATLAS_PATH)
		return cards
	for spec in card_specs_for_seed(seed_value):
		var sprite := Sprite2D.new()
		sprite.texture = _texture
		sprite.region_enabled = true
		var region := atlas_region_for_seed(spec.seed, Vector2i(_texture.get_size()))
		sprite.region_rect = region
		sprite.offset = Vector2(0.0, -region.size.y * 0.5)
		# No explicit z-index: the shared y-sorted Entities parent places a
		# card correctly against the player and creatures from its ground root.
		sprite.position = ground_position + spec.offset
		sprite.scale = Vector2.ONE * (WORLD_SIZE / float(region.size.x))
		sprite.material = material()
		parent.add_child(sprite)
		cards.append(sprite)
	return cards
