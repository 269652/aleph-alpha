extends RefCounted

## STUB -- trivial "everyone is a stranger" implementation, replaced by the
## real one as soon as test_npc_recognition.gd is red against it.

const STRANGER := "stranger"
const KNOWS_YOU := "knows_you"
const OWED := "owed"
const TRUSTED := "trusted"
const DISAPPOINTED := "disappointed"
const TIERS: Array[String] = [STRANGER, KNOWS_YOU, OWED, TRUSTED, DISAPPOINTED]


static func parties_of(_entity_id: String) -> Array[String]:
	var out: Array[String] = []
	return out


static func tier_for(_sources: Dictionary) -> Dictionary:
	var empty: Array[String] = []
	return {
		"tier": STRANGER,
		"floor_tier": STRANGER,
		"shared_event_count": 0,
		"last_outcome": "",
		"last_outcome_event_id": "",
		"open_contract_ids": empty.duplicate(),
		"fulfilled_contract_ids": empty.duplicate(),
		"failed_contract_ids": empty.duplicate(),
		"heard_of_you": false,
		"hearsay_strength": 0.0,
	}
