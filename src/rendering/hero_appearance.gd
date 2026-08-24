extends RefCounted

## The hero look engine: a character's full visual identity, either rolled
## from a DNA seed (`appearance_for`) or picked explicitly in the character
## creator (`appearance_from_choices`).
##
## The CLASS/occupation declares itself through the outfit palette (warrior in
## battle red with gold trim, mage in deep arcane blue with silver, ranger in
## forest leather with bronze), while the person wearing it is individualized
## across five customization axes -- skin tone, hair color, hair style, beard
## style, eye color. Same (class, seed) always yields the same hero; rendered
## by ProceduralCharacterSprite's hero generators and worn by CharacterView.
##
## This is the concrete slice of the concept docs' DNA-drives-phenotype pillar
## (dna.md's "DNA-Driven Phenotype/Body Generation") applied to the player
## character: appearance derives from identity data, never hand-picked --
## while still letting a player deliberately author their own at creation.

## Per-class/occupation outfit palettes: tunic (torso), trim (belt/accents),
## legs. Player classes and villager occupations (see NpcIdentity.OCCUPATIONS,
## worn by VillageRenderer's NPC markers) share this one table -- both are
## "what role determines the outfit", the same idea this engine already models.
const CLASS_PALETTES := {
	"warrior": {
		"tunic": Color(0.68, 0.2, 0.16), "trim": Color(0.88, 0.72, 0.28), "legs": Color(0.32, 0.3, 0.34),
	},
	"mage": {
		"tunic": Color(0.24, 0.28, 0.66), "trim": Color(0.78, 0.82, 0.9), "legs": Color(0.16, 0.16, 0.3),
	},
	"ranger": {
		"tunic": Color(0.24, 0.44, 0.2), "trim": Color(0.66, 0.46, 0.2), "legs": Color(0.34, 0.26, 0.16),
	},
	"beastmaster": {
		"tunic": Color(0.5, 0.38, 0.18), "trim": Color(0.75, 0.6, 0.3), "legs": Color(0.3, 0.24, 0.15),
	},
	"artisan": {
		"tunic": Color(0.52, 0.42, 0.3), "trim": Color(0.7, 0.65, 0.5), "legs": Color(0.3, 0.28, 0.24),
	},
	"herbalist": {
		"tunic": Color(0.3, 0.52, 0.42), "trim": Color(0.7, 0.55, 0.72), "legs": Color(0.24, 0.32, 0.28),
	},
	"overseer": {
		"tunic": Color(0.42, 0.36, 0.5), "trim": Color(0.8, 0.76, 0.5), "legs": Color(0.26, 0.24, 0.32),
	},
	"farmer": {
		"tunic": Color(0.62, 0.5, 0.24), "trim": Color(0.4, 0.3, 0.14), "legs": Color(0.36, 0.28, 0.18),
	},
	"blacksmith": {
		"tunic": Color(0.32, 0.3, 0.32), "trim": Color(0.7, 0.36, 0.14), "legs": Color(0.2, 0.19, 0.2),
	},
	"merchant": {
		"tunic": Color(0.5, 0.24, 0.56), "trim": Color(0.86, 0.7, 0.24), "legs": Color(0.3, 0.24, 0.34),
	},
	"guard": {
		"tunic": Color(0.28, 0.34, 0.46), "trim": Color(0.72, 0.74, 0.78), "legs": Color(0.22, 0.24, 0.28),
	},
	"fisher": {
		"tunic": Color(0.22, 0.5, 0.52), "trim": Color(0.8, 0.72, 0.5), "legs": Color(0.24, 0.3, 0.32),
	},
}
const _FALLBACK_CLASS := "warrior"

## DNA-picked pools spanning a natural human range.
const SKIN_TONES := [
	Color(0.96, 0.82, 0.69), Color(0.90, 0.73, 0.58), Color(0.80, 0.61, 0.44),
	Color(0.66, 0.47, 0.32), Color(0.50, 0.35, 0.24), Color(0.36, 0.25, 0.18),
]
const HAIR_COLORS := [
	Color(0.14, 0.11, 0.09), Color(0.32, 0.20, 0.12), Color(0.52, 0.33, 0.16),
	Color(0.78, 0.62, 0.30), Color(0.65, 0.28, 0.11), Color(0.75, 0.75, 0.78),
	Color(0.45, 0.30, 0.55),
]
const EYE_COLORS := [
	Color(0.22, 0.16, 0.10), Color(0.20, 0.42, 0.28), Color(0.20, 0.38, 0.62),
	Color(0.38, 0.34, 0.30),
]

## Hair silhouettes ProceduralCharacterSprite can draw, in index order.
const HAIR_STYLES := ["short", "swept", "long", "ponytail", "topknot", "bald"]
## Kept as a named constant (rather than a bare literal) so callers and tests
## read the count from one place.
const HAIR_STYLE_COUNT := 6

## Facial hair silhouettes, in index order.
const BEARD_STYLES := ["none", "stubble", "goatee", "full"]
const BEARD_STYLE_COUNT := 4

