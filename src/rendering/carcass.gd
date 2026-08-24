extends Node2D

## A killed animal's remains -- see docs/concept/carrion.md. Replaces the old
## "die and instantly drop loot" model (CreatureMarker._drop_loot): the
## marker frees itself and this spawns in its place, holding real parts
## (hide/meat/guts) a player butchers by hand, one swing at a time, mirroring
## SmashableStone's "N hits, N states" shape. Rots on its own clock,
## independent of butchering, so decomposers can eventually finish it off
## whether or not the player ever touches it.

const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const ProceduralCarcassSprite = preload("res://src/rendering/procedural_carcass_sprite.gd")
const CarcassGuts = preload("res://src/rendering/carcass_guts.gd")
const Butchering = preload("res://src/gameplay/butchering.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const DiseaseModel = preload("res://src/gameplay/disease_model.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")

const GROUP_NAME := "carcass"

## How long an untouched carcass stays "fresh" before decomposers can start
## eating it. Deliberately NOT FruitSpoilage's real-day-compressed timescale
## (a windfall is food the player might walk back for, so it keeps for a
## meaningful slice of an in-game season) -- a carcass rotting enough for
## insects to work on is a fast organic process with nothing seasonal about
## it, and ecosystem_dynamics.md's own pacing pillar ("the simulation runs
## at the rate the player can perceive") means it needs to happen within an
## ordinary play session, not over real hours.
const ROT_SECONDS := 180.0

## How much decomposer "bite" it takes to fully consume an already-rotten
## carcass, regardless of what parts (if any) remain.
const DECOMPOSE_HEALTH := 20.0

var species := ""
var _age := 0.0
var _parts_taken := 0
var _decompose_health := DECOMPOSE_HEALTH
var _sprite: Sprite2D

## Disease (see docs/concept/disease.md's anthrax-like CARRION archetype):
## which RegionDifficulty tier this carcass rotted in (set by whoever spawns
## it -- see CreatureMarker._spawn_carcass_if_eligible, which copies its own
## region_tier straight across) and whether it rolled contaminated the
## instant it crossed is_rotten() (see _roll_contamination_if_just_rotten).
## A contaminated carcass is a real hazard: a decomposer can carry it onward
## (DecomposerMarker) and a player who butchers it carelessly risks exposure
## (Player._butcher_step).
var region_tier: int = RegionDifficulty.Tier.EASY
var contaminated := false
var _was_rotten := false
var _disease_model := DiseaseModel.new()

static var _item_catalog := ItemCatalog.new()
static var _carcass_sprite_generator := ProceduralCarcassSprite.new()


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	_sprite = Sprite2D.new()
	_sprite.texture = _carcass_sprite_generator.generate_texture(false)
	add_child(_sprite)


func _process(delta: float) -> void:
	_age += delta
	if not _was_rotten and is_rotten():
		_was_rotten = true
		_roll_contamination()


func is_rotten() -> bool:
	return _age >= ROT_SECONDS


## Rolled exactly once, the instant this carcass first crosses is_rotten()
## (docs/concept/disease.md: "an unburied Carcass past its ROT_SECONDS
## threshold has a real chance to be contaminated"). Seeded from this
## carcass's own position + species -- deterministic for a given carcass,
## the same spatial-hash convention ore_placement.gd/stone_placement.gd
## already use for their own one-time world rolls.
func _roll_contamination() -> void:
	var chance := _disease_model.carcass_contamination_chance(region_tier)
	var seed_value := hash("%d_%d_%s_contaminate" % [int(position.x), int(position.y), species])
	contaminated = _disease_model.attempt_transmit(chance, seed_value)


func has_parts_remaining() -> bool:
	return _parts_taken < Butchering.hits_required()


## Which part the next butcher() call would take, or "" once fully stripped.
func next_part() -> String:
	return Butchering.part_for_hit(_parts_taken)


## Removes the next remaining part. Hide and meat drop as ordinary ground
## items (WorldItemBus, the same path every other harvest already uses);
## guts do NOT -- they spawn a real CarcassGuts entity as a sibling of this
## node instead (see docs/concept/carrion.md: guts are food, not inventory).
## `meat_yield_bonus` is the player's allocated SkillTree meat_yield bonus
## (see Butchering.meat_count) -- 0.0 for an unskilled cut.
## Returns the part actually taken, or "" if nothing was left.
func butcher(meat_yield_bonus: float = 0.0) -> String:
	var part := next_part()
	if part == "":
		return ""
	_parts_taken += 1
	match part:
		"hide":
			WorldItemBus.item_dropped.emit(
				ItemStack.new(_item_catalog.make("hide"), Butchering.HIDE_COUNT), position
			)
		"meat":
			WorldItemBus.item_dropped.emit(
				ItemStack.new(_item_catalog.make("meat"), Butchering.meat_count(meat_yield_bonus)),
				position
			)
		"guts":
			var guts := CarcassGuts.new()
			guts.position = position
			get_parent().add_child(guts)
	if not has_parts_remaining() and _sprite != null:
		_sprite.texture = _carcass_sprite_generator.generate_texture(true)
	return part


## A decomposer's bite. No-op (returns false) until the carcass is actually
## rotten -- decomposers don't touch a fresh kill. Frees the node once fully
## consumed, whatever parts remain at that point.
func take_bite(amount: float) -> bool:
	if not is_rotten():
		return false
	_decompose_health = maxf(0.0, _decompose_health - amount)
	if _decompose_health <= 0.0:
		queue_free()
	return true


## For World's mouse-hover tooltip (see HoverTargetFinder).
func get_display_name() -> String:
	var label := species.capitalize()
	return "%s Remains" % label if not has_parts_remaining() else "%s Carcass" % label


## For World's mouse-hover tooltip (see HoverTargetFinder).
func get_hover_actions() -> Array:
	if next_part() == "":
		return []
	return [{"verb": "Butcher", "action": "attack"}]
