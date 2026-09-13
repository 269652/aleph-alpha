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
