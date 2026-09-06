extends RefCounted

## Procedural "crushed" fallback for a small creature with no dedicated
## crushed artwork of its own (see docs/concept/soil_fauna.md's "Crushed
## underfoot" family). CaterpillarMarker, AntForagerMarker, and
## DecomposerMarker all reuse this identical transform rather than each
## inventing their own -- three real call sites clears this codebase's own
## "three similar things beats a premature abstraction" bar (worm and
## millipede don't need this at all: a worm already has real "die" art plus
## corpse/recovery state, and millipede.png's own "crushed" row is real,
## delivered art, see MillipedeMarker.crush()).
##
## Applied directly to whatever sprite a marker is already showing at the
## moment it dies, so no new art asset is needed: flattens it vertically (a
## real squash) and tints it dark/reddish (a real "no longer alive" tell) --
## matching millipede.png's own crushed-row description in spirit ("a level
## crawl transitioning into a flattened, splattered pose") without needing
## bespoke art to draw it.

## How much a crushed sprite flattens vertically -- pinned by
## test_apply_flattens_the_sprite_vertically, not eyeballed. Only the
## vertical axis changes: a squash spreads a body outward as it flattens in
## real life, but widening the sprite too would fight whatever horizontal
## scale a species-specific marker_scale already set, so this stays a pure
## Y-axis flatten, the least invasive change that still reads as "crushed
## flat" at a glance.
const VERTICAL_SQUASH := 0.35

## How dark/red a crushed sprite tints -- pinned by
## test_apply_tints_the_sprite_dark_and_reddish, not eyeballed. Replaces the
## sprite's own default (Color(1, 1, 1, 1)) outright rather than multiplying
## against it: every caller applies this to a sprite mid-frame that has
## never been tinted for any other reason, so there is nothing else to
## preserve underneath.
const TINT := Color(0.55, 0.15, 0.12)

## How long the flattened mark stays visible before the marker actually
## frees itself -- long enough to register as a real event, short enough
## that a stepped-on patch of ground doesn't stay littered with corpses
## forever. Pinned by test_linger_seconds_is_a_real_pinned_constant.
const LINGER_SECONDS := 2.0


static func apply(sprite: Sprite2D) -> void:
	sprite.scale.y = VERTICAL_SQUASH
	sprite.modulate = TINT
