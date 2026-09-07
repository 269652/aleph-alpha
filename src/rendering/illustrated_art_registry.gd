extends RefCounted

## The subject declarations for docs/concept/illustrated_art_addressing.md's
## addressing convention -- a plain const Dictionary, the same shape every
## other `_SHEETS` dict in src/rendering/ already uses (see
## illustrated_item_sprite.gd's own `_SHEETS`, the two-row wooden_club
## pilot this new convention supersedes -- see that doc's own "Migration"
## section), keyed by subject id (matching `Item.sprite_id` for items, so
## a crafted variant sharing a base item's art keeps working with no
## second entry).
##
## Holds only what a file path itself cannot say. Per-file existence is
## discovered from the real `assets/sprites/<subject>/...` tree at resolve
## time (see illustrated_art_resolver.gd) -- nothing here says which of a
## subject's declared season/state/animation combinations are actually
## drawn yet, so dropping in a newly generated file is never a registry
## edit (the doc's own "Per file, nothing is stored").
##
## `wooden_club` and `campfire` are the doc's own two full worked examples
## (non-seasonal+pivot vs. seasonal+footprint), proving this entry shape
## against both documented axes. Every other entry below is bare icon-only
## scaffolding for the first 100 ItemCatalog ids (see tests/unit/
## test_item_icon_registry_coverage.gd) -- one un-differentiated "default"
## state, one static "still" frame, `center` anchor: the minimum needed to
## be addressable at all. None of these ~100 subjects has any real art
## under this convention yet -- see the doc's own Status checklist for
## what's still ⬜, and item_illustrations.md's "Icon" states-table row for
## why coverage stops at icon (ground/held/placed reuse it by fallback, or
## are each their own separately-named, still-unstarted piece of work).

const _SUBJECTS := {
	"wooden_club": {
		"contexts": {
			"held": {"seasonal": false, "anchor": "pivot"},
			# Declared explicitly rather than left to the documented (but,
			# per this doc's own Status notes, not actually implemented)
			# icon-falls-back-to-held direction -- see item_icon_registry_
			# coverage.gd, which requires every one of the first 100
			# ItemCatalog ids to declare this context directly.
			"icon": {"seasonal": false, "anchor": "center"},
		},
		"base_season": "any",
		"states": ["pristine", "worn", "broken"],
		"base_state": "pristine",
		"animations": {
			# item_illustrations.md "Combat sheets": 8 frames, wind-up
			# 1-3/release 4-5/recovery 6-8, one-shot (not a loop).
			"attack": {"fps": 8, "loop": false},
			# is_blocking() is a held LEVEL, not a momentary swing -- one
			# static pose, not a cycle.
			"block": {"fps": 0, "loop": false},
			"still": {"fps": 0, "loop": false},
		},
		"overlays": [],
		"chroma_key": Color(1.0, 0.0, 1.0),
		"chroma_key_tolerance": 0.25,
	},
	"campfire": {
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
		"overlays": ["snowed"],
		"chroma_key": Color(1.0, 0.0, 1.0),
		"chroma_key_tolerance": 0.25,
	},

	# -- Icon-only scaffolding for the first 100 ItemCatalog ids (see -------
	# -- tests/unit/test_item_icon_registry_coverage.gd) --------------------
	#
	# Bare `icon` context, one un-differentiated "default" state, one static
	# "still" frame -- the minimum a subject needs to be addressable at all,
	# matching pillar 4 ("author the base, fill in the rest"): no real art
	# exists on disk for any of these yet, so every one of them resolves
	# through to the procedural fallback today exactly as it did before this
	# pass (rule 5, "subject -> procedural" -- has_subject/entry_for existing
	# is what changes, not what a caller currently sees on screen). Grouped
	# and ordered to mirror item_catalog.gd's own `_ITEMS` groupings
	# one-for-one, so the two files can be read side by side. iron_sword and
	# crude_blade use wooden_club's own real pristine/worn/broken vocabulary
	# instead of the generic "default" state -- item_durability.md already
	# models real wear for exactly these three weapons (see item_catalog.gd's
	# own _WEAPON_MATERIAL_AND_VOLUME comment), so declaring it here is
	# accurate, not presumptive -- only their `held`/attack art (wooden_club's
	# own still-pilot-only combat sheet) is out of scope for this pass.

	"hide": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"meat": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"fang": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"fruit": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"nut": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"cherry": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"apple": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"walnut": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"acorn": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"hazelnut": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"pine": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"fly_agaric": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"psylo": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"black_trumpet": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"champignon": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"chanterelle": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"parasol": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"death_cap": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"false_death_cap": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"fly_agaric_bitten": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"psylo_bitten": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"black_trumpet_bitten": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"champignon_bitten": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"chanterelle_bitten": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"parasol_bitten": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"death_cap_bitten": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"false_death_cap_bitten": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"wood": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"iron_sword": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"iron_axe": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"torch": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"cooked_meat": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"rock": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"stick": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"sharp_shard": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"plant_fibre": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"lasso": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"carrot": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"potato": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"log": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"beam": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"plank": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"saw": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"crude_blade": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"stone": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"stone_pickaxe": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"iron_ore": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"copper_ore": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"coal": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"worm": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"fish": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"cooked_fish": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"trout": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"cooked_trout": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"bluegill": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"cooked_bluegill": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"koi": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"cooked_koi": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"goldfish": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"cooked_goldfish": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"rare_fish": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"legendary_fish": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"leather_helm": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"leather_chest": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"leather_legs": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"leather_boots": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"iron_ingot": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"copper_ingot": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"furnace": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"iron_helm": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"iron_chest": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"iron_legs": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"iron_boots": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"fishing_rod": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"sagewerk": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"storage": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"stone_dam": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"rough_compass": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"compass": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"map": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"spyglass": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"weather_glass": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"star_chart": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"deed": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"ledger": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"field_journal": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"charter": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"terminal_fragment": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"secret_room_token": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"wargames_punch_card": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"curious_keepsake": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"snare": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"butterfly_net": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"trap": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"reinforced_rope": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"jarred_insect": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"caged_songbird": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"glass_bottle": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
}


func has_subject(subject: String) -> bool:
	return _SUBJECTS.has(subject)


func entry_for(subject: String) -> Dictionary:
	return _SUBJECTS.get(subject, {})


## Every registered subject id, for callers that need to enumerate the
## whole catalog (a future "every declared address is resolvable or
## drawn" sweep test, a future prompt-printing tool) rather than look up
## one at a time.
func subjects() -> Array:
	return _SUBJECTS.keys()
