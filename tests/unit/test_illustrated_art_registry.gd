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


func test_campfire_entry_gains_a_ground_context_matching_furnace():
	# campfire's own "placed" surface predates this pass and stays deferred
	# (no real art either, same as furnace's), but a dropped/uncrafted
	# campfire item still needs a ground sprite same as every other
	# placeable -- furnace already draws this exact icon/ground/placed
	# shape, so campfire gains the ground context to match.
	var entry := registry.entry_for("campfire")
	assert_true(entry.contexts.has("ground"))
	assert_eq(entry.contexts.ground.anchor, "center")


# -- 2026-09-13 per-item composite sheet mapping (item_illustrations.md's
# own "Per-item composite sheet mapping"): durability art generalizes
# beyond the original wooden_club/iron_sword/crude_blade three, to a
# fourth "used" state, and which static rows (icon/held/equipped/ground)
# apply is a function of item kind, not universal.

func test_stone_pickaxe_entry_has_the_documented_shape():
	# A tool: the full icon/held/equipped/ground row set -- ANY carryable
	# weapon or tool has a carried-but-not-in-hand look (strapped to a
	# belt/back), whether or not it is ever swung (corrected same-day: the
	# first draft of this mapping wrongly dropped "equipped" for tools).
	var entry := registry.entry_for("stone_pickaxe")
	for context in ["icon", "held", "equipped", "ground"]:
		assert_true(entry.contexts.has(context), "stone_pickaxe should declare a %s context" % context)
	assert_eq(entry.contexts.held.anchor, "pivot")
	assert_eq(entry.base_state, "pristine")
	for state in ["pristine", "used", "worn", "broken"]:
		assert_true(entry.states.has(state), "stone_pickaxe should have the %s state" % state)
	# held's real art is 4 pose variants of the pristine state only (real
	# generated art, 2026-09-08 batch integrated 2026-09-13) -- not tied to
	# the pristine/used/worn/broken axis, the same "pose variety, one state"
	# shape confirmed for this whole batch.
	for animation in ["still", "pose_b", "pose_c", "pose_d"]:
		assert_true(entry.animations.has(animation), "stone_pickaxe should declare the %s animation" % animation)


func test_crude_blade_entry_has_the_documented_shape():
	# A weapon: the full icon/held/equipped/ground row set, plus a real
	# attack swing animation -- pristine-state frames only, the same
	# "worn/attack falls back to pristine/attack" rule the resolver's own
	# wooden_club worked example already establishes, so no separate
	# worn/broken attack art is needed here.
	var entry := registry.entry_for("crude_blade")
	for context in ["icon", "held", "equipped", "ground"]:
		assert_true(entry.contexts.has(context), "crude_blade should declare a %s context" % context)
	for state in ["pristine", "used", "worn", "broken"]:
		assert_true(entry.states.has(state), "crude_blade should have the %s state" % state)
	assert_true(entry.animations.has("attack"))
	assert_eq(entry.animations.attack.fps, 8)
	assert_false(entry.animations.attack.loop)


func test_leather_helm_entry_has_the_documented_shape():
	# Armor: icon, equipped (worn on the rig slot), ground -- no held, you
	# don't swing a helmet. Armor wears too (item_durability.md's own
	# open question, resolved 2026-09-13), so it gets the full 4 states.
	var entry := registry.entry_for("leather_helm")
	assert_true(entry.contexts.has("icon"))
	assert_true(entry.contexts.has("equipped"))
	assert_true(entry.contexts.has("ground"))
	assert_false(entry.contexts.has("held"), "you don't swing a helmet")
	for state in ["pristine", "used", "worn", "broken"]:
		assert_true(entry.states.has(state), "leather_helm should have the %s state" % state)


func test_furnace_entry_shares_campfires_fire_status_vocabulary():
	# A placeable: furnace's own states are fire-status (unlit/lit/embers),
	# the same vocabulary campfire already uses -- NOT durability, since a
	# stone furnace's condition axis is whether it's burning, not wear.
	var entry := registry.entry_for("furnace")
	assert_true(entry.contexts.has("placed"))
	assert_eq(entry.contexts.placed.anchor, "footprint")
	assert_eq(entry.base_state, "unlit")
	for state in ["unlit", "lit", "embers"]:
		assert_true(entry.states.has(state), "furnace should have the %s state" % state)
	assert_true(entry.animations.has("burn"))
	assert_true(entry.animations.burn.loop)


# -- 2026-09-08 batch integration (2026-09-13): real art for these six was
# sitting uncommitted in the main checkout since 2026-09-08. Held-row
# semantics were hand-verified per item, NOT assumed uniform (automated
# SpriteSheetSlicer.detect_frames boundary detection proved unreliable on
# this real, imperfectly-dividered dataset) -- some items' held row is pure
# pose variety of the pristine state (a tool with nothing that visibly
# wears), others show real condition progression exactly like icon/
# equipped/ground (a tool with a blade/net/cord that visibly damages).

