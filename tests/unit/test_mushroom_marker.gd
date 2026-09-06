extends GutTest

## The visible marker over one fruiting WildMushroomPatch site -- see
## docs/concept/mushrooms.md. Deliberately inert (AntMoundMarker's own
## reasoning: purely "stand here and be visible").
##
## Always shows its REAL species' own look and name -- no identification
## gate (see docs/concept/mushrooms.md's "Revised again: the
## identification gate is gone"): the illustrated art directly resembles
## its real counterpart, so recognizing danger at a glance is meant to be
## real and immediate, the same way a real forager cross-checks against a
## physical field guide rather than starting from zero. Picking one up
## always resolves to the REAL species item, matching what it already
## visibly was.

const MushroomMarker = preload("res://src/rendering/mushroom_marker.gd")
const ProceduralMushroomSprite = preload("res://src/rendering/procedural_mushroom_sprite.gd")
const IllustratedMushroomSprite = preload("res://src/rendering/illustrated_mushroom_sprite.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")

class StubPicker:
	extends Node2D
	var inventory


class StubMushroomWorld:
	extends RefCounted
	var taken: Array = []
	var bitten: Array = []

	# No need to override has_method() -- Godot's own reflection already
	# reports true for this real, defined method. Named `pick` to match
	# WildMushroomPatch's own real method -- the actual mushroom_world a
	# live MushroomRenderer injects is that sim directly (spawn_markers/
	# sync_markers already hold the exact right per-chunk instance), not a
	# wrapper with a different name.
	func pick(cell: Vector2i) -> bool:
		taken.append(cell)
		return true

	# Same reasoning as pick() above -- named to match WildMushroomPatch.bite
	# exactly, and mirrors its own "already bitten is a no-op" contract.
	func bite(cell: Vector2i) -> bool:
		if bitten.has(cell):
			return false
		bitten.append(cell)
		return true


func _make_marker(species_id: String, cell: Vector2i = Vector2i.ZERO) -> MushroomMarker:
	var marker := MushroomMarker.new()
	marker.species_id = species_id
	marker.cell = cell
	add_child_autofree(marker)
	return marker


func _make_picker(slots: int = 10) -> StubPicker:
	var picker := StubPicker.new()
	picker.inventory = Inventory.new(slots)
	add_child_autofree(picker)
	return picker


# -- groups -------------------------------------------------------------

func test_joins_the_dropped_item_group():
	var marker := _make_marker("chanterelle")
	assert_true(marker.is_in_group(DroppedItem.GROUP_NAME))


func test_joins_the_forageable_group_so_decomposers_can_eat_it_too():
	var marker := _make_marker("chanterelle")
	assert_true(marker.is_in_group(DroppedItem.FORAGEABLE_GROUP_NAME))


## Reported live: "They need hover tooltips." World._update_hover_tooltip
## only scans HoverTargetFinder.GROUP_NAME (see that class's own doc
## comment) -- a marker not in it is invisible to the whole hover system
## no matter what get_display_name() returns, the same gap
## WildCropMarker/LiftableStone don't have.
func test_joins_the_hoverable_group_so_the_mouse_tooltip_actually_shows():
	var marker := _make_marker("chanterelle")
	assert_true(marker.is_in_group(HoverTargetFinder.GROUP_NAME))


## Mirrors DroppedItem/WildCropMarker/LiftableStone's own
## get_hover_actions() contract -- the same "Pick Up" verb DroppedItem's
## own generic pickup uses.
func test_get_hover_actions_offers_pick_up():
	var marker := _make_marker("chanterelle")
	assert_eq(marker.get_hover_actions(), [{"verb": "Pick Up", "action": "pickup"}])


# -- always the real species' own look and name --------------------------

func test_different_species_look_different_from_each_other():
	var fly_agaric := _make_marker("fly_agaric")
	var chanterelle := _make_marker("chanterelle")
	var fly_agaric_sprite := fly_agaric.get_child(0) as Sprite2D
	var chanterelle_sprite := chanterelle.get_child(0) as Sprite2D
	assert_ne(fly_agaric_sprite.texture.get_image().get_data(), chanterelle_sprite.texture.get_image().get_data())


## Same "gigantic" failure class DecomposerMarker's/AntMoundMarker's own
## sprites hit once (applying the wrong world scale to real illustrated
## art, whose canvas proportions don't match the procedural fallback's) --
## pinned directly rather than trusted by inspection. Real illustrated art
## exists for every species (see IllustratedMushroomSprite), so a marker
## must use ITS OWN measured-from-the-real-art marker_scale(species_id),
## not the procedural generator's flat MUSHROOM_WORLD_SCALE.
func test_species_with_illustrated_variants_use_the_illustrated_marker_scale():
	var marker := _make_marker("chanterelle")
	var sprite := marker.get_child(0) as Sprite2D
	assert_eq(sprite.scale, Vector2.ONE * IllustratedMushroomSprite.new().marker_scale("chanterelle"))


func test_display_name_reveals_the_real_species_and_toxicity():
	assert_eq(_make_marker("psylo").get_display_name(), "Psilocybe (Toxic)")
	assert_eq(_make_marker("chanterelle").get_display_name(), "Chanterelle (Edible)")


# -- picking up: always the real species -----------------------------------

