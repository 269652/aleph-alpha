extends RefCounted

## Reads a WorldBossFitness.PhaseGenerator-shaped phases array (docs/concept/
## worldbosses.md's "Encounter design": {"hp_threshold": float, "ability":
## String}) and answers "which of these should be active right now" from a
## live health_fraction. Pure lookup -- this does not generate phases
## (PhaseGenerator's job) or execute an ability (a future increment, once
## each ability's physics/VFX exists -- see docs/progress.md); it just
## answers the phase-selection question a boss's live combat loop needs
## every time it decides what to do. Works identically whether `phases`
## came from a one-shot LLM call or a hand-authored kit (see
## BossPhaseKits) -- the shape is all that matters.


## Every phase whose hp_threshold has been crossed (health_fraction at or
## below it) -- a boss deep into a fight has ALL of its earlier phases
## active, not just the latest, since a threshold once crossed doesn't
## un-cross as other effects change health_fraction slightly.
func active_phases(phases: Array, health_fraction: float) -> Array:
	var active: Array = []
	for phase_entry in phases:
		if health_fraction <= float(phase_entry["hp_threshold"]):
			active.append(phase_entry)
	return active


## The single most-escalated phase reached so far -- the LOWEST hp_threshold
## among active phases, since a lower threshold means more health has been
## lost, i.e. further into the fight. Returns {} if health_fraction hasn't
## crossed any registered threshold yet. Ties (see Krampus's phase 2, where
## chain_lash and terrifying_roar share hp_threshold 0.5) resolve
## arbitrarily between the tied entries -- callers that need every ability
## active at once (Krampus's real case) should use active_ability_names
## instead of this, which only ever names one.
func current_phase(phases: Array, health_fraction: float) -> Dictionary:
	var active := active_phases(phases, health_fraction)
	if active.is_empty():
		return {}
	var best: Dictionary = active[0]
	for phase_entry in active:
		if float(phase_entry["hp_threshold"]) < float(best["hp_threshold"]):
			best = phase_entry
	return best


## Every ability name active at this health fraction, across every crossed
## phase -- handles a shared-threshold phase (multiple abilities unlocking
## together, like Krampus's phase 2) correctly, unlike current_phase which
## only ever names one.
func active_ability_names(phases: Array, health_fraction: float) -> Array:
	var names: Array = []
	for phase_entry in active_phases(phases, health_fraction):
		names.append(phase_entry["ability"])
	return names