func test_compass_held_is_pose_variety_not_condition():
	var entry := registry.entry_for("compass")
	for context in ["icon", "held", "equipped", "ground"]:
		assert_true(entry.contexts.has(context), "compass should declare a %s context" % context)
	for state in ["pristine", "used", "worn", "broken"]:
		assert_true(entry.states.has(state), "compass should have the %s state" % state)
	for animation in ["still", "pose_b", "pose_c", "pose_d"]:
		assert_true(entry.animations.has(animation), "compass should declare the %s animation" % animation)


func test_rough_compass_held_is_condition_tied():
	# Unlike plain compass: rough_compass's held row shows a visibly
	# fraying/broken cord by the "broken" column -- real condition
	# progression, not pose variety, so held needs no extra animations
	# beyond "still" (one frame per state, same as icon/equipped/ground).
	var entry := registry.entry_for("rough_compass")
	for context in ["icon", "held", "equipped", "ground"]:
		assert_true(entry.contexts.has(context), "rough_compass should declare a %s context" % context)
	for state in ["pristine", "used", "worn", "broken"]:
		assert_true(entry.states.has(state), "rough_compass should have the %s state" % state)


func test_weather_glass_held_is_condition_tied():
	# The glass orb visibly cracks by the "broken" column -- condition-tied.
	var entry := registry.entry_for("weather_glass")
	for context in ["icon", "held", "equipped", "ground"]:
		assert_true(entry.contexts.has(context), "weather_glass should declare a %s context" % context)
	for state in ["pristine", "used", "worn", "broken"]:
		assert_true(entry.states.has(state), "weather_glass should have the %s state" % state)


func test_butterfly_net_held_is_condition_tied():
	# The net visibly tears/drips by the "broken" column -- condition-tied.
	# Supersedes the old 3-state (pristine/worn/broken) icon-only entry.
	var entry := registry.entry_for("butterfly_net")
	for context in ["icon", "held", "equipped", "ground"]:
		assert_true(entry.contexts.has(context), "butterfly_net should declare a %s context" % context)
	for state in ["pristine", "used", "worn", "broken"]:
		assert_true(entry.states.has(state), "butterfly_net should have the %s state" % state)


func test_saw_held_is_condition_tied():
	# The blade visibly chips by the "broken" column -- condition-tied.
	# Supersedes the old 3-state (pristine/worn/broken) icon-only entry.
	var entry := registry.entry_for("saw")
	for context in ["icon", "held", "equipped", "ground"]:
		assert_true(entry.contexts.has(context), "saw should declare a %s context" % context)
	for state in ["pristine", "used", "worn", "broken"]:
		assert_true(entry.states.has(state), "saw should have the %s state" % state)


# -- 2026-09-08 batch, second pass: the remaining 12 real catalog items.
# Same "hand-verify per item" discipline -- held-row pose count and
# condition-vs-pose-variety semantics vary per item, confirmed by direct
# visual inspection, not assumed uniform.

func _assert_standard_item_shape(item_id: String, held_pose_count: int) -> void:
	var entry := registry.entry_for(item_id)
	for context in ["icon", "held", "equipped", "ground"]:
		assert_true(entry.contexts.has(context), "%s should declare a %s context" % [item_id, context])
	for state in ["pristine", "used", "worn", "broken"]:
		assert_true(entry.states.has(state), "%s should have the %s state" % [item_id, state])
	var pose_names := ["still", "pose_b", "pose_c", "pose_d", "pose_e", "pose_f", "pose_g", "pose_h"]
	for i in held_pose_count:
		assert_true(
			entry.animations.has(pose_names[i]),
			"%s should declare the %s held animation" % [item_id, pose_names[i]]
		)


func test_charter_held_is_pose_variety_with_seven_poses():
	_assert_standard_item_shape("charter", 7)


func test_deed_held_is_pose_variety_with_four_poses():
	_assert_standard_item_shape("deed", 4)


func test_field_journal_held_is_pose_variety_with_six_poses():
	_assert_standard_item_shape("field_journal", 6)


func test_ledger_held_is_pose_variety_with_six_poses():
	_assert_standard_item_shape("ledger", 6)


func test_fishing_rod_held_is_pose_variety_with_eight_poses():
	_assert_standard_item_shape("fishing_rod", 8)


func test_spyglass_held_is_pose_variety_with_six_poses():
	_assert_standard_item_shape("spyglass", 6)


