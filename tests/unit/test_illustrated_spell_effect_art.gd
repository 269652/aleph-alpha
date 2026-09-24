extends GutTest

## Real illustrated art reaching the screen for a spell atom's effect
## (docs/concept/spell_vfx.md, "IllustratedSpellEffectArt") -- the bridge
## that was missing, the exact shape `IllustratedItemArt`'s own doc comment
## named for items: a registry can know every subject and a resolver can
## know the fallback lattice, and none of it reaches a pixel until
## something actually calls the loader.
##
## `ai_sprite_prompts.md` section 8 has had complete prompts for all 25
## atoms since 2026-08-28. Nothing has ever drawn them. Every cast a player
## has seen is `ProceduralSpellEffectSprite`'s generated shape -- correct
## per the doc's own "fallback of last resort" pillar, but a fallback with
## no real art to fall back FROM is not a fallback, it is the only track.
##
## No atom has real art on disk yet (that is the honest, named-not-hidden
## state -- see spell_vfx.md's Status), so every test here either asserts
## the ADDRESS shape and registry coverage, or asserts the safe fallback a
## subject with no art on disk gets -- exactly `test_illustrated_item_art.
## gd`'s own "a subject with no art on disk resolves to procedural" case,
## true of all 25 atoms simultaneously right now.

const IllustratedSpellEffectArt = preload("res://src/rendering/illustrated_spell_effect_art.gd")
const ProceduralSpellEffectSprite = preload("res://src/rendering/procedural_spell_effect_sprite.gd")
const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")
const IllustratedArtRegistry = preload("res://src/rendering/illustrated_art_registry.gd")

var art: IllustratedSpellEffectArt
var _catalog := SpellAtomCatalog.new()
var _registry := IllustratedArtRegistry.new()


func before_each():
	art = IllustratedSpellEffectArt.new()


# -- the address, collapsed to the one axis that varies ---------------------

## docs/concept/spell_vfx.md's address table: subject=atom, context="effect",
## season="any", state="default", animation="cast" -- every axis but the
## atom id itself fixed, because none of the others mean anything for a
## spell effect.
func test_an_address_is_a_path_with_the_fixed_axes():
	assert_eq(
		IllustratedSpellEffectArt.path_for("fire_damage"),
		"res://assets/sprites/fire_damage/effect/any/default/cast.png"
	)


func test_the_path_is_keyed_by_atom_id_alone():
	assert_eq(
		IllustratedSpellEffectArt.path_for("frost_damage"),
		"res://assets/sprites/frost_damage/effect/any/default/cast.png"
	)


# -- registry coverage: every catalog atom is a known subject --------------

## The drift guard this exact suite of failures earned for items
## (test_item_icon_registry_coverage.gd): a future atom added to
## spell_atom_catalog.gd and never registered here would silently render
## procedural forever with nothing failing loudly about it.
func test_every_catalog_atom_is_a_registered_subject():
	for atom_id in _catalog.known_ids():
		assert_true(
			_registry.has_subject(atom_id),
			"%s must be a registered illustrated-art subject" % atom_id
		)


func test_a_registered_atoms_entry_declares_the_effect_context():
	var entry := _registry.entry_for("fire_damage")
	assert_true(entry.get("contexts", {}).has("effect"))


func test_a_registered_atoms_entry_declares_the_cast_animation():
	var entry := _registry.entry_for("fire_damage")
	assert_true(entry.get("animations", {}).has("cast"))


# -- resolution: no art on disk yet, so every atom falls back safely -------

## Named honestly rather than hidden (spell_vfx.md's Status): true of all
## 25 atoms at once today.
func test_every_registered_atom_resolves_to_procedural_until_art_exists():
	for atom_id in _catalog.known_ids():
		var address: Dictionary = art.resolve(atom_id)
		assert_true(
			address.is_procedural,
			"%s has no art on disk yet, so it must fall back" % atom_id
		)


func test_an_unregistered_id_also_resolves_to_procedural_rather_than_crashing():
	assert_true(art.resolve("not_a_real_atom").is_procedural)


# -- texture_for: illustrated-or-procedural, the one call site wants -------

## The actual contract every caller relies on: SOME real texture comes
## back, whichever track supplied it.
func test_texture_for_always_returns_a_real_texture():
	for atom_id in ["fire_damage", "freeze", "minor_heal", "slow", "push", "poison_damage"]:
		assert_not_null(art.texture_for(atom_id), "%s must draw something" % atom_id)


## With no illustrated art on disk, texture_for must be pixel-identical to
## the procedural generator's own output -- the fallback contract stated as
## an equality, not just "returned something".
func test_texture_for_matches_the_procedural_fallback_exactly():
	var generator := ProceduralSpellEffectSprite.new()
	assert_eq(
		art.texture_for("fire_damage").get_image().get_data(),
		generator.texture_for("fire_damage").get_image().get_data()
	)


func test_texture_for_an_unknown_atom_falls_back_without_crashing():
	assert_not_null(art.texture_for("not_a_real_atom"))


## Falling back must not mean falling back to the WRONG atom's shape --
## a real regression this exact fallback design invites if the miss path
## ever forgets which atom it was asked for.
func test_texture_for_differs_between_two_different_fallback_atoms():
	assert_ne(
		art.texture_for("fire_damage").get_image().get_data(),
		art.texture_for("frost_damage").get_image().get_data()
	)


# -- the declared cast fps is derived, not eyeballed ------------------------

## docs/concept/spell_vfx.md: 6 frames over SpellEffectMarker's own
## GROW_DURATION+HOLD_DURATION+FADE_DURATION beat -- not yet consumed by
## the marker (still Tweens a single frame), declared now so the number is
## already correct the day it is. Computed the SAME way the registry
## comment itself derives it, so retuning the marker's timing and
## forgetting to retune this fails a test instead of silently drifting.
func test_the_declared_cast_fps_matches_a_six_frame_row_over_the_markers_own_beat():
	const SpellEffectMarker = preload("res://src/rendering/spell_effect_marker.gd")
	var beat_seconds: float = (
		SpellEffectMarker.GROW_DURATION
		+ SpellEffectMarker.HOLD_DURATION
		+ SpellEffectMarker.FADE_DURATION
	)
	var expected_fps: int = roundi(6.0 / beat_seconds)
	for atom_id in _catalog.known_ids():
		var entry := _registry.entry_for(atom_id)
		var cast: Dictionary = entry.get("animations", {}).get("cast", {})
		assert_eq(
			int(cast.get("fps", -1)), expected_fps,
			"%s's declared cast fps must match the marker's own beat" % atom_id
		)