func test_pickup_adds_the_real_species_item():
	var marker := _make_marker("fly_agaric")
	var picker := _make_picker()
	assert_true(marker.pick_up(picker))
	assert_eq(picker.inventory.count_of("fly_agaric"), 1)


func test_pickup_frees_the_marker():
	var marker := _make_marker("parasol")
	var picker := _make_picker()
	marker.pick_up(picker)
	assert_true(marker.is_queued_for_deletion())


func test_pickup_tells_the_mushroom_world_its_site_was_taken():
	var marker := _make_marker("parasol", Vector2i(3, 4))
	marker.mushroom_world = StubMushroomWorld.new()
	var picker := _make_picker()
	marker.pick_up(picker)
	assert_eq(marker.mushroom_world.taken, [Vector2i(3, 4)])


func test_pickup_fails_gracefully_with_no_picker():
	var marker := _make_marker("parasol")
	assert_false(marker.pick_up(null))
	assert_false(marker.is_queued_for_deletion())


# -- bug fungivory: a bite marks it bitten, it doesn't remove it -----------
#
# Reported: "bugs should forage mushrooms -- when a bug takes a bite from a
# mushroom it should get the bitten flag... mushrooms with a bitten flag
# have less value; weigh less and render their mushroom_bitten_1.png in
# world and inventory, their title reads as e.g. Parasol (bitten)".

func test_bitten_defaults_to_false():
	assert_false(_make_marker("parasol").bitten)


func test_take_mushroom_bite_marks_it_bitten_and_returns_true():
	var marker := _make_marker("parasol", Vector2i(3, 4))
	marker.mushroom_world = StubMushroomWorld.new()
	assert_true(marker.take_mushroom_bite())
	assert_true(marker.bitten)


func test_take_mushroom_bite_tells_the_mushroom_world():
	var marker := _make_marker("parasol", Vector2i(3, 4))
	marker.mushroom_world = StubMushroomWorld.new()
	marker.take_mushroom_bite()
	assert_eq(marker.mushroom_world.bitten, [Vector2i(3, 4)])


## One bite is enough -- see WildMushroomPatch.bite's own doc comment for why
## DecomposerMarker relies on this false to know when to move on.
func test_a_second_bite_is_a_no_op():
	var marker := _make_marker("parasol", Vector2i(3, 4))
	marker.mushroom_world = StubMushroomWorld.new()
	assert_true(marker.take_mushroom_bite())
	assert_false(marker.take_mushroom_bite(), "already bitten -- nothing left to take")


func test_take_mushroom_bite_fails_gracefully_with_no_mushroom_world():
	var marker := _make_marker("parasol")
	assert_false(marker.take_mushroom_bite())
	assert_false(marker.bitten)


func test_take_mushroom_bite_swaps_the_sprite_when_the_species_has_bitten_art():
	var marker := _make_marker("champignon")
	marker.mushroom_world = StubMushroomWorld.new()
	var before: PackedByteArray = (marker.get_child(0) as Sprite2D).texture.get_image().get_data()
	marker.take_mushroom_bite()
	var after: PackedByteArray = (marker.get_child(0) as Sprite2D).texture.get_image().get_data()
	assert_ne(before, after, "champignon has real bitten art -- the sprite should change")


## Same has-or-doesn't fallback every optional illustrated-art seam in this
## codebase uses -- only 3 of 6 species have real bitten art so far (see
## IllustratedMushroomSprite).
func test_take_mushroom_bite_falls_back_to_the_normal_look_without_bitten_art():
	var marker := _make_marker("fly_agaric")
	marker.mushroom_world = StubMushroomWorld.new()
	var before: PackedByteArray = (marker.get_child(0) as Sprite2D).texture.get_image().get_data()
	marker.take_mushroom_bite()
	var after: PackedByteArray = (marker.get_child(0) as Sprite2D).texture.get_image().get_data()
	assert_eq(before, after, "fly_agaric has no bitten art yet -- the look should stay the same")


## Bitten takes priority over the ordinary toxic/edible suffix -- once a
## mushroom is visibly bitten, that's the more salient thing to name.
func test_display_name_shows_bitten_instead_of_toxicity_once_bitten():
	var marker := _make_marker("psylo")
	marker.mushroom_world = StubMushroomWorld.new()
	marker.take_mushroom_bite()
	assert_eq(marker.get_display_name(), "Psilocybe (Bitten)")


## Picking up a bitten mushroom adds the "_bitten" catalog variant (see
## MushroomBiting.gd, ItemCatalog) -- lighter, distinctly named -- not the
## ordinary species item it would have been unbitten.
func test_pickup_of_a_bitten_mushroom_adds_the_bitten_item():
	var marker := _make_marker("parasol")
	marker.mushroom_world = StubMushroomWorld.new()
	marker.take_mushroom_bite()
	var picker := _make_picker()
	assert_true(marker.pick_up(picker))
	assert_eq(picker.inventory.count_of("parasol_bitten"), 1)
	assert_eq(picker.inventory.count_of("parasol"), 0)


# -- position -------------------------------------------------------------

func test_stays_exactly_where_placed():
	var marker := _make_marker("chanterelle")
	marker.position = Vector2(80, 60)
	assert_eq(marker.position, Vector2(80, 60))
