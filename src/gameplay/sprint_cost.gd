extends RefCounted
## What running costs (docs/concept/survival.md's "Stamina scope", and
## docs/concept/journey_rings.md: the world's order is enforced by
## pressures, and this is the first of them).
##
## Measured before this module existed: `SurvivalMeters.spend_stamina` had
## exactly ONE caller in the whole game -- the sickness step
## (scenes/player.gd's `_sickness_step`) -- while `Player.is_sprinting()`
## simply read the held key and `current_speed()` returned
## `SPRINT_SPEED` (exactly twice `BASE_SPEED`) for as long as it was down.
## So sprint was free, unlimited, and twice as fast as walking for ever.
##
## That one fact hollowed out the whole danger gradient. A predator that
## senses at six tiles and pursues at anything under twice walking speed
## can be ignored by holding a key; `RegionDifficulty`'s EASY/MEDIUM/HARD
## rings gate which species may SPAWN, but a player who can outrun all of
## them has no reason to respect any of it. You could stroll -- run --
## anywhere on Earth.
##
## Stamina is this project's traversal resource by design (survival.md is
## explicit that combat stays off it), which makes it exactly the right
## price for speed. Walking stays free, so a player is never stranded: the
## cost is on the FAST option, which is what makes running a decision
## rather than a tax.
##
## Pure: no meters object, no player, no clock. The caller spends what this
## says, gates on what this allows.


const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")

## How long a sprint from a FULL stamina bar lasts, in seconds, before the
## bar reaches the meters' own exhausted threshold and the legs give out.
##
## The one tuned number here, and everything else is derived from it. Chosen
## as a burst rather than a travel mode: long enough to break contact with
## something that is chasing you or to close the last stretch to a door
## (about a hundred metres at this world's scale -- see
## `burst_distance_metres`), short enough that crossing real country is
## still walking, which is where the world gets to be dangerous at you.
##
## Test-pinned at both ends (test_sprint_cost.gd: shorter is a twitch,
## longer is just a faster walk), and pinned against the ring it must NOT
## be able to cross.
const SECONDS_OF_SPRINT_FROM_FULL := 14.0

## The drain, per second of running. A consequence of the burst length, not
## a second opinion about it: spending the whole bar takes exactly
## SECONDS_OF_SPRINT_FROM_FULL.
const STAMINA_PER_SECOND := 1.0 / SECONDS_OF_SPRINT_FROM_FULL

## The play-scale tile, in pixels. Restated rather than preloading the
## renderer (a pure gameplay rule should not pull in rendering), and held
## to TerrainRenderer.TILE_SIZE by test.
const TILE_SIZE_PX := 16


## The stamina a step of `delta_seconds` costs at this pace. Walking is
## free -- always, deliberately (see the header): a player out of stamina
## can still get home.
static func stamina_for_seconds(delta_seconds: float, sprinting: bool) -> float:
	if not sprinting or delta_seconds <= 0.0:
		return 0.0
	return STAMINA_PER_SECOND * delta_seconds


## Whether legs at this stamina can run at all.
##
## The gate is `SurvivalMeters.EXHAUSTED_THRESHOLD` itself rather than a
## number of this module's own, so "Exhausted" on the survival panel and
## "cannot sprint" are ONE fact that cannot drift apart -- the same
## single-source rule docs/concept/hud.md states for every other readout.
static func can_sprint(stamina: float) -> bool:
	return stamina > SurvivalMeters.EXHAUSTED_THRESHOLD


## How far one full burst carries you, in real metres at this world's play
## scale (GroundSlide.PX_PER_METER, the player-height yardstick every other
## real-world-grounded size in this codebase is read against).
##
## Derived, never typed in: the real `Player.SPRINT_SPEED` for the real
## usable fraction of the bar. It exists so a test can assert the thing the
## whole danger gradient rests on -- that a burst does not cross a ring
## (test_sprint_cost.gd), so lethal country has to be WALKED into, with the
## world watching.
static func burst_distance_metres() -> float:
	return (
		sprint_speed_px_per_second() / GroundSlide.PX_PER_METER
		* SECONDS_OF_SPRINT_FROM_FULL * (1.0 - SurvivalMeters.EXHAUSTED_THRESHOLD)
	)


## The player's own sprint speed in pixels per second, restated here for
## the same reason TILE_SIZE_PX is: a pure rule module must not preload a
## scene script (scenes/player.gd is a Node2D and pulling it in would drag
## the whole scene tree into every test that touches a number). Held to
## `Player.SPRINT_SPEED` by test.
static func sprint_speed_px_per_second() -> float:
	return 80.0
