extends GutTest

## Real illustrated art actually reaching the screen for an item (see
## docs/concept/illustrated_art_addressing.md, whose own Status list has
## carried "Rendering: Player/CharacterView drawing held-item animations by
## address" as ⬜ since the convention landed).
##
## Reported directly: *"Can you wire the real tool sprites? Axe is currently
## using procedural sprite, but should use the illustrated one"*, and
## *"Sword as well"*.
##
## The registry, the resolver and the loader were all already built and
## tested. What was missing between them was the piece that turns a subject
## id into a real texture: nothing anywhere called IllustratedArtLoader --
## it appeared only inside other files' comments -- so every item in the
## game still drew ProceduralItemSprite's generated shape while ~100
## subjects' worth of real art sat on disk unreferenced.

const IllustratedItemArt = preload("res://src/rendering/illustrated_item_art.gd")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")

var art: IllustratedItemArt


func before_each():
	art = IllustratedItemArt.new()


# -- the address, as a path -------------------------------------------------

## docs/concept/illustrated_art_addressing.md, "The address":
## assets/sprites/<subject>/<context>/<season>/<state>/<animation>.png
func test_an_address_is_a_path():
	assert_eq(
		IllustratedItemArt.path_for("iron_axe", "icon", "any", "pristine", "still"),
		"res://assets/sprites/iron_axe/icon/any/pristine/still.png"
	)


func test_the_real_axe_art_is_where_that_path_says_it_is():
	assert_true(
		ResourceLoader.exists(
			IllustratedItemArt.path_for("iron_axe", "icon", "any", "pristine", "still")
		),
		"the real iron_axe icon is on disk at its own address"
	)


# -- resolution against the REAL tree, not a fixture -----------------------

## The resolver was only ever exercised against synthetic fixtures. Against
## the real tree it has a real job: `held` is drawn in pristine only (hand-
## verified -- the icon/equipped/ground rows carry worn art, held does not),
## so a broken axe still in someone's hand has to relax STATE and keep the
## held context rather than fall back to the icon.
func test_a_broken_axe_in_hand_relaxes_its_state_not_its_context():
	var address := art.resolve("iron_axe", "held", "broken", "still")
	assert_false(address.is_procedural)
	assert_eq(address.context, "held", "still the held picture")
	assert_eq(address.state, "pristine", "the only state held is drawn in")


func test_a_worn_axe_icon_uses_its_own_worn_art():
	var address := art.resolve("iron_axe", "icon", "worn", "still")
	assert_false(address.is_procedural)
	assert_eq(address.context, "icon")
	assert_eq(address.state, "worn", "the icon row really is drawn worn")


func test_a_subject_with_no_art_on_disk_resolves_to_procedural():
	# iron_pickaxe is a real catalog item with neither art nor a registry
	# entry -- the honest control for "nothing changed for what has no art".
	assert_true(art.resolve("iron_pickaxe", "icon", "pristine", "still").is_procedural)


# -- real pixels ------------------------------------------------------------

func test_the_axe_icon_is_a_real_texture():
	var texture := art.illustrated_texture_for("iron_axe", "icon", "pristine", "still")
	assert_not_null(texture, "the axe has real art and must not fall through")
	assert_gt(texture.get_width(), 0)


func test_the_sword_icon_is_a_real_texture():
	var texture := art.illustrated_texture_for("iron_sword", "icon", "pristine", "still")
	assert_not_null(texture, "\"Sword as well\"")
	assert_gt(texture.get_width(), 0)


## The magenta ground the art is drawn on is keyed out, or every item would
## render as a pink tile. The registry declares the key and its tolerance;
## this proves the loader is actually being handed them.
func test_the_magenta_ground_is_keyed_away():
	var image := art.illustrated_texture_for("iron_axe", "icon", "pristine", "still").get_image()
	assert_eq(image.get_pixel(0, 0).a, 0.0, "the corner of an icon is background, not ground")


