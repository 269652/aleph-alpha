extends RefCounted
## How an aggregate population becomes a number of animals you can actually
## meet (docs/concept/ecosystem_dynamics.md).
##
## Measured in a real `--solo` launch, after the report that there was
## nothing to fight. Across the 25 chunks the streamer holds around a fresh
## spawn:
##
##   herbivores  0.40 .. 1.26 per chunk  ->  24 animals drawn
##   predators   0.03 .. 0.10 per chunk  ->   0 animals drawn
##
## Those predator figures sum to **1.66 animals** in the neighbourhood -- a
## real, non-zero population the ecosystem simulation is tracking and
## stepping every day -- and `roundi` turned every one of them into nothing,
## because each chunk on its own rounds below a half. The world near spawn
## was a petting zoo: boar, sheep, mouse, deer, squirrel, horse, alpaca, and
## not one thing that hunts.
##
## The trophic pyramid is not the bug. `PredatorPopulationModel.
## PREDATORS_PER_PREY_UNIT` is 0.08 because an ecosystem really does sustain
## far fewer predators than prey, and that is right. Rounding a real density
## away per chunk is what was wrong: it is the one step between "the world
## has predators in it" and "the player can meet one".
##
## So the fraction is kept as a CHANCE rather than discarded. A chunk with
## 0.3 predators draws one three times in ten; over the whole neighbourhood
## the animals drawn total what the ecology says is there. Seeded per chunk,
## so it is deterministic like every other pick in this codebase -- a chunk
## does not gain and lose a wolf each time it streams back in.
##
## Pure: RefCounted, static, no scene tree, no world.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## The noise lane this draws on, so a chunk's marker roll cannot correlate
## with any other seeded decision made about the same chunk.
const MARKER_NOISE_SALT := 0x9E3779B9


## How many animals to draw for `population`, capped at `cap`.
##
## The whole number is always drawn -- two deer are two deer, never a coin
## flip. The remainder is a chance, taken deterministically from
## `seed_value`, so a density below one animal per chunk shows up as an
## animal in SOME chunks rather than in none.
static func count_for(population: float, seed_value: int, cap: int) -> int:
	if cap <= 0 or population <= 0.0:
		return 0
	var whole := int(floorf(population))
	var fraction := population - float(whole)
	var count := whole
	# > rather than >=: a fraction of exactly zero must never draw an extra
	# animal, whatever the noise says.
	if fraction > 0.0 and PixelNoise.unit(MARKER_NOISE_SALT, seed_value, 0) < fraction:
		count += 1
	return mini(count, cap)
