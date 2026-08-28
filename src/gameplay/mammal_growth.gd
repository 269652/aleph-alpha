extends RefCounted

## Mammal offspring growth: a live-born juvenile starts at a real fraction of
## its adult size (never zero -- a live birth is not an egg) and grows
## smoothly toward full size over a real multi-day duration (see
## docs/concept/ecosystem_dynamics.md's "Land-mammal courtship" subsection).
##
## Deliberately its own small module, NOT LifeCycle (pollinators' egg/hatch/
## juvenile/adult stages) reused wholesale -- the same call MammalCourtship
## itself already made for not reusing a pollinator-shaped module when the
## underlying biology genuinely differs (see mammal_courtship.gd's own doc
## comment, "reuses Courtship's pairing primitives... but NOT the dance").
## A mammal is born LIVE: there is no egg stage and no separate hatch event,
## so this module only keeps the two things LifeCycle has that still apply to
## a mammal -- a starting size and a growth curve up to full size -- and
## drops the rest.
##
## ## Maturation duration is a per-species SIZE TIER, keyed off max_health
##
## A mouse grows up in weeks; a bear takes years. One flat duration for
## every species (this module's own earlier design) papered over that real
## gap entirely. Duration is now `mature_seconds_for(species)`, a function of
## `CreatureInfo.MAX_HEALTH_BY_SPECIES` -- the SAME size/toughness signal
## every other per-species stat in this codebase already keys off (see
## CreatureInfo's own doc comment: "how big/tough is this species"), rather
## than inventing a second scale-of-species number nothing else uses.
##
## Three discrete tiers, not one duration per exact species: a clean number
## of tested boundaries is something a "tuned values must be a tested
## function, never eyeballed" rule (this repo's CLAUDE.md) can actually hold
## to, where 21 individually-chosen numbers could not.
##
## - **SMALL** (`max_health < SMALL_TIER_MAX_HEALTH`, 15.0) -- mouse,
##   squirrel, and the two snake entries (also live-born/grown through this
##   same machinery, see CreatureMarker -- nothing here special-cases them
##   out). Grounded on a real mouse: sexual maturity in about 6-8 weeks.
##   `SMALL_TIER_MATURE_SECONDS` (30 real days, ~4.3 weeks) keeps that
##   "grows up in about a month" real-world feel, compressed only slightly
##   for playability. This is exactly the OLD flat constant's value --
##   in hindsight it was calibrated for the roster's smallest/fastest
##   species, and undersold everything bigger.
## - **MEDIUM** (`SMALL_TIER_MAX_HEALTH <= max_health < LARGE_TIER_MIN_
##   HEALTH`, i.e. 15.0-39.9) -- the broad middle of the roster: deer,
##   horse, boar, wolf, the big cats other than lion, camel, goat, etc.
##   Grounded on real mid-size herbivores/mid predators: wild boar ~8-10
##   months, white-tailed deer ~1.5 years, horses ~2 years, wolves ~2 years
##   to full sexual maturity. `MEDIUM_TIER_MATURE_SECONDS` (90 real days,
##   3x the small tier) is a proportionally-compressed representative for
##   that whole "many months to ~2 years" real band -- the same wall-clock-
##   but-liveable compression trade the small tier (and the original flat
##   constant) already makes, just scaled up since these species are
##   genuinely slower than a mouse in reality.
##   Note: lynx also lands in this tier (max_health 26.0), NOT alongside
##   lion/bear below, despite being a predator. This is real-world accurate,
##   not an approximation forced by the health-keyed lookup: a lynx is a
##   mid-size cat built more like a large dog than an apex predator, and
##   a real lynx (~1-3 years to sexual maturity, commonly cited around 21
##   months for females) matures distinctly faster than a lion or bear
##   (commonly 3+ years) -- keying off size/toughness rather than
##   predator-vs-herbivore role gets this one right.
## - **LARGE** (`max_health >= LARGE_TIER_MIN_HEALTH`, 40.0) -- lion and
##   bear, the roster's two toughest entries and its only true apex
##   predators. Grounded on real big carnivores commonly needing 3+ years
##   (up to 4-8 for some brown bear populations) to reach full sexual
##   maturity -- the slowest real category on the roster, so it gets the
##   longest tier. `LARGE_TIER_MATURE_SECONDS` (180 real days, 2x the medium
##   tier, 6x the small tier) preserves that real ordering (small < medium
##   < large) while keeping even the slowest species inside a timeframe a
##   player returning across a couple of real months will still see
##   meaningfully progress in -- the same "compressed but liveable" argument
##   the original flat constant made, now honoring the real relative gap
##   between tiers instead of collapsing it to one number.
##
## An unrecognized/empty species (e.g. a bare test marker with no `info`
## set yet) falls back through `CreatureInfo.MAX_HEALTH_BY_SPECIES`'s own
## generic default (10.0, `CreatureInfo._init`'s fallback) rather than a
## second fallback number invented here -- which lands it in the SMALL tier,
## the same tier as everything else near that default's weight class.

const CreatureInfo = preload("res://src/world/creature_info.gd")

const SECONDS_PER_REAL_DAY := 86400.0

