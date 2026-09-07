extends GutTest

## illustrated_art_registry.gd -- see docs/concept/illustrated_art_addressing.md
## "The registry". A plain const Dictionary, the same shape every other
## `_SHEETS` dict in src/rendering/ already uses (see
## illustrated_item_sprite.gd's own _SHEETS, the club pilot this new
## convention supersedes), keyed by subject, holding only what a file path
## itself cannot say -- per-file existence is discovered at resolve time,
## never stored here (see the doc's own "Per file, nothing is stored").

const IllustratedArtRegistry = preload("res://src/rendering/illustrated_art_registry.gd")

var registry: IllustratedArtRegistry


func before_each():
	registry = IllustratedArtRegistry.new()


# -- has_subject / entry_for: the basic lookup contract --------------------

func test_has_subject_is_true_for_a_registered_subject():
	assert_true(registry.has_subject("wooden_club"))


func test_has_subject_is_false_for_an_unregistered_subject():
	assert_false(registry.has_subject("nonexistent_item"))


func test_entry_for_an_unregistered_subject_is_empty():
	assert_eq(registry.entry_for("nonexistent_item"), {})


# -- wooden_club: the doc's own non-seasonal, pivot-anchored example -------

func test_wooden_club_entry_has_the_documented_shape():
	var entry := registry.entry_for("wooden_club")
	assert_true(entry.contexts.has("held"))
	assert_eq(entry.contexts.held.anchor, "pivot")
	assert_false(entry.contexts.held.seasonal, "a club's look does not follow the year")
	assert_eq(entry.base_season, "any")
	assert_eq(entry.base_state, "pristine")
	assert_true(entry.states.has("pristine"))
	assert_true(entry.states.has("worn"))
	assert_true(entry.states.has("broken"))
	assert_true(entry.animations.has("attack"))
	assert_true(entry.animations.has("block"))
	assert_true(entry.animations.has("still"))


func test_wooden_clubs_attack_animation_is_an_eight_frame_one_shot():
	# item_illustrations.md's own "Combat sheets" spec: "8, one row
	# (wind-up 1-3, release 4-5, recovery 6-8)" -- not a looping cycle.
	var entry := registry.entry_for("wooden_club")
	assert_eq(entry.animations.attack.fps, 8)
	assert_false(entry.animations.attack.loop)


# -- campfire: the doc's own seasonal, footprint-anchored example ----------

func test_campfire_entry_has_the_documented_shape():
	var entry := registry.entry_for("campfire")
	assert_true(entry.contexts.has("placed"))
	assert_true(entry.contexts.placed.seasonal)
	assert_eq(entry.contexts.placed.anchor, "footprint")
	assert_true(entry.contexts.has("icon"))
	assert_false(entry.contexts.icon.seasonal)
	assert_eq(entry.contexts.icon.anchor, "center")
	assert_eq(entry.base_season, "summer")
	assert_eq(entry.base_state, "unlit")
	assert_true(entry.states.has("embers"))
	assert_true(entry.overlays.has("snowed"))


func test_campfires_burn_and_glow_animations_loop():
	var entry := registry.entry_for("campfire")
	assert_true(entry.animations.burn.loop)
	assert_true(entry.animations.glow.loop)


# -- self-consistency: every subject's own declared defaults must be real -
#
# The resolver's own base-case (mask=0, zero axes relaxed) and its base-
# season/base-state relaxation targets are only meaningful if a subject's
# OWN declared base_state is a member of its OWN declared states list (and
# similarly for base_season) -- an entry that failed this would make its
# own "state -> base state" fallback resolve to a state the subject
# doesn't even claim to have. Real self-consistency, not a style nit: this
# is exactly the class of bug a typo in a hand-written registry entry
# would produce silently.

const _REAL_SEASONS := ["spring", "summer", "autumn", "winter"]


func test_every_subjects_base_state_is_a_member_of_its_own_states_list():
	for subject in registry.subjects():
		var entry := registry.entry_for(subject)
		assert_true(
			entry.states.has(entry.base_state),
			"%s's base_state %s is not in its own states list" % [subject, entry.base_state]
		)


func test_every_subjects_base_season_is_any_or_a_real_season():
	for subject in registry.subjects():
		var entry := registry.entry_for(subject)
		var valid: bool = entry.base_season == "any" or _REAL_SEASONS.has(entry.base_season)
		assert_true(valid, "%s's base_season %s is neither \"any\" nor a real season" % [subject, entry.base_season])


func test_every_contexts_anchor_is_one_of_the_four_declared_anchor_types():
	var real_anchors := ["baseline", "pivot", "footprint", "center"]
	for subject in registry.subjects():
		var entry := registry.entry_for(subject)
		for context_name in entry.contexts:
			var anchor: String = entry.contexts[context_name].anchor
			assert_true(
				real_anchors.has(anchor),
				"%s's %s context has an unrecognized anchor %s" % [subject, context_name, anchor]
			)


func test_every_subject_declares_at_least_one_animation():
	for subject in registry.subjects():
		var entry := registry.entry_for(subject)
		assert_gt(entry.animations.size(), 0, "%s declares no animations at all" % subject)


func test_subjects_lists_every_registered_subject_exactly_once():
	var subjects := registry.subjects()
	assert_true(subjects.has("wooden_club"))
	assert_true(subjects.has("campfire"))
	var seen := {}
	for subject in subjects:
		seen[subject] = true
	assert_eq(subjects.size(), seen.size(), "no subject should be listed twice")
