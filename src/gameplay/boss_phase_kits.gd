extends RefCounted

## Hand-authored phase/ability kits for world bosses that haven't gone
## through the emergent fitness-promotion pipeline (world_boss_fitness.gd)
## and its one-shot LLM PhaseGenerator (docs/concept/worldbosses.md's
## Krampus encounter-design section) -- a debug-spawned boss like Krampus
## (see console_species.gd's /spawn roster) needs SOME kit to fight with
## today, since nothing currently promotes a live creature through the real
## pipeline (see worldbosses.md's own "Status" section). Same
## {"hp_threshold": float, "ability": String} shape PhaseGenerator produces
## (see BossPhase), so a hand-authored kit and a real promoted individual's
## baked phases are interchangeable to whatever reads them -- nothing
## downstream needs to change once the real promotion pipeline is wired up
## and starts producing LLM-authored kits instead of these.

## Krampus (docs/concept/worldbosses.md): a goat-horned, chain-wielding
## punisher, Alpine/Bavarian folklore. Two escalating phases past his
## baseline melee + Chain Yank (always available, not phase-gated -- see
## the doc's own encounter writeup for why): phase 2 unlocks TWO abilities
## at once (chain_lash AND terrifying_roar both at 0.5), phase 3 unlocks
## chain_shackle at 0.2 -- mirrors WorldBossFitness.FakePhaseGenerator's own
## two-threshold shape (0.5/0.2), just hand-authored instead of generated.
const _KITS := {
	"krampus": [
		{"hp_threshold": 0.5, "ability": "chain_lash"},
		{"hp_threshold": 0.5, "ability": "terrifying_roar"},
		{"hp_threshold": 0.2, "ability": "chain_shackle"},
	],
}


func has_kit(species: String) -> bool:
	return _KITS.has(species)


## A defensive copy so a caller mutating the result can never corrupt the
## shared table (same discipline as SpellAtomCatalog.spec()). An
## unregistered species returns an empty array rather than crashing --
## this project's standing "never crash on an odd species id" convention.
func kit_for(species: String) -> Array:
	var kit: Array = []
	for phase_entry in _KITS.get(species, []):
		kit.append(phase_entry.duplicate())
	return kit