## The customization axes a character creator can cycle through, and how many
## options each has -- so the creator UI never hard-codes pool sizes.
## Accent/trim color -- independent of class (previously always the class's
## own fixed palette.trim, no player choice at all). Matches dna.md's
## resolved "cosmetics layer on top" pillar: dye/accent color is exactly the
## kind of thing that customizes without touching what the class itself
## communicates (tunic/legs stay class-derived, only the accent is free).
const TRIM_COLORS := [
	Color(0.88, 0.72, 0.28),  # gold
	Color(0.82, 0.85, 0.9),  # silver
	Color(0.7, 0.36, 0.14),  # copper
	Color(0.72, 0.16, 0.16),  # crimson
	Color(0.24, 0.56, 0.36),  # verdant
	Color(0.42, 0.32, 0.62),  # amethyst
]
## Names in TRIM_COLORS order, for the creator's axis readout.
const TRIM_NAMES := ["Gold", "Silver", "Copper", "Crimson", "Verdant", "Amethyst"]

const AXES := ["skin", "hair_color", "hair_style", "beard", "eyes", "trim"]


## How many options a customization axis offers. 0 for an unknown axis
## (fail-safe: a creator cycling it simply can't move).
func option_count(axis: String) -> int:
	match axis:
		"skin":
			return SKIN_TONES.size()
		"hair_color":
			return HAIR_COLORS.size()
		"hair_style":
			return HAIR_STYLE_COUNT
		"beard":
			return BEARD_STYLE_COUNT
		"eyes":
			return EYE_COLORS.size()
		"trim":
			return TRIM_COLORS.size()
		_:
			return 0


## The deterministic look for one hero rolled from a DNA seed. Unknown class
## ids fall back to the warrior palette (fail-safe default, matching this
## codebase's convention).
func appearance_for(class_id: String, dna_seed: int) -> Dictionary:
	return appearance_from_choices(class_id, {
		"skin": _roll(dna_seed, "skin", SKIN_TONES.size()),
		"hair_color": _roll(dna_seed, "hair", HAIR_COLORS.size()),
		"hair_style": _roll(dna_seed, "hair_style", HAIR_STYLE_COUNT),
		"beard": _roll(dna_seed, "beard", BEARD_STYLE_COUNT),
		"eyes": _roll(dna_seed, "eyes", EYE_COLORS.size()),
		"trim": _roll(dna_seed, "trim", TRIM_COLORS.size()),
	}, dna_seed)


## The look for an explicitly authored hero -- what the character creator
## builds as the player cycles each axis. `choices` maps axis name -> option
## index; a missing or out-of-range index wraps into its pool rather than
## erroring, so a creator can increment freely and let this normalize.
##
## `seed_value` is carried straight through onto the returned dict's "seed"
## rather than used to roll anything here -- unlike appearance_for, this path
## is for a look a player is actively hand-authoring, so nothing about it
## should be RE-derived from the seed. It exists so IllustratedCharacterSprite
## has something deterministic to pick this hero's illustrated head cell from
## (see head_cell_index_for) without every caller of apply_appearance needing
## to plumb a seed through separately. Defaults to 0 -- a caller with no seed
## in hand yet (e.g. a live creator preview before Randomise has run) still
## gets a valid, stable appearance rather than an error.
func appearance_from_choices(class_id: String, choices: Dictionary, seed_value: int = 0) -> Dictionary:
	var palette: Dictionary = CLASS_PALETTES.get(class_id, CLASS_PALETTES[_FALLBACK_CLASS])
	var hair_style := _wrap(int(choices.get("hair_style", 0)), HAIR_STYLE_COUNT)
	var beard := _wrap(int(choices.get("beard", 0)), BEARD_STYLE_COUNT)
	return {
		"seed": seed_value,
		"skin": SKIN_TONES[_wrap(int(choices.get("skin", 0)), SKIN_TONES.size())],
		"hair": HAIR_COLORS[_wrap(int(choices.get("hair_color", 0)), HAIR_COLORS.size())],
		"hair_style": hair_style,
		"hair_style_name": HAIR_STYLES[hair_style],
		"beard": beard,
		"beard_name": BEARD_STYLES[beard],
		"eyes": EYE_COLORS[_wrap(int(choices.get("eyes", 0)), EYE_COLORS.size())],
		"tunic": palette.tunic,
		"trim": TRIM_COLORS[_wrap(int(choices.get("trim", 0)), TRIM_COLORS.size())],
		"legs": palette.legs,
	}


## Index of the option each axis currently sits on, recovered from a built
## appearance -- lets a creator resume cycling from a rolled/randomized look
## instead of snapping back to option 0.
func choices_from_appearance(appearance: Dictionary) -> Dictionary:
	return {
		"skin": maxi(SKIN_TONES.find(appearance.get("skin", SKIN_TONES[0])), 0),
		"hair_color": maxi(HAIR_COLORS.find(appearance.get("hair", HAIR_COLORS[0])), 0),
		"hair_style": int(appearance.get("hair_style", 0)),
		"beard": int(appearance.get("beard", 0)),
		"eyes": maxi(EYE_COLORS.find(appearance.get("eyes", EYE_COLORS[0])), 0),
		"trim": maxi(TRIM_COLORS.find(appearance.get("trim", TRIM_COLORS[0])), 0),
	}


## Wraps an index into [0, count) in both directions, so a creator's
## "previous" past 0 lands on the last option rather than out of range.
func _wrap(index: int, count: int) -> int:
	if count <= 0:
		return 0
	return ((index % count) + count) % count


func _roll(dna_seed: int, salt: String, count: int) -> int:
	# The % 10000 reduction first: Godot's string hash freezes a bare
	# `% count` to one bucket for counts divisible by 3 when the salted
	# strings share a short suffix (see ProceduralHouseSprite._index).
	return (absi(hash("%d_%s" % [dna_seed, salt])) % 10000) % count