## The whole point of matching ProceduralItemSprite.SIZE: an illustrated
## icon drops into the hotbar slot, the ground sprite and the armour rig
## exactly where the generated one was, so no call site has to re-scale and
## world_scale_for keeps meaning what it meant.
func test_an_illustrated_icon_is_the_same_size_as_the_generated_one_it_replaces():
	var illustrated := art.illustrated_texture_for("iron_axe", "icon", "pristine", "still")
	assert_eq(
		maxi(illustrated.get_width(), illustrated.get_height()), ProceduralItemSprite.SIZE
	)


func test_a_subject_with_no_art_has_no_illustrated_texture():
	assert_null(art.illustrated_texture_for("iron_pickaxe", "icon", "pristine", "still"))


# -- the fallback ladder every call site actually uses ---------------------

func test_texture_for_gives_the_illustrated_picture_when_there_is_one():
	var illustrated := art.illustrated_texture_for("iron_axe", "icon", "pristine", "still")
	assert_eq(
		art.texture_for("iron_axe", "icon").get_image().get_data(),
		illustrated.get_image().get_data()
	)


func test_texture_for_falls_back_to_the_generated_picture_when_there_is_none():
	var generated := ProceduralItemSprite.new().texture_for("iron_pickaxe")
	assert_eq(
		art.texture_for("iron_pickaxe", "icon").get_image().get_data(),
		generated.get_image().get_data(),
		"nothing changes for an item with no art of its own"
	)


## Asking twice must not re-read and re-key a 328x300 PNG -- the hotbar
## refreshes per frame, and texture_for is what it calls.
func test_the_same_address_is_only_built_once():
	assert_same(
		art.texture_for("iron_axe", "icon"), art.texture_for("iron_axe", "icon")
	)


# -- a drop-in for the generated sprite, whatever anchor the art declares --

## `held` is declared `pivot`, and the loader's pivot anchor deliberately
## returns the WHOLE authored cell (220x300 for the axe) so a grip point
## stays at the same pixel across frames. A call site swapping this in for
## a 32px generated sprite cannot take that: CharacterView.equip_weapon
## sets `offset = -texture.get_height() / 2`, so a 300px-tall texture
## displaces the grip by ten times what a 32px one does.
##
## Scaling the whole cell UNIFORMLY to a common canvas is compatible with
## the pivot contract rather than a violation of it -- every pixel keeps
## its position relative to every other, so the grip point stays where it
## was, just at a different resolution.
func test_a_held_frame_is_fitted_to_the_same_canvas_as_the_generated_sprite():
	var texture := art.texture_for("iron_axe", "held")
	assert_lte(texture.get_width(), ProceduralItemSprite.SIZE)
	assert_lte(texture.get_height(), ProceduralItemSprite.SIZE)
	assert_eq(
		maxi(texture.get_width(), texture.get_height()), ProceduralItemSprite.SIZE,
		"fitted TO the canvas, not merely under it"
	)


func test_fitting_a_held_frame_keeps_the_cells_own_aspect_so_the_grip_does_not_move():
	var cell := art.frames_for("iron_axe", "held")[0]
	var fitted := art.texture_for("iron_axe", "held")
	assert_almost_eq(
		float(fitted.get_width()) / float(fitted.get_height()),
		float(cell.get_width()) / float(cell.get_height()),
		0.05,
		"a uniform scale, not a squash"
	)


## The four contexts the four real call sites ask for, all present for the
## axe -- the hotbar icon, the axe in hand, the axe on your belt, and the
## axe lying on the ground.
func test_every_context_the_game_draws_has_real_axe_art():
	for context in ["icon", "held", "equipped", "ground"]:
		var address := art.resolve("iron_axe", context, "pristine", "still")
		assert_false(address.is_procedural, context)
		assert_eq(address.context, context, "%s is drawn in its own context" % context)