## Below this MAX_HEALTH_BY_SPECIES value, a species is in the SMALL
## maturation tier (see the class doc comment's tier table above). Chosen so
## mouse (6.0)/squirrel (9.0)/the snake entries (10.0/14.0) fall under it
## while sheep, the roster's next-lightest species at 18.0, does not --
## pinned by test_tier_assignment_is_keyed_off_max_health_by_species.
const SMALL_TIER_MAX_HEALTH := 15.0

## At or above this MAX_HEALTH_BY_SPECIES value, a species is in the LARGE
## maturation tier. Chosen so lion (45.0) and bear (50.0) -- the roster's
## only two apex predators -- fall in, while the generic "predator" entry
## (35.0, the next-toughest) and jaguar (34.0) do not -- pinned by
## test_tier_assignment_is_keyed_off_max_health_by_species.
const LARGE_TIER_MIN_HEALTH := 40.0

## How long a SMALL-tier mammal takes to grow from newborn to full adult
## size, in real seconds (see the class doc comment's SMALL tier grounding).
const SMALL_TIER_MATURE_SECONDS := 30.0 * SECONDS_PER_REAL_DAY

## How long a MEDIUM-tier mammal takes to grow from newborn to full adult
## size, in real seconds (see the class doc comment's MEDIUM tier
## grounding). Exactly 3x the small tier.
const MEDIUM_TIER_MATURE_SECONDS := 90.0 * SECONDS_PER_REAL_DAY

## How long a LARGE-tier mammal takes to grow from newborn to full adult
## size, in real seconds (see the class doc comment's LARGE tier grounding).
## Exactly 2x the medium tier, 6x the small tier.
const LARGE_TIER_MATURE_SECONDS := 180.0 * SECONDS_PER_REAL_DAY

## A sentinel "definitely already grown" age -- large enough that
## is_mature() reads true for EVERY species tier, regardless of which one a
## given individual turns out to belong to. Used as CreatureMarker.
## age_seconds' default value, set before that marker's `info` (and so its
## species) is even known -- see CreatureMarker.age_seconds' own doc
## comment: a spawned-in creature starts already adult, only something
## actually BORN in front of the player (begin_life()) starts young.
const DEFAULT_ADULT_AGE_SECONDS := LARGE_TIER_MATURE_SECONDS

## How big a newborn mammal is relative to its adult size. Grounded on a
## precocial ungulate newborn (a fawn or foal) -- the majority of this
## game's breeding-eligible land mammals (deer, boar, horse) stand and move
## within hours of birth, already a real, substantial fraction of adult size
## (roughly 40% of adult shoulder height/body length is a representative
## real-world figure for a newborn fawn or foal). This flat constant
## knowingly overstates an ALTRICIAL newborn (e.g. a lynx kitten, born blind
## and comparatively tiny) -- a simplification named explicitly in
## docs/concept/ecosystem_dynamics.md rather than a second, predator-only
## constant nothing here currently tests for. Kept species-independent
## (unlike the maturation DURATION above) -- there is no comparable
## species-scale signal in this codebase for "how developed is a newborn",
## only for adult size/toughness.
const NEWBORN_SCALE := 0.4


## How long the given species takes to grow from newborn to full adult size,
## in real seconds -- see the class doc comment for the three tiers and
## their real-world grounding. Looks up CreatureInfo.MAX_HEALTH_BY_SPECIES
## for the species' size signal; an unrecognized species falls back to
## CreatureInfo's own generic default (10.0) rather than inventing a second
## fallback number here.
static func mature_seconds_for(species: String) -> float:
	var max_health: float = CreatureInfo.MAX_HEALTH_BY_SPECIES.get(species, 10.0)
	if max_health < SMALL_TIER_MAX_HEALTH:
		return SMALL_TIER_MATURE_SECONDS
	if max_health >= LARGE_TIER_MIN_HEALTH:
		return LARGE_TIER_MATURE_SECONDS
	return MEDIUM_TIER_MATURE_SECONDS


## Size relative to an adult, at a given age, for the given species. A
## newborn starts at NEWBORN_SCALE and grows linearly to full size by that
## species' own mature_seconds_for(species), so growing up is something a
## returning player can actually see happen rather than a number that flips
## -- mirrors LifeCycle.size_scale_at's own shape, minus the egg/hatch
## stages a live birth never has.
static func size_scale_at(age_seconds: float, species: String) -> float:
	var mature_seconds := mature_seconds_for(species)
	if age_seconds >= mature_seconds:
		return 1.0
	var grown := clampf(age_seconds / mature_seconds, 0.0, 1.0)
	return lerpf(NEWBORN_SCALE, 1.0, grown)


## Only a grown mammal may enter courtship -- see World._pair_up_courtships.
## Without this a newborn could pair off and breed the moment it was born,
## the same unbounded-growth failure LifeCycle.can_court_at already guards
## against for pollinators. Maturity threshold is this species' own
## mature_seconds_for(species), not a shared flat constant.
static func is_mature(age_seconds: float, species: String) -> bool:
	return age_seconds >= mature_seconds_for(species)
