extends GutTest

## illustrated_art_resolver.gd -- see docs/concept/illustrated_art_addressing.md
## "Resolution: the fallback lattice". Pure logic, no engine/file-system
## dependency: address_exists is a caller-injected Callable, matching this
## codebase's own "inject the check, keep the class headlessly testable"
## convention (LeafLitterField.set_current_probe, AntColony's injected
## seeds, etc.) and directly answering the doc's own "a fixture tree of
## placeholder files" test requirement -- the fixture here is a plain
## Dictionary set of address strings, never real files.

const IllustratedArtResolver = preload("res://src/rendering/illustrated_art_resolver.gd")


## Builds an address_exists Callable from a flat list of "context/season/
## state/animation" strings -- the fixture tree.
func _fixture(existing: Array) -> Callable:
	var set := {}
	for address in existing:
		set[address] = true
	return func(context: String, season: String, state: String, animation: String):
		return set.has("%s/%s/%s/%s" % [context, season, state, animation])


func _wooden_club_entry() -> Dictionary:
	return {
		"contexts": {"held": {"seasonal": false, "anchor": "pivot"}},
		"base_season": "any",
		"states": ["pristine", "worn", "broken"],
		"base_state": "pristine",
		"animations": {
			"attack": {"fps": 8, "loop": false},
			"block": {"fps": 0, "loop": false},
			"still": {"fps": 0, "loop": false},
		},
	}


func _wooden_club_files() -> Array:
	return [
		"held/any/pristine/attack",
		"held/any/pristine/block",
		"held/any/worn/still",
		"held/any/broken/still",
	]


func _campfire_entry() -> Dictionary:
	return {
		"contexts": {
			"placed": {"seasonal": true, "anchor": "footprint"},
			"icon": {"seasonal": false, "anchor": "center"},
		},
		"base_season": "summer",
		"states": ["unlit", "lit", "embers"],
		"base_state": "unlit",
		"animations": {
			"still": {"fps": 0, "loop": false},
			"burn": {"fps": 8, "loop": true},
			"glow": {"fps": 4, "loop": true},
		},
	}


# -- exact match: zero axes relaxed --------------------------------------

func test_an_exact_match_resolves_with_no_axes_relaxed():
	var result: Dictionary = IllustratedArtResolver.resolve(
		"held", "any", "pristine", "attack", _wooden_club_entry(), _fixture(_wooden_club_files())
	)
	assert_false(result.is_procedural)
	assert_eq(result.context, "held")
	assert_eq(result.season, "any")
	assert_eq(result.state, "pristine")
	assert_eq(result.animation, "attack")


# -- the doc's own worked example: worn/attack -> pristine/attack --------
#
# docs/concept/illustrated_art_addressing.md's own worked example: "`worn/
# attack` resolves to `pristine/attack` (state -> base state), which is
# exactly the pilot's stated 'a worn club still swings using the pristine
# frames'". Both a state-only relaxation (pristine/attack, exists) AND an
# animation-only relaxation (worn/still, ALSO exists) are single-axis
# candidates here -- a genuine tie the doc's own numbered fallback list
# (which lists animation before state) does not actually produce; only
## preferring state's relaxation over animation's does. This is the load-
## bearing test for that resolved ambiguity (see the resolver's own doc
## comment).

func test_a_missing_state_specific_animation_prefers_relaxing_state_over_animation():
	var result: Dictionary = IllustratedArtResolver.resolve(
		"held", "any", "worn", "attack", _wooden_club_entry(), _fixture(_wooden_club_files())
	)
	assert_false(result.is_procedural)
	assert_eq(result.state, "pristine", "must relax STATE, keeping the requested animation")
	assert_eq(result.animation, "attack", "must NOT fall back to still -- a real single-axis match exists")


func test_a_missing_state_specific_block_pose_also_prefers_relaxing_state():
	# Same shape as the attack case, a second animation, to prove this is a
	# genuine tie-break rule and not a coincidence of "attack" specifically.
	var result: Dictionary = IllustratedArtResolver.resolve(
		"held", "any", "broken", "block", _wooden_club_entry(), _fixture(_wooden_club_files())
	)
	assert_eq(result.state, "pristine")
	assert_eq(result.animation, "block")


# -- season falls back to the subject's base season -----------------------

