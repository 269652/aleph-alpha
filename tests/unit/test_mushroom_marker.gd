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
const MushroomSpecies = preload("res://src/world/mushroom_species.gd")
const ProceduralMushroomSprite = preload("res://src/rendering/procedural_mushroom_sprite.gd")
const IllustratedMushroomSprite = preload("res://src/rendering/illustrated_mushroom_sprite.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")
const MushroomBiting = preload("res://src/gameplay/mushroom_biting.gd")

class StubPicker:
	extends Node2D
	var inventory


class StubMushroomWorld:
	extends RefCounted
	var taken: Array = []
	var bitten: Array = []
	## How many stages bite() reports as actually applied -- lets a test
	## force "nothing left to take" (0) without needing a real
	## WildMushroomPatch's own recovery/stage-cap state. Defaults to 1,
	## matching a real sim's ordinary single-stage bite.
	var bite_stages_result := 1

	# No need to override has_method() -- Godot's own reflection already
	# reports true for this real, defined method. Named `pick`/`bite` to
	# match WildMushroomPatch's own real methods -- the actual
	# mushroom_world a live MushroomRenderer injects is that sim directly
	# (spawn_markers/sync_markers already hold the exact right per-chunk
	# instance), not a wrapper with a different name.
	func pick(cell: Vector2i) -> bool:
		taken.append(cell)
		return true

	func bite(cell: Vector2i, _stages: int = 1) -> int:
		if bite_stages_result <= 0:
			return 0
		bitten.append(cell)
		return bite_stages_result


func _make_marker(species_id: String, cell: Vector2i = Vector2i.ZERO, corpse_kind: String = "") -> MushroomMarker:
	var marker := MushroomMarker.new()
	marker.species_id = species_id
	marker.cell = cell
	marker.corpse_kind = corpse_kind
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


## Corrected 2026-09-07 (see docs/concept/soil_fauna.md's "Progressive,
## mass-scaled bites, and real toxic effects"): a second bite is no longer
## necessarily a no-op -- it lands exactly when the sim reports there is
## still real capacity left, and MushroomMarker.bite_stage accumulates
## whatever it was told, rather than the marker enforcing a hardcoded
## one-shot cap itself.
func test_a_second_bite_advances_bite_stage_further():
	var marker := _make_marker("parasol", Vector2i(3, 4))
	marker.mushroom_world = StubMushroomWorld.new()
	assert_true(marker.take_mushroom_bite())
	assert_eq(marker.bite_stage, 1)
	assert_true(marker.take_mushroom_bite(), "the sim still has capacity -- a second bite should land")
	assert_eq(marker.bite_stage, 2)


## Once the sim itself reports nothing left (see WildMushroomPatch.bite's own
## real stage cap), a further bite is a genuine no-op -- MushroomMarker just
## forwards whatever the sim decides, it doesn't second-guess it locally.
func test_a_bite_the_sim_refuses_is_a_no_op():
	var marker := _make_marker("parasol", Vector2i(3, 4))
	var world := StubMushroomWorld.new()
	marker.mushroom_world = world
	assert_true(marker.take_mushroom_bite())
	world.bite_stages_result = 0
	assert_false(marker.take_mushroom_bite(), "the sim says nothing is left to take")
	assert_eq(marker.bite_stage, 1, "a refused bite must not still advance the stage")


## A bigger eater's bite (see MushroomBiting.bites_per_visit_for) can request
## more than one stage in a single call.
func test_take_mushroom_bite_accepts_a_bigger_bite_count():
	var marker := _make_marker("parasol", Vector2i(3, 4))
	var world := StubMushroomWorld.new()
	world.bite_stages_result = 3
	marker.mushroom_world = world
	assert_true(marker.take_mushroom_bite(3))
	assert_eq(marker.bite_stage, 3)


func test_can_be_bitten_defaults_to_true():
	assert_true(_make_marker("parasol").can_be_bitten())


func test_can_be_bitten_is_false_once_fully_eaten():
	var marker := _make_marker("parasol", Vector2i(3, 4))
	var world := StubMushroomWorld.new()
	world.bite_stages_result = MushroomBiting.MAX_BITE_STAGES
	marker.mushroom_world = world
	marker.take_mushroom_bite(MushroomBiting.MAX_BITE_STAGES)
	assert_false(marker.can_be_bitten(), "fully eaten -- nothing left for the next decomposer to take")


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
## codebase uses -- all 8 real species have real bitten art now (see
## IllustratedMushroomSprite), so this exercises the fallback itself via a
## species id that can never have real art at all, the same "portobello"
## stand-in test_illustrated_mushroom_sprite.gd's own unknown-species test
## already uses.
func test_take_mushroom_bite_falls_back_to_the_normal_look_without_bitten_art():
	var marker := _make_marker("portobello")
	marker.mushroom_world = StubMushroomWorld.new()
	var before: PackedByteArray = (marker.get_child(0) as Sprite2D).texture.get_image().get_data()
	marker.take_mushroom_bite()
	var after: PackedByteArray = (marker.get_child(0) as Sprite2D).texture.get_image().get_data()
	assert_eq(before, after, "an unknown species has no bitten art -- the look should stay the same")


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


# -- corpses: crushed/bitten remains show the real delivered art (see
# docs/concept/mushrooms.md "Crushed underfoot", docs/concept/soil_fauna.md
# fungivory follow-up, IllustratedMushroomSprite.crushed_frame_for/
# bitten_frame_for). corpse_kind is set before add_child by
# MushroomRenderer.sync_markers, same convention as species_id/cell.

