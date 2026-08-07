extends RefCounted

## The hero look engine: maps (class archetype, dna seed) to a deterministic
## visual identity, Hammerwatch-style -- the CLASS declares itself through the
## outfit palette (warrior in battle red with gold trim, mage in deep arcane
## blue with silver, ranger in forest leather with bronze), while the DNA seed
## individualizes the person wearing it (skin tone, hair color, hair style).
## Same (class, seed) always yields the same hero; rendered by
## ProceduralCharacterSprite's hero generators and worn by CharacterView.
##
## This is the first concrete slice of the concept docs' DNA-drives-phenotype
## pillar (dna.md's "DNA-Driven Phenotype/Body Generation") applied to the
## player character: appearance derives from identity data, never hand-picked.

## Per-class outfit palettes: tunic (torso), trim (belt/accents), legs.
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
}
const _FALLBACK_CLASS := "warrior"

## DNA-picked pools: skin tones and hair colors span a natural human range.
const SKIN_TONES := [
	Color(0.95, 0.8, 0.66), Color(0.87, 0.68, 0.52), Color(0.72, 0.52, 0.36), Color(0.5, 0.35, 0.24),
]
const HAIR_COLORS := [
	Color(0.16, 0.12, 0.1), Color(0.42, 0.26, 0.12), Color(0.78, 0.62, 0.3),
	Color(0.6, 0.28, 0.12), Color(0.75, 0.75, 0.78),
]
## Hair silhouettes ProceduralCharacterSprite can draw (0: full fringe,
## 1: fringe + side locks, 2: short crop).
const HAIR_STYLE_COUNT := 3


## The deterministic look for one hero. Unknown class ids fall back to the
## warrior palette (fail-safe default, matching this codebase's convention).
func appearance_for(class_id: String, dna_seed: int) -> Dictionary:
	var palette: Dictionary = CLASS_PALETTES.get(class_id, CLASS_PALETTES[_FALLBACK_CLASS])
	return {
		"skin": SKIN_TONES[absi(hash("%d_skin" % dna_seed)) % SKIN_TONES.size()],
		"hair": HAIR_COLORS[absi(hash("%d_hair" % dna_seed)) % HAIR_COLORS.size()],
		"hair_style": absi(hash("%d_hair_style" % dna_seed)) % HAIR_STYLE_COUNT,
		"tunic": palette.tunic,
		"trim": palette.trim,
		"legs": palette.legs,
	}
