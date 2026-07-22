extends RefCounted

## The magic DSL's primitive-effect catalog (docs/concept/magic.md): the
## fine-grained atomic effects every spell / weapon enchantment / NPC
## instruction is composed from. Pure lookup, no state -- same shape as
## item_catalog.gd. It is the single source of the cost-relevant data
## (base cost + how each atom scales), which spell_cost.gd reads to *derive*
## a spell's price. Skill-tree gating (which atoms a player has unlocked) and
## parameter caps live elsewhere (the validator); this table is the full set
## of atoms the mechanics engine can express at all.

## atom_id -> {category, tier, base_cost, mag_ref, dur_ref}
##
## - category: coarse grouping, one of _CATEGORIES (for editor/UI + cost tuning).
## - tier: 1..3 rarity/power band; higher tiers are gated further up the skill
##   tree and carry a higher base_cost.
## - base_cost: flat cost contribution before magnitude/duration/composition
##   scaling. Always > 0 so no atom is ever free.
## - mag_ref: reference magnitude at which the magnitude cost multiplier is 1.0.
##   0.0 means the atom has no magnitude dimension (its strength is fixed or
##   expressed purely through duration).
## - dur_ref: reference duration (seconds) at which the duration cost multiplier
##   is 1.0. 0.0 means the atom is instantaneous (no duration dimension).
const _ATOMS := {
	# damage -- instantaneous, scales with magnitude
	"fire_damage": {"category": "damage", "tier": 1, "base_cost": 2.0, "mag_ref": 6.0, "dur_ref": 0.0},
	"frost_damage": {"category": "damage", "tier": 1, "base_cost": 2.0, "mag_ref": 6.0, "dur_ref": 0.0},
	"shock_damage": {"category": "damage", "tier": 1, "base_cost": 2.2, "mag_ref": 5.0, "dur_ref": 0.0},
	"poison_damage": {"category": "damage", "tier": 1, "base_cost": 1.8, "mag_ref": 4.0, "dur_ref": 0.0},
	# heal -- instantaneous, scales with magnitude
	"minor_heal": {"category": "heal", "tier": 1, "base_cost": 2.5, "mag_ref": 6.0, "dur_ref": 0.0},
	"major_heal": {"category": "heal", "tier": 2, "base_cost": 4.0, "mag_ref": 15.0, "dur_ref": 0.0},
	# control -- lingering statuses, scale with duration
	"ignite": {"category": "control", "tier": 1, "base_cost": 1.5, "mag_ref": 0.0, "dur_ref": 3.0},
	"freeze": {"category": "control", "tier": 2, "base_cost": 3.0, "mag_ref": 0.0, "dur_ref": 2.0},
	"slow": {"category": "control", "tier": 1, "base_cost": 1.2, "mag_ref": 0.0, "dur_ref": 3.0},
	"root": {"category": "control", "tier": 2, "base_cost": 2.0, "mag_ref": 0.0, "dur_ref": 2.0},
	# movement -- instantaneous displacement, scales with force magnitude
	"push": {"category": "movement", "tier": 1, "base_cost": 1.5, "mag_ref": 10.0, "dur_ref": 0.0},
	"pull": {"category": "movement", "tier": 1, "base_cost": 1.5, "mag_ref": 10.0, "dur_ref": 0.0},
	# defense -- a timed absorb: both a magnitude (how much) and duration (how long)
	"shield": {"category": "defense", "tier": 2, "base_cost": 3.0, "mag_ref": 10.0, "dur_ref": 4.0},
	# summon -- priciest band; a timed entity
	"summon_wisp": {"category": "summon", "tier": 3, "base_cost": 8.0, "mag_ref": 0.0, "dur_ref": 6.0},
	# utility
	"reveal": {"category": "utility", "tier": 1, "base_cost": 1.0, "mag_ref": 0.0, "dur_ref": 5.0},

	# --- 2026-07-15 brainstorm domains (docs/concept/magic.md "the primitive
	# domains go beyond the physical") -- same atom-spec shape, three new
	# categories: biological/genetic, perceptual/mental, spatial.

	# biological -- acts on the life-system itself (ties to dna.md/evolution.md)
	"accelerate_growth": {"category": "biological", "tier": 2, "base_cost": 3.0, "mag_ref": 5.0, "dur_ref": 0.0},
	"induce_mutation": {"category": "biological", "tier": 3, "base_cost": 6.0, "mag_ref": 3.0, "dur_ref": 0.0},
	"suppress_mutation": {"category": "biological", "tier": 2, "base_cost": 2.5, "mag_ref": 0.0, "dur_ref": 5.0},
	"blight": {"category": "biological", "tier": 2, "base_cost": 2.0, "mag_ref": 0.0, "dur_ref": 4.0},
	# perceptual -- affects light/creature temperament/NPC minds (pets.md)
	"illuminate": {"category": "perceptual", "tier": 1, "base_cost": 1.0, "mag_ref": 0.0, "dur_ref": 5.0},
	"calm": {"category": "perceptual", "tier": 1, "base_cost": 1.5, "mag_ref": 0.0, "dur_ref": 4.0},
	"fear": {"category": "perceptual", "tier": 1, "base_cost": 1.5, "mag_ref": 0.0, "dur_ref": 4.0},
	# spatial -- mobility/logistics (transportation.md)
	"teleport": {"category": "spatial", "tier": 2, "base_cost": 3.5, "mag_ref": 8.0, "dur_ref": 0.0},
	"portal": {"category": "spatial", "tier": 3, "base_cost": 7.0, "mag_ref": 0.0, "dur_ref": 8.0},
	"gravity_shift": {"category": "spatial", "tier": 3, "base_cost": 5.0, "mag_ref": 5.0, "dur_ref": 3.0},
}


func has(atom_id: String) -> bool:
	return _ATOMS.has(atom_id)


## The full spec for an atom, as a defensive copy so callers can't mutate the
## shared table. Assumes a known id (callers gate on has() first).
func spec(atom_id: String) -> Dictionary:
	return _ATOMS[atom_id].duplicate()


func category(atom_id: String) -> String:
	return _ATOMS[atom_id]["category"]


func tier(atom_id: String) -> int:
	return _ATOMS[atom_id]["tier"]


func base_cost(atom_id: String) -> float:
	return _ATOMS[atom_id]["base_cost"]


func mag_ref(atom_id: String) -> float:
	return _ATOMS[atom_id]["mag_ref"]


func dur_ref(atom_id: String) -> float:
	return _ATOMS[atom_id]["dur_ref"]


func scales_with_magnitude(atom_id: String) -> bool:
	return _ATOMS[atom_id]["mag_ref"] > 0.0


func scales_with_duration(atom_id: String) -> bool:
	return _ATOMS[atom_id]["dur_ref"] > 0.0


## Every atom id, e.g. for a spell-editor palette or a /help listing.
func known_ids() -> Array:
	return _ATOMS.keys()


## All atom ids in one category, for grouped editor palettes and cost tests.
func ids_in_category(a_category: String) -> Array:
	var result: Array = []
	for atom_id in _ATOMS:
		if _ATOMS[atom_id]["category"] == a_category:
			result.append(atom_id)
	return result
