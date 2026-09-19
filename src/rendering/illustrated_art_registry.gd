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
			# 2026-09-13 (2026-09-08 batch integration): the full weapon row
			# set, per item_illustrations.md's "Per-item composite sheet
			# mapping".
			"equipped": {"seasonal": false, "anchor": "pivot"},
			"ground": {"seasonal": false, "anchor": "center"},
		},
		"base_season": "any",
		# "used" added 2026-09-13 -- durability generalizes to a 4-state
		# vocabulary (item_illustrations.md's same mapping section).
		"states": ["pristine", "used", "worn", "broken"],
		"base_state": "pristine",
		"animations": {
			# item_illustrations.md "Combat sheets": 8 frames, wind-up
			# 1-3/release 4-5/recovery 6-8, one-shot (not a loop).
			"attack": {"fps": 8, "loop": false},
			# is_blocking() is a held LEVEL, not a momentary swing -- one
			# static pose, not a cycle.
			"block": {"fps": 0, "loop": false},
			"still": {"fps": 0, "loop": false},
			# 2026-09-13: held's real art is 8 pose variants of the
			# pristine state only (hand-verified: none show wear, unlike
			# the icon/equipped/ground rows' own real broken-state art) --
			# pose variety, not a second condition axis.
			"pose_b": {"fps": 0, "loop": false},
			"pose_c": {"fps": 0, "loop": false},
			"pose_d": {"fps": 0, "loop": false},
			"pose_e": {"fps": 0, "loop": false},
			"pose_f": {"fps": 0, "loop": false},
			"pose_g": {"fps": 0, "loop": false},
			"pose_h": {"fps": 0, "loop": false},
		},
		"overlays": [],
		"chroma_key": Color(1.0, 0.0, 1.0),
		"chroma_key_tolerance": 0.25,
	},
	"campfire": {
		"contexts": {
			"placed": {"seasonal": true, "anchor": "footprint"},
			"icon": {"seasonal": false, "anchor": "center"},
			"ground": {"seasonal": false, "anchor": "center"},
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
	# 2026-09-13 (2026-09-08 batch): a weapon, but no real attack-swing art
	# exists in this batch (unlike wooden_club's own pilot) -- held is 6
	# pose variants of pristine only, hand-verified, no "attack" animation
	# added since there is no real art for it yet. Supersedes the old
	# 3-state icon-only entry.
	"iron_sword": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "pose_b": {"fps": 0, "loop": false}, "pose_c": {"fps": 0, "loop": false}, "pose_d": {"fps": 0, "loop": false}, "pose_e": {"fps": 0, "loop": false}, "pose_f": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13: held is 6 pose variants of pristine only (hand-verified:
	# none show wear).
	"iron_axe": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "pose_b": {"fps": 0, "loop": false}, "pose_c": {"fps": 0, "loop": false}, "pose_d": {"fps": 0, "loop": false}, "pose_e": {"fps": 0, "loop": false}, "pose_f": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-19: stone_axe and stone_blade had real art on disk -- 16 and
	# 20 files, the same four-context/four-state batch as iron_axe and
	# crude_blade beside them -- and no entry here at all, so both resolved
	# straight past their own pictures to the procedural sprite. Found by
	# the doc's own deferred sweep (test_every_subject_with_real_art_on_
	# disk_is_declared), which could only be written once real art existed.
	"stone_axe": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "pose_b": {"fps": 0, "loop": false}, "pose_c": {"fps": 0, "loop": false}, "pose_d": {"fps": 0, "loop": false}, "pose_e": {"fps": 0, "loop": false}, "pose_f": {"fps": 0, "loop": false}, "pose_g": {"fps": 0, "loop": false}, "pose_h": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13: torch's own icon/equipped/ground rows show a real
	# bright-to-extinguished progression -- kept on the same
	# pristine/used/worn/broken vocabulary the rest of this batch uses
	# (uniform across the whole batch), not a special fire-status axis, for
	# consistency; held is 6 pose variants of pristine only.
	"torch": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "pose_b": {"fps": 0, "loop": false}, "pose_c": {"fps": 0, "loop": false}, "pose_d": {"fps": 0, "loop": false}, "pose_e": {"fps": 0, "loop": false}, "pose_f": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# Storm Lantern (docs/concept/lighting.md) -- mirrors torch's own entry
	# just above; no real art drawn yet, same as most of this file's ~100
	# icon-only scaffolding entries (see this file's own header comment).
	"lantern": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"cooked_meat": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"rock": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"stick": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"sharp_shard": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"plant_fibre": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"lasso": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"carrot": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"potato": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"log": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"beam": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"plank": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13: the blade visibly chips by the broken column --
	# condition-tied. Real art integrated from the 2026-09-08 batch,
	# superseding the old flat assets/sprites/items/saw.png.
	"saw": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13: the full weapon row set (icon/held/equipped/ground) and a
	# real attack swing -- pristine-state frames only, the resolver's own
	# state->base_state fallback already serves them for worn/broken (the
	# same "a worn club still swings using the pristine frames" rule).
	"crude_blade": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "attack": {"fps": 8, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"stone_blade": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "attack": {"fps": 8, "loop": false}, "pose_b": {"fps": 0, "loop": false}, "pose_c": {"fps": 0, "loop": false}, "pose_d": {"fps": 0, "loop": false}, "pose_e": {"fps": 0, "loop": false}, "pose_f": {"fps": 0, "loop": false}, "pose_g": {"fps": 0, "loop": false}, "pose_h": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"stone": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13 (item_illustrations.md "Per-item composite sheet mapping"):
	# a tool -- the full icon/held/equipped/ground row set (equipped =
	# strapped to a belt/back when not in hand, same as any carryable
	# weapon or tool), real 4-state durability (pristine/used/worn/broken)
	# generalized beyond the original three combat items. Real art
	# integrated from the 2026-09-08 batch: held has 4 real pose variants
	# (still/pose_b/pose_c/pose_d) of the pristine state only -- pose
	# variety, not tied to the durability axis (the resolver's own
	# state->base_state fallback serves them for used/worn/broken).
	"stone_pickaxe": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "pose_b": {"fps": 0, "loop": false}, "pose_c": {"fps": 0, "loop": false}, "pose_d": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"iron_ore": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"copper_ore": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"coal": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	# 2026-09-13: held is 8 pose variants of pristine only.
	"worm": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "pose_b": {"fps": 0, "loop": false}, "pose_c": {"fps": 0, "loop": false}, "pose_d": {"fps": 0, "loop": false}, "pose_e": {"fps": 0, "loop": false}, "pose_f": {"fps": 0, "loop": false}, "pose_g": {"fps": 0, "loop": false}, "pose_h": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

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

	# 2026-09-13: armor -- icon/equipped/ground, no held (you don't swing a
	# helmet). Armor wears too (item_durability.md's own open question,
	# resolved this pass), so it gets the same 4-state vocabulary.
	"leather_helm": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"leather_chest": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"leather_legs": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"leather_boots": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"iron_ingot": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"copper_ingot": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13: a placeable -- icon/ground plus its own "placed" surface
	# (footprint anchor, mirroring campfire exactly), sharing campfire's own
	# fire-status vocabulary (unlit/lit/embers) rather than durability --
	# whether a furnace is lit is its condition axis, not wear.
	"furnace": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "ground": {"seasonal": false, "anchor": "center"}, "placed": {"seasonal": false, "anchor": "footprint"}}, "base_season": "any", "states": ["unlit", "lit", "embers"], "base_state": "unlit", "animations": {"still": {"fps": 0, "loop": false}, "burn": {"fps": 8, "loop": true}, "glow": {"fps": 4, "loop": true}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"iron_helm": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"iron_chest": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"iron_legs": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"iron_boots": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	# 2026-09-13: held is 8 pose variants of pristine only.
	"fishing_rod": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "pose_b": {"fps": 0, "loop": false}, "pose_c": {"fps": 0, "loop": false}, "pose_d": {"fps": 0, "loop": false}, "pose_e": {"fps": 0, "loop": false}, "pose_f": {"fps": 0, "loop": false}, "pose_g": {"fps": 0, "loop": false}, "pose_h": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"sagewerk": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"storage": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"stone_dam": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	# 2026-09-13: rough_compass's held row shows a visibly fraying cord by
	# the broken column -- condition-tied like icon/equipped/ground, not
	# pose variety.
	"rough_compass": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13: compass's held row is pure pose variety (4 poses, all
	# undamaged) of the pristine state -- unlike rough_compass.
	"compass": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "pose_b": {"fps": 0, "loop": false}, "pose_c": {"fps": 0, "loop": false}, "pose_d": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13: the unfolded map visibly tears/splits by the broken
	# column -- condition-tied, unlike this batch's other scroll/document
	# items (charter/deed/field_journal/ledger/star_chart), whose held rows
	# are pure pose variety instead.
	"map": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13: held is 6 pose variants of pristine only.
	"spyglass": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "pose_b": {"fps": 0, "loop": false}, "pose_c": {"fps": 0, "loop": false}, "pose_d": {"fps": 0, "loop": false}, "pose_e": {"fps": 0, "loop": false}, "pose_f": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13: the glass orb visibly cracks by the broken column --
	# condition-tied.
	"weather_glass": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13: held is 6 pose variants of pristine only.
	"star_chart": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "pose_b": {"fps": 0, "loop": false}, "pose_c": {"fps": 0, "loop": false}, "pose_d": {"fps": 0, "loop": false}, "pose_e": {"fps": 0, "loop": false}, "pose_f": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13: held is 4 pose variants of pristine only.
	"deed": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "pose_b": {"fps": 0, "loop": false}, "pose_c": {"fps": 0, "loop": false}, "pose_d": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13: held is 6 pose variants of pristine only.
	"ledger": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "pose_b": {"fps": 0, "loop": false}, "pose_c": {"fps": 0, "loop": false}, "pose_d": {"fps": 0, "loop": false}, "pose_e": {"fps": 0, "loop": false}, "pose_f": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13: held is 6 pose variants of pristine only.
	"field_journal": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "pose_b": {"fps": 0, "loop": false}, "pose_c": {"fps": 0, "loop": false}, "pose_d": {"fps": 0, "loop": false}, "pose_e": {"fps": 0, "loop": false}, "pose_f": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13: held is 7 pose variants of pristine only (unevenly sized
	# cells -- 3 flat poses + 3 rolled-scroll poses + 1 more flat pose,
	# hand-measured, not a uniform 7-way split).
	"charter": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}, "pose_b": {"fps": 0, "loop": false}, "pose_c": {"fps": 0, "loop": false}, "pose_d": {"fps": 0, "loop": false}, "pose_e": {"fps": 0, "loop": false}, "pose_f": {"fps": 0, "loop": false}, "pose_g": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"terminal_fragment": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"secret_room_token": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"wargames_punch_card": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"curious_keepsake": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["default"], "base_state": "default", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

	"snare": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	# 2026-09-13: the net visibly tears/drips by the broken column --
	# condition-tied. Real art integrated from the 2026-09-08 batch,
	# superseding the old flat assets/sprites/items/butterfly_net.png.
	"butterfly_net": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"trap": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"reinforced_rope": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},
	"climbing_rope": {"contexts": {"icon": {"seasonal": false, "anchor": "center"}, "held": {"seasonal": false, "anchor": "pivot"}, "equipped": {"seasonal": false, "anchor": "pivot"}, "ground": {"seasonal": false, "anchor": "center"}}, "base_season": "any", "states": ["pristine", "used", "worn", "broken"], "base_state": "pristine", "animations": {"still": {"fps": 0, "loop": false}}, "overlays": [], "chroma_key": Color(1.0, 0.0, 1.0), "chroma_key_tolerance": 0.25},

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