func test_star_chart_held_is_pose_variety_with_six_poses():
	_assert_standard_item_shape("star_chart", 6)


func test_iron_axe_held_is_pose_variety_with_six_poses():
	_assert_standard_item_shape("iron_axe", 6)


func test_iron_sword_held_is_pose_variety_with_six_poses():
	# Supersedes the old 3-state (pristine/worn/broken) icon-only entry --
	# no real attack-swing art exists in this batch, so unlike wooden_club
	# this entry gains no "attack" animation.
	_assert_standard_item_shape("iron_sword", 6)


func test_torch_held_is_pose_variety_with_six_poses():
	_assert_standard_item_shape("torch", 6)


func test_worm_held_is_pose_variety_with_eight_poses():
	_assert_standard_item_shape("worm", 8)


func test_map_held_is_condition_tied():
	# The map visibly tears/splits by the "broken" column -- condition-tied,
	# unlike this batch's other scroll/document items.
	var entry := registry.entry_for("map")
	for context in ["icon", "held", "equipped", "ground"]:
		assert_true(entry.contexts.has(context), "map should declare a %s context" % context)
	for state in ["pristine", "used", "worn", "broken"]:
		assert_true(entry.states.has(state), "map should have the %s state" % state)


func test_wooden_club_held_is_pose_variety_with_eight_poses():
	# 8 real pose variants of the pristine state (verified: none show wear,
	# unlike the icon/equipped/ground rows' own real broken-state art) --
	# adds to, does not replace, the pilot's own existing attack/block/still
	# animations and pristine/worn/broken states.
	var entry := registry.entry_for("wooden_club")
	for context in ["equipped", "ground"]:
		assert_true(entry.contexts.has(context), "wooden_club should declare a %s context" % context)
	assert_true(entry.states.has("used"), "wooden_club should gain the used state")
	for animation in ["still", "pose_b", "pose_c", "pose_d", "pose_e", "pose_f", "pose_g", "pose_h"]:
		assert_true(entry.animations.has(animation), "wooden_club should declare the %s animation" % animation)
	# the pilot's own original shape must still hold
	assert_true(entry.animations.has("attack"))
	assert_true(entry.animations.has("block"))


# -- 2026-09-13 armor batch: the remaining 7 armor items (3 leather, 4
# iron), generated fresh via ChatGPT using leather_helm/iron_helm as style
# references. Same shape as leather_helm throughout -- icon/equipped/ground,
# no held (you don't swing a chestplate/greaves/boots), 4-state durability --
# so one shared helper suffices; no held-row semantics to hand-verify here
# since armor never has a held context at all.

func _assert_armor_shape(item_id: String) -> void:
	var entry := registry.entry_for(item_id)
	assert_true(entry.contexts.has("icon"), "%s should declare an icon context" % item_id)
	assert_true(entry.contexts.has("equipped"), "%s should declare an equipped context" % item_id)
	assert_true(entry.contexts.has("ground"), "%s should declare a ground context" % item_id)
	assert_false(entry.contexts.has("held"), "%s is armor, you don't swing it" % item_id)
	for state in ["pristine", "used", "worn", "broken"]:
		assert_true(entry.states.has(state), "%s should have the %s state" % [item_id, state])


func test_leather_chest_entry_has_the_documented_shape():
	_assert_armor_shape("leather_chest")


func test_leather_legs_entry_has_the_documented_shape():
	_assert_armor_shape("leather_legs")


func test_leather_boots_entry_has_the_documented_shape():
	_assert_armor_shape("leather_boots")


func test_iron_helm_entry_has_the_documented_shape():
	_assert_armor_shape("iron_helm")


func test_iron_chest_entry_has_the_documented_shape():
	_assert_armor_shape("iron_chest")


func test_iron_legs_entry_has_the_documented_shape():
	_assert_armor_shape("iron_legs")


func test_iron_boots_entry_has_the_documented_shape():
	_assert_armor_shape("iron_boots")


# -- 2026-09-13 placeables batch: sagewerk/storage/stone_dam have no fire
# (unlike campfire/furnace) and no wear mechanic of their own (unlike
# equipment), so unlike every other subject touched this session they keep
# their original single "default" state -- only icon+ground gain real art.
# No held/equipped (nothing to carry or wear), and "placed" stays out of
# scope here the same way it does for furnace/campfire's own deferred
# footprint surface.

func _assert_icon_and_ground_only_shape(item_id: String) -> void:
	var entry := registry.entry_for(item_id)
	assert_true(entry.contexts.has("icon"), "%s should declare an icon context" % item_id)
	assert_true(entry.contexts.has("ground"), "%s should declare a ground context" % item_id)
	assert_eq(entry.contexts.ground.anchor, "center")
	assert_false(entry.contexts.has("held"), "%s is a placeable, not carried" % item_id)
	assert_false(entry.contexts.has("equipped"), "%s is a placeable, not worn" % item_id)


