extends StaticBody2D

## A tree that can be felled with an axe (see Player._perform_attack),
## dropping wood. Deliberately defines NO _process -- thousands of these are
## loaded at once, so any per-frame behavior here would tank the frame rate
## (the same constraint ForageScheduler's centralized ticking exists to
## avoid). take_damage() is only ever called on demand by the attacker, so
## having a script here costs nothing at runtime until that happens.

const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const Health = preload("res://src/gameplay/health.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")

const GROUP_NAME := "tree"
const MAX_HEALTH := 30.0
const WOOD_DROP_COUNT := 3
const STICK_DROP_COUNT := 2

var health := MAX_HEALTH
var _health := Health.new()

## Set by TreeRenderer so this tree can re-render its own canopy with its
## current ripe-fruit crop (see set_ripe_fruit) -- fruit phenology is driven
## centrally (EarthChunkManager.step_fruiting) only for trees near the player,
## so most trees never pay this cost.
var species_bias := 0.5
var sprite_seed := 0
var _canopy_sprite: Sprite2D
var _ripe_count := -1  # -1 == "never set", so the first update always renders
var _tree_sprite_generator := ProceduralTreeSprite.new()


func _ready() -> void:
	add_to_group(GROUP_NAME)


## Registers the canopy sprite so set_ripe_fruit can swap its texture.
func bind_canopy(sprite: Sprite2D) -> void:
	_canopy_sprite = sprite


## Shows `count` ripe fruits as canopy pixel dots (capped in the sprite).
## No-op if the count is unchanged (avoids regenerating the texture every
## tick) or the canopy isn't bound.
func set_ripe_fruit(count: int) -> void:
	if count == _ripe_count or _canopy_sprite == null:
		return
	_ripe_count = count
	_canopy_sprite.texture = _tree_sprite_generator.generate_texture_with_fruit(
		species_bias, sprite_seed, count
	)


## Reduces health; felling drops wood into the world (via WorldItemBus, same
## as creature loot/forage -- see world.gd's _on_item_dropped) and frees the
## tree (its collision goes with it, same as any other queue_free()'d node).
func take_damage(amount: float) -> void:
	health = _health.take_damage(health, amount)
	if _health.is_dead(health):
		var wood := ItemStack.new(Item.new("wood", "Wood", "material", 40), WOOD_DROP_COUNT)
		WorldItemBus.item_dropped.emit(wood, position)
		var sticks := ItemStack.new(Item.new("stick", "Stick", "material", 40), STICK_DROP_COUNT)
		WorldItemBus.item_dropped.emit(sticks, position + Vector2(8, 4))
		queue_free()
