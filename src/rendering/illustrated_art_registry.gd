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
## Two subjects so far, mirroring the doc's own two full worked examples
## exactly (non-seasonal+pivot vs. seasonal+footprint), so this entry
## shape is proven against both axes documented so far rather than just
## one. Neither has any real art under this convention yet -- see that
## doc's own Status checklist for what's still ⬜.

const _SUBJECTS := {
	"wooden_club": {
		"contexts": {
			"held": {"seasonal": false, "anchor": "pivot"},
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