func test_sagewerk_entry_has_the_documented_shape():
	_assert_icon_and_ground_only_shape("sagewerk")


func test_storage_entry_has_the_documented_shape():
	_assert_icon_and_ground_only_shape("storage")


func test_stone_dam_entry_has_the_documented_shape():
	_assert_icon_and_ground_only_shape("stone_dam")


# -- 2026-09-13 tools batch: the final 5 items (lasso, snare, trap,
# reinforced_rope, climbing_rope) -- every one a carryable tool, so every
# one gets the full icon/held/equipped/ground row set (item_illustrations.md's
# own "every tool/weapon gets equipped too" correction), all condition-tied
# (a rope visibly frays and an iron ring visibly rusts by the broken column;
# none of these got a pose-variety held row the way e.g. compass did).
# climbing_rope is a brand-new entry -- it had no registry entry at all
# before this pass, unlike the other four which had icon-only stubs.

func test_lasso_entry_has_the_documented_shape():
	_assert_standard_item_shape("lasso", 1)


func test_snare_entry_has_the_documented_shape():
	_assert_standard_item_shape("snare", 1)


func test_trap_entry_has_the_documented_shape():
	_assert_standard_item_shape("trap", 1)


func test_reinforced_rope_entry_has_the_documented_shape():
	_assert_standard_item_shape("reinforced_rope", 1)


func test_climbing_rope_entry_has_the_documented_shape():
	_assert_standard_item_shape("climbing_rope", 1)


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


## The sweep docs/concept/illustrated_art_addressing.md's own Status list
## deferred: *"the 'every file under assets/sprites/<subject>/ is
## addressable' sweep test this doc originally specified -- there is no real
## art under this convention on disk yet for that test to sweep, so it is
## deferred to whichever migration actually authors files"*.
##
## There is now. ~100 subjects carry real art, and the sweep immediately
## earns its keep: `stone_axe` and `stone_blade` had 16 and 20 files each
## on disk and no registry entry at all, so they resolved straight past
## their own art to the procedural sprite while their neighbours
## (`iron_axe`, `crude_blade`) drew properly.
const _ART_ROOT := "res://assets/sprites"


func _subjects_with_art_on_disk() -> Array:
	var found: Array = []
	var root := DirAccess.open(_ART_ROOT)
	if root == null:
		fail_test("cannot open %s" % _ART_ROOT)
		return found
	for subject in root.get_directories():
		# <subject>/<context>/<season>/<state>/<animation>.png -- a subject
		# is "on the convention" the moment one address-shaped file exists.
		var contexts := DirAccess.open("%s/%s" % [_ART_ROOT, subject])
		if contexts == null:
			continue
		for context in contexts.get_directories():
			var seasons := DirAccess.open("%s/%s/%s" % [_ART_ROOT, subject, context])
			if seasons == null:
				continue
			for season in seasons.get_directories():
				var states := DirAccess.open("%s/%s/%s/%s" % [_ART_ROOT, subject, context, season])
				if states == null:
					continue
				for state in states.get_directories():
					var files := DirAccess.open(
						"%s/%s/%s/%s/%s" % [_ART_ROOT, subject, context, season, state]
					)
					if files == null:
						continue
					for file in files.get_files():
						if file.ends_with(".png"):
							found.append(subject)
							break
					if found.has(subject):
						break
				if found.has(subject):
					break
			if found.has(subject):
				break
	return found


func test_every_subject_with_real_art_on_disk_is_declared():
	var registry = IllustratedArtRegistry.new()
	var undeclared: Array = []
	for subject in _subjects_with_art_on_disk():
		if not registry.has_subject(subject):
			undeclared.append(subject)
	assert_eq(
		undeclared, [],
		"art on disk that no registry entry can reach draws the procedural sprite instead"
	)


## And the contexts that art is drawn in are declared too -- a subject
## declared icon-only while `held`/`equipped`/`ground` art sits on disk
## still cannot reach three quarters of its own pictures.
func test_every_context_with_real_art_on_disk_is_declared():
	var registry = IllustratedArtRegistry.new()
	var missing: Array = []
	for subject in _subjects_with_art_on_disk():
		if not registry.has_subject(subject):
			continue
		var declared: Dictionary = registry.entry_for(subject).get("contexts", {})
		var dir := DirAccess.open("%s/%s" % [_ART_ROOT, subject])
		for context in dir.get_directories():
			if not declared.has(context):
				missing.append("%s/%s" % [subject, context])
	assert_eq(missing, [], "these contexts have art on disk but no declaration to reach it")