func test_shows_crushed_art_when_corpse_kind_is_crushed_and_the_species_has_it():
	var marker := _make_marker("chanterelle", Vector2i.ZERO, "crushed")
	var sprite := marker.get_child(0) as Sprite2D
	var expected := IllustratedMushroomSprite.new().crushed_frame_for("chanterelle", marker.mushroom_seed)
	assert_eq(sprite.texture.get_image().get_data(), expected.get_image().get_data())


## Reported directly: mushroom hover tooltips should show state, e.g.
## "Parasol (Crushed)". get_display_name() already named bitten/toxic/
## edible (see test_display_name_reveals_the_real_species_and_toxicity/
## test_display_name_reveals_bitten above and below) but never checked
## corpse_kind at all -- a crushed corpse fell through to the ordinary
## toxic/edible hint instead, the same species-driven answer a live,
## untouched specimen shows, which reads as flatly wrong for a corpse.
## Highest priority (checked before bitten/toxic/edible, mirroring
## _rebuild_sprite's own identical corpse_kind-first priority): a crushed
## marker is always a FRESH, unbitten replacement (see corpse_kind's own
## doc comment), so this can never actually race bitten in practice, but
## matching the sprite's own priority order keeps the two from silently
## drifting apart.
func test_display_name_reveals_a_crushed_corpse():
	assert_eq(_make_marker("parasol", Vector2i.ZERO, "crushed").get_display_name(), "Parasol (Crushed)")
	assert_eq(_make_marker("death_cap", Vector2i.ZERO, "crushed").get_display_name(), "Death Cap (Crushed)")


## A fully-eaten mushroom (see WildMushroomPatch's new "eaten" corpse_kind,
## docs/concept/soil_fauna.md's "Progressive, mass-scaled bites") gets its
## own real state hint too, distinct from a crushed corpse.
func test_display_name_reveals_an_eaten_corpse():
	assert_eq(_make_marker("parasol", Vector2i.ZERO, "eaten").get_display_name(), "Parasol (Eaten)")


## An eaten corpse shows the final bitten-stage art (the mushroom read as
## most-consumed just before it was actually finished off), not the ordinary
## live look, wherever real bitten art exists for the species.
func test_shows_final_stage_bitten_art_when_corpse_kind_is_eaten():
	var marker := _make_marker("chanterelle", Vector2i.ZERO, "eaten")
	var sprite := marker.get_child(0) as Sprite2D
	var expected := IllustratedMushroomSprite.new().bitten_frame_for(
		"chanterelle", marker.mushroom_seed, MushroomBiting.MAX_BITE_STAGES
	)
	assert_eq(sprite.texture.get_image().get_data(), expected.get_image().get_data())


## A bitten mushroom is NOT a "bitten" corpse_kind -- it is still standing,
## still fruiting, tracked via the separate `bitten` field instead (see
## MushroomMarker.take_mushroom_bite, WildMushroomPatch._bitten's own doc
## comment for why the two are orthogonal). Covered by
## test_take_mushroom_bite_swaps_the_sprite_when_the_species_has_bitten_art
## above via the real mechanism instead.


## All 8 real species have real crushed (and normal, and bitten)
## illustrated art now (reported live: "I added all missing mushroom
## spritesheets... wire them") -- a species with the middle case this test
## used to cover (real normal look, no crushed look) no longer exists, so
## this now exercises the DEEPEST fallback instead: a species id with no
## illustrated art of ANY kind still falls all the way through to the
## procedural generator rather than a blank/missing texture (see
## MushroomMarker._rebuild_sprite's own final `else` branch).
func test_falls_back_to_the_procedural_look_for_a_species_with_no_illustrated_art_at_all():
	var marker := _make_marker("portobello", Vector2i.ZERO, "crushed")
	var sprite := marker.get_child(0) as Sprite2D
	var expected := ProceduralMushroomSprite.new().generate_texture("portobello", true)
	assert_eq(sprite.texture.get_image().get_data(), expected.get_image().get_data())


## Round 6 FPS fix (see docs/concept/soil_fauna.md): a live decomposer bite
## used to be the FIRST thing that ever asked for a not-yet-cached
## species' bitten art, on a real gameplay frame -- measured up to ~1.6s
## for one bite. warm_art_cache() is the one-line hook World._ready() now
## calls once, before any decomposer can possibly reach a mushroom, so
## take_mushroom_bite's own _rebuild_sprite() call always hits an already-
## warm cache instead. Thin delegation to the shared _illustrated_
## generator instance every MushroomMarker already reads from -- the real
## coverage lives in test_illustrated_mushroom_sprite.gd's own warm_cache
## tests; this just proves the wiring reaches the same shared instance.
## `_bitten_frames_cache` (checked here originally) was replaced by
## `_bitten_stage_frames_cache` -- see test_illustrated_mushroom_sprite.gd's
## own mirror test for why -- updated to the real field name post-merge.
func test_warm_art_cache_warms_the_shared_illustrated_generator():
	IllustratedMushroomSprite._frames_cache = {}
	IllustratedMushroomSprite._crushed_frames_cache = {}
	IllustratedMushroomSprite._bitten_stage_frames_cache = {}
	MushroomMarker.warm_art_cache()
	for id in MushroomSpecies.IDS:
		assert_true(
			IllustratedMushroomSprite._bitten_stage_frames_cache.has(id), "%s bitten cache should be warm" % id
		)