func test_a_season_with_nothing_drawn_falls_back_to_the_base_season():
	var files := ["placed/summer/unlit/still"]
	var result: Dictionary = IllustratedArtResolver.resolve(
		"placed", "winter", "unlit", "still", _campfire_entry(), _fixture(files)
	)
	assert_false(result.is_procedural)
	assert_eq(result.season, "summer", "a campfire with only summer drawn must show summer in December")
	assert_eq(result.state, "unlit")


# -- state falls back to the subject's base state --------------------------

func test_a_state_with_nothing_drawn_falls_back_to_the_base_state():
	var files := ["placed/summer/unlit/still"]
	var result: Dictionary = IllustratedArtResolver.resolve(
		"placed", "summer", "embers", "still", _campfire_entry(), _fixture(files)
	)
	assert_false(result.is_procedural)
	assert_eq(result.state, "unlit", "a campfire with no embers art must show unlit")
	assert_eq(result.season, "summer", "must not ALSO relax season -- summer was already correct")


# -- season and state both need relaxing, simultaneously -------------------
#
# "Author the base, fill in the rest ... a subject with two of fourteen
# files drawn still renders everywhere" -- the design pillar this whole
# lattice exists for. Neither season alone nor state alone resolves here;
# only relaxing BOTH does.

func test_a_season_and_state_that_both_need_relaxing_resolve_together():
	var files := ["placed/summer/unlit/still"]
	var result: Dictionary = IllustratedArtResolver.resolve(
		"placed", "winter", "embers", "still", _campfire_entry(), _fixture(files)
	)
	assert_false(result.is_procedural)
	assert_eq(result.season, "summer")
	assert_eq(result.state, "unlit")


# -- context falls back to icon --------------------------------------------

func test_a_context_with_nothing_drawn_falls_back_to_icon():
	# season requested as "any", matching what a real caller would pass for
	# a non-seasonal context lookup -- this resolver does NOT auto-
	# normalize season from a context's own `seasonal` declaration (see
	# the resolver's own doc comment, "Also NOT implemented"), so a
	# request that still asked for season="summer" here would need BOTH
	# context and season relaxed, a case this test deliberately avoids to
	# isolate context-relaxation on its own.
	var entry := _campfire_entry()
	var files := ["icon/any/unlit/still"]
	var result: Dictionary = IllustratedArtResolver.resolve(
		"placed", "any", "unlit", "still", entry, _fixture(files)
	)
	assert_false(result.is_procedural)
	assert_eq(result.context, "icon")


# -- nothing resolves at all: the procedural fallback -----------------------

func test_nothing_authored_at_all_falls_back_to_procedural():
	var result: Dictionary = IllustratedArtResolver.resolve(
		"placed", "summer", "unlit", "still", _campfire_entry(), _fixture([])
	)
	assert_true(result.is_procedural)


# -- the fixed tie-break priority itself, isolated from any real subject ---
#
# season < state < context < animation, tested directly against a minimal
# synthetic entry rather than wooden_club/campfire, so this pins the
# PRIORITY RULE itself rather than a property of either worked example.

func _synthetic_entry() -> Dictionary:
	return {"base_season": "base_season", "base_state": "base_state"}


func test_tie_break_prefers_relaxing_season_over_state_when_both_alone_would_resolve():
	var files := ["ctx/base_season/req_state/req_anim", "ctx/req_season/base_state/req_anim"]
	var result: Dictionary = IllustratedArtResolver.resolve(
		"ctx", "req_season", "req_state", "req_anim", _synthetic_entry(), _fixture(files)
	)
	assert_eq(result.season, "base_season")
	assert_eq(result.state, "req_state", "state must stay as requested -- season alone already resolved it")


func test_tie_break_prefers_relaxing_state_over_context_when_both_alone_would_resolve():
	var files := ["ctx/req_season/base_state/req_anim", "icon/req_season/req_state/req_anim"]
	var result: Dictionary = IllustratedArtResolver.resolve(
		"ctx", "req_season", "req_state", "req_anim", _synthetic_entry(), _fixture(files)
	)
	assert_eq(result.state, "base_state")
	assert_eq(result.context, "ctx", "context must stay as requested -- state alone already resolved it")


func test_tie_break_prefers_relaxing_context_over_animation_when_both_alone_would_resolve():
	var files := ["icon/req_season/req_state/req_anim", "ctx/req_season/req_state/still"]
	var result: Dictionary = IllustratedArtResolver.resolve(
		"ctx", "req_season", "req_state", "req_anim", _synthetic_entry(), _fixture(files)
	)
	assert_eq(result.context, "icon")
	assert_eq(result.animation, "req_anim", "animation must stay as requested -- context alone already resolved it")
