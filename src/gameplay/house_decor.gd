extends RefCounted

## Occupation-themed interior decor (docs/concept/housing.md's "Occupation-
## themed decor" section) -- the resolution to that doc's own "theme
## matching" Open Question, for the one real per-NPC signal this codebase
## already models: occupation identity.
##
## Deliberately NOT wealth-tiered. `village_wages.gd`'s own file doc comment
## establishes this game's economy as DELIBERATELY neutral between producer
## and non-producer occupations ("village income is neutral between working
## a producing occupation and a non-producing one") -- a richer/poorer
## furniture tier per occupation would contradict a design decision already
## made elsewhere, not extend it. Every occupation therefore draws from the
## same shared pool (`BuildingPiece.CATEGORY_FURNITURE`), never a bigger or
## smaller one: variety, not scarcity.
##
## Each set is reasoned from the two real per-occupation signals this
## codebase already tracks -- `NpcIdentity.WORK_LOCATION_BY_OCCUPATION`
## (where they work) and `OccupationProduction`'s own recipe table (what
## they make) -- not invented lore. A merchant (stall, customers) and a
## nurse (well, patients) are the two occupations whose real work routinely
## brings other people to them, so they get the couch, the one piece meant
## for a visitor to sit on. A herbalist's own recipe is `butterfly_net`, a
## specimen-collecting, knowledge-keeping trade, mirrored by the bookshelf.
## A guard (gate, sleeps between shifts) gets the smallest, barracks-plain
## set -- nothing but somewhere to sleep and sit. A farmer and a fisher,
## the two other real producers alongside the hunter (`NpcProduction.
## PRODUCER_ITEM_BY_OCCUPATION`), get the same plain working-household set:
## a table to eat at, a chair, a rug -- reflecting that their work is manual
## and grounded, not that they earn less (see above).
const FURNITURE_SET_BY_OCCUPATION := {
	"farmer": ["wood_table", "wood_chair", "wood_rug"],
	"blacksmith": ["wood_bed", "wood_chair", "wood_rug"],
	"merchant": ["couch", "wood_bookshelf", "photo_frame"],
	"guard": ["wood_bed", "wood_chair"],
	"fisher": ["wood_table", "wood_chair", "wood_rug"],
	"herbalist": ["wood_bookshelf", "wood_chair", "wood_rug"],
	"hunter": ["wood_bed", "wood_chair", "photo_frame"],
	"nurse": ["couch", "wood_table", "photo_frame"],
}

## The plain baseline every generated house had before this pass -- used
## only for an occupation string that isn't one of NpcIdentity.OCCUPATIONS'
## real 8 (should never happen), so a house is still furnished rather than
## left empty.
const _FALLBACK_SET: Array[String] = ["wood_chair", "wood_table"]


## InteriorTemplates v2 (docs/concept/building.md "Entering"): what fills a
## typed slot letter for a given occupation -- the resident's REAL trade
## decides the room. Every home shares the same basics (a bed, a hearth, a
## table, a rug, a picture, a candle); the seating (`C`), the storage
## (`S`) and above all the workshop slot (`W`) are where one household
## reads differently from the next: a smith's anvil, an herbalist's or
## nurse's workbench, a farmer's barrel, a fisher's or merchant's crate,
## a hunter's or guard's chest -- and a merchant or nurse sits on a couch
## and shelves books where a working household has a chair and a
## cupboard. Every result is a real CATEGORY_FURNITURE id; an unknown
## letter or occupation still furnishes something real (a chair / a
## crate) rather than leaving a hole -- the same fail-open convention
## furniture_set_for below already keeps.
const _COUCH_OCCUPATIONS := {"merchant": true, "nurse": true}
const _BOOKSHELF_OCCUPATIONS := {"herbalist": true, "merchant": true, "nurse": true}
const _WORKSHOP_PIECE_BY_OCCUPATION := {
	"blacksmith": "anvil", "herbalist": "workbench", "nurse": "workbench",
	"farmer": "barrel", "fisher": "crate", "merchant": "crate",
	"hunter": "chest", "guard": "chest",
}

static func piece_for_slot(letter: String, occupation: String) -> String:
	match letter:
		"B":
			return "wood_bed"
		"T":
			return "wood_table"
		"R":
			return "wood_rug"
		"P":
			return "photo_frame"
		"K":
			return "hearth"
		"L":
			return "candle"
		"C":
			return "couch" if _COUCH_OCCUPATIONS.has(occupation) else "wood_chair"
		"S":
			return "wood_bookshelf" if _BOOKSHELF_OCCUPATIONS.has(occupation) else "cupboard"
		"W":
			return _WORKSHOP_PIECE_BY_OCCUPATION.get(occupation, "crate")
		_:
			return "wood_chair"


## The real furniture set for `occupation` -- every entry a real
## BuildingPiece.CATEGORY_FURNITURE id, safe to feed straight into
## EarthChunkManager.furnish_house_at_global.
static func furniture_set_for(occupation: String) -> Array[String]:
	if not FURNITURE_SET_BY_OCCUPATION.has(occupation):
		return _FALLBACK_SET
	var set: Array = FURNITURE_SET_BY_OCCUPATION[occupation]
	var typed: Array[String] = []
	typed.assign(set)
	return typed
