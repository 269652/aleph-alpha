extends RefCounted

## Per-chunk flower population (see docs/concept/flora.md#flowering-plants-
## scent-and-pollinators).
##
## Deliberately shaped like TallGrass -- deterministic seeded initial
## placement, a bounded patch count, and mutation only through explicit calls
## -- so the two read the same way and a reloaded chunk reproduces the same
## meadow. The difference is how it SPREADS: tall grass creeps into adjacent
## cells on a tick, whereas flowers only appear where seed actually lands and
## takes (see MeadowSpread / SeedDispersal / plant()), so this class never
## spreads itself.
##
## No RandomNumberGenerator: all placement is derived from a seed via
## PixelNoise, which (unlike Godot's string hash) decorrelates neighbouring
## cells -- the clustering bug this project has hit five times.

const FlowerEstablishment = preload("res://src/world/flower_establishment.gd")
const FlowerSpecies = preload("res://src/world/flower_species.gd")
const MeadowSpread = preload("res://src/world/meadow_spread.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const PollinatorForaging = preload("res://src/gameplay/pollinator_foraging.gd")
const Pollination = preload("res://src/gameplay/pollination.gd")
const SeedGermination = preload("res://src/world/seed_germination.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const WindDispersal = preload("res://src/world/wind_dispersal.gd")

## Hard cap per chunk, so animal-dropped seed can't grow the population
## without bound over a long session.
const MAX_FLOWERS := 40

## The founder field a baked meadow grows from is a property of the WORLD, not
## of a chunk: every chunk has to derive the SAME founders for the same ground
## or meadows would stop dead at every seam (see MeadowSpread.founder_tiles).
## So the baked meadow is seeded from this one constant rather than from
## _seed_value, which is per-chunk by design -- it decides this chunk's plant
## sexes and germination rolls, which are nobody else's business.
const MEADOW_WORLD_SEED := 60659

var _width: int
var _height: int
var _biome: PackedStringArray
var _seed_value: int

## Vector2i cell -> species id (String).
var _flowers: Dictionary = {}
## Vector2i cell -> nectar remaining, 0..1. A drained bloom refills slowly
## (see advance), so a meadow is a depleting-and-recovering resource rather
## than an infinite one.
var _nectar: Dictionary = {}

## How fast a picked-over plant sets seed again, per second. Far slower than
## nectar (PollinatorForaging.NECTAR_REGEN_PER_SECOND): a plant refills a
## drained nectary in about a minute, but it sets seed once, so a picked-over
## patch stays picked over for a good while (~8 minutes).
const SEED_REGEN_PER_SECOND := 1.0 / 480.0

## Vector2i cell -> seed remaining, 0..1. Whether it is actually ON OFFER
## additionally depends on the season -- see seed_cells.
var _seed: Dictionary = {}


## `origin_tiles` is the chunk's global tile origin and
## `prevailing_wind`/`prevailing_strength` the region's long-run wind (see
## WeatherModel.prevailing_wind_direction) -- all three feed the baked meadow,
## which is what the wind has ALREADY done by the time the player arrives.
## They default to "at the origin, dead calm" so a caller that only wants a
## patch to exercise nectar/seed/growth on (every test that predates the baked
## meadow being wind-shaped) still gets a real meadow, just an unremarkable
## one.
func _init(
	seed_value: int,
	width: int,
	height: int,
	biome: PackedStringArray,
	origin_tiles: Vector2i = Vector2i.ZERO,
	prevailing_wind: Vector2 = Vector2.RIGHT,
	prevailing_strength: float = 0.0
) -> void:
	_seed_value = seed_value
	_width = width
	_height = height
	_biome = biome
	_seed_initial_flowers(origin_tiles, prevailing_wind, prevailing_strength)


## How long a newly-seeded flower takes to reach full size.
##
## Every flower used to be full-size the instant it existed, so a meadow
## filling in from shed seed looked like blooms popping into being. Long
## enough that growth is something a returning player notices rather than
## something that finishes while they watch, in keeping with the rest of the
## world's real-time growth (see LifeCycle).
const SECONDS_TO_MATURE := 900.0

## The wind seed rides on, set by whoever owns this patch (see
## WeatherModel.wind_direction_for). A patch nobody tells about the weather
## still sheds, just as though the day were calm.
var _wind_direction := Vector2.RIGHT
var _wind_strength := 0.0


func set_wind(direction: Vector2, strength: float) -> void:
	_wind_direction = direction if direction.length() > 0.0 else Vector2.RIGHT
	_wind_strength = clampf(strength, 0.0, 1.0)


## cell -> growth 0..1. Cells absent from this map are treated as GROWN: the
## map-seeded meadow was always there, the same rule TallGrass uses for its
## initial patches, and it keeps this backward-compatible with any patch
## created before growth existed.
var _growth: Dictionary = {}

## Cells whose plant has received matching pollen and can therefore set seed.
var _pollinated: Dictionary = {}


## How grown the flower in this cell is, 0 (just seeded) to 1 (mature). An
## empty cell has no growth at all.
func growth_at(cell: Vector2i) -> float:
	if not has_flower(cell):
		return 0.0
	return float(_growth.get(cell, 1.0))


func get_flower_cells() -> Array:
	return _flowers.keys()


## Only the cells whose species is actually IN BLOOM this season (see
## FlowerSpecies.is_in_bloom) -- what should be rendered, as opposed to
## get_flower_cells' full planted set.
##
## A flower visible on screen must be one a pollinator will actually visit.
## Drawing every planted cell year-round put a large share of out-of-bloom
## species on screen -- FlowerSpecies.scent_strength is exactly 0.0 out of
## bloom, so ScentField saw nothing and pollinators correctly ignored them,
## which read as the foraging being broken (reported twice, latterly with a
## screenshot: "There's a butterfly near two flowers and does nothing...
## they are not attracted by scent at all"). The simulation was right; the
## WORLD was lying about what was in bloom. The plant is still there and
## still simulated -- it simply isn't showing a bloom out of season, which
## is also what a real meadow looks like.
func blooming_cells(season: String) -> Array:
	var out: Array = []
	for cell in _flowers:
		if FlowerSpecies.is_in_bloom(_flowers[cell], season):
			out.append(cell)
	return out


## Seed is its OWN entity lying in the grass, not a state of the plant: a
## flower whose bloom is over sheds seed, it falls nearby, and it stays there
## as something a granivore can see and walk to (see concept/flora.md).
## Vector2i cell -> species id of the seed lying there.
var _ground_seeds: Dictionary = {}

## How far a shed seed lands from its parent is NOT a constant here: it is
## whatever the wind does with it (see shed_seed / WindDispersal), which is
## mostly close by and occasionally a long way downwind. This deliberately
## does not mirror TallGrass.SEED_FALL_RADIUS any more -- grass seed is heavy
## and flower seed is the lightest thing in the world, and that difference is
## the whole reason meadows colonise faster than fields.

## Hard cap per chunk, so an unattended meadow can't carpet itself in seed
## over a long session. Same bounding rationale as MAX_FLOWERS.
const MAX_GROUND_SEEDS := 60

## Expected seconds between shed events for a single out-of-bloom plant.
## Slow: a meadow accumulates seed over minutes, so a patch that has been
## picked clean by birds stays visibly bare for a while.
const SECONDS_PER_SEED_FALL := 40.0

var _shed_accumulator := 0.0
var _shed_index := 0


## Drops seed from plants whose bloom is over. Called on the world's flower
## step; `season` decides which plants are past flowering and therefore
## setting seed.
func shed_seed(delta: float, season: String) -> void:
	if _ground_seeds.size() >= MAX_GROUND_SEEDS:
		return
	var setting: Array = []
	for cell in _flowers:
		if not FlowerSpecies.is_in_bloom(_flowers[cell], season):
			# Only a plant that was actually POLLINATED sets seed. A plant
			# that seeds on its own is not being pollinated -- it is just
			# reproducing, with the pollinator as decoration (see
			# Pollination).
			if _pollinated.has(cell):
				setting.append(cell)
	if setting.is_empty():
		return
	# One shed event per SECONDS_PER_SEED_FALL per seeding plant, so a dense
	# meadow drops seed proportionally faster than a sparse one.
	_shed_accumulator += delta * float(setting.size()) / SECONDS_PER_SEED_FALL
	while _shed_accumulator >= 1.0 and _ground_seeds.size() < MAX_GROUND_SEEDS:
		_shed_accumulator -= 1.0
		_shed_index += 1
		var parent: Vector2i = setting[_shed_index % setting.size()]
		# On the WIND (see WindDispersal). Flower seed is the lightest thing
		# in the world and should travel furthest -- it is why meadows
		# colonise faster than woods. It used to drop within two tiles of the
		# parent whatever the weather, which is heavier behaviour than an
		# acorn's.
		var landing := WindDispersal.landing_offset(
			_seed_value + _shed_index,
			WindDispersal.WEIGHT_FLOWER_SEED,
			_wind_direction,
			_wind_strength
		) / float(TerrainRenderer.TILE_SIZE)
		var offset := Vector2i(int(round(landing.x)), int(round(landing.y)))
		var cell := parent + offset
		if cell.x < 0 or cell.x >= _width or cell.y < 0 or cell.y >= _height:
			continue
		if _ground_seeds.has(cell):
			continue
		_ground_seeds[cell] = _flowers[parent]


## Delivers pollen of `carried_species` to the plant in this cell.
##
## Returns whether it took: only a female plant of the matching species sets
## seed, and only that plant then appears in the shedding list.
func pollinate(cell: Vector2i, carried_species: String) -> bool:
	if not _flowers.has(cell):
		return false
	var species: String = _flowers[cell]
	var sex := Pollination.sex_of(_plant_seed(cell))
	if not Pollination.sets_seed(carried_species, species, sex):
		return false
	_pollinated[cell] = true
	return true


## This plant's sex, for callers that want to show it or decide what a
## pollinator picks up here.
func sex_at(cell: Vector2i) -> String:
	return Pollination.sex_of(_plant_seed(cell))


## A per-plant seed, stable for the plant's life -- the same shape the sprite
## and the tint already use.
func _plant_seed(cell: Vector2i) -> int:
	return hash("%d_%d_%d_plant" % [_seed_value, cell.x, cell.y])


## Roots the seed lying here, if the ground is wet enough and will take it.
##
## Rain is the trigger, which is what makes it a thing a player waits for
## rather than a weather texture (see SeedGermination). `bare_earth` is how
## exposed the soil is: bare ground takes more seed than thick turf, which is
## what makes clearing a patch a way to start a meadow.
##
## A rooted seed becomes a SEEDLING, not a bloom -- growth is something the
## player can watch.
func root_seeds(soil_moisture: float, bare_earth: float) -> void:
	if not SeedGermination.is_rooting_weather(soil_moisture):
		return
	var chance := SeedGermination.germination_chance("grassland", bare_earth)
	if chance <= 0.0:
		return
	for cell in _ground_seeds.keys():
		# Same gate the baked meadow and animal-dropped seed pass: a seedling
		# in an established plant's shade is outcompeted before it is a plant
		# (see FlowerEstablishment). Rain roots seed; it does not suspend
		# competition for light.
		if not FlowerEstablishment.is_clear(cell, _flowers):
			continue
		if _flowers.size() >= MAX_FLOWERS:
			return
		var roll := float(PixelNoise.range_index(
			_seed_value + cell.x * 733 + cell.y, 197, 0, 1000
		)) / 1000.0
		if roll > chance:
			continue
		_flowers[cell] = _ground_seeds[cell]
		_growth[cell] = 0.0
		_ground_seeds.erase(cell)


## Removes the seed lying in this cell, if there is one. Returns the species
## taken, or "" if there was nothing there.
##
## Cell-addressed, for callers that already know exactly which seed they mean
## -- a PickableSeed node holding its own cell, say -- rather than searching by
## position the way an animal has to.
func take_seed_at_cell(cell: Vector2i) -> String:
	if not _ground_seeds.has(cell):
		return ""
	var species: String = _ground_seeds[cell]
	_ground_seeds.erase(cell)
	return species


func ground_seed_cells() -> Array:
	return _ground_seeds.keys()


func species_of_ground_seed(cell: Vector2i) -> String:
	return _ground_seeds.get(cell, "")


## Takes the seed lying at `cell`, returning the species eaten ("" when there
## was none) -- the species matters because a bird carries and replants it.
func take_ground_seed(cell: Vector2i) -> String:
	if not _ground_seeds.has(cell):
		return ""
	var species: String = _ground_seeds[cell]
	_ground_seeds.erase(cell)
	return species


func has_flower(cell: Vector2i) -> bool:
	return _flowers.has(cell)


func species_at(cell: Vector2i) -> String:
	return _flowers.get(cell, "")


## Plants a flower dropped here as carried seed (see SeedDispersal). Returns
## false when a plant is already standing too close, the ground isn't
## grassland, or the chunk is at its cap -- so a caller can just offer a drop
## and let this decide.
func plant(cell: Vector2i, species: String) -> bool:
	if _flowers.size() >= MAX_FLOWERS:
		return false
	if cell.x < 0 or cell.x >= _width or cell.y < 0 or cell.y >= _height:
		return false
	if _biome[cell.y * _width + cell.x] != "grassland":
		return false
	# Seed dropped at a standing plant's foot does not become a second plant
	# there (see FlowerEstablishment) -- this covers the cell already being
	# taken, and the ring around it that a seedling could not survive in. A
	# gate the animal-dispersal path could route around would silently refill
	# exactly the gaps the baked meadow opens.
	if not FlowerEstablishment.is_clear(cell, _flowers):
		return false
	_flowers[cell] = species
	_seed[cell] = 1.0
	_nectar[cell] = 1.0
	# Planted, not map-seeded: it starts as a seedling and grows (see
	# SECONDS_TO_MATURE).
	_growth[cell] = 0.0
	return true


## The flower list in the shape ScentField/SeedDispersal expect, positioned in
## world pixels. `origin_tiles` is the chunk's global tile origin.
func flowers_for_field(origin_tiles: Vector2i, tile_size: int) -> Array:
	var out: Array = []
	for cell in _flowers:
		out.append({
			"position": Vector2(
				float(origin_tiles.x + cell.x + 0.5) * float(tile_size),
				float(origin_tiles.y + cell.y + 0.5) * float(tile_size)
			),
			"species": _flowers[cell],
			"nectar": _nectar.get(cell, 1.0),
		})
	return out


## The meadow that was already there when the player arrived.
##
## This used to be an independent coin flip per grassland cell: a uniform
## speckle at a density set by one constant, which made two neighbouring cells
## both flowering as likely as any other pair (so adjacent pairs and triples
## were constant -- reported as flowers growing "way too dense") and which had
## no relationship whatever to the wind, so a world whose entire dispersal
## model is "light seed goes downwind" nevertheless STARTED isotropic.
##
## It is now what the wind already did: the same kernel the live world sheds
## with, run from sparse world-space founders under the region's prevailing
## wind, through the same establishment gate live seed passes. See
## MeadowSpread and concept/flora.md#the-meadow-you-arrive-to-is-what-the-wind-
## already-did.
func _seed_initial_flowers(
	origin_tiles: Vector2i, prevailing_wind: Vector2, prevailing_strength: float
) -> void:
	var meadow := MeadowSpread.colonise(
		MEADOW_WORLD_SEED,
		origin_tiles,
		_width,
		_height,
		_biome,
		prevailing_wind,
		prevailing_strength,
		MAX_FLOWERS
	)
	for cell in meadow:
		_flowers[cell] = meadow[cell]
		_nectar[cell] = 1.0
		_seed[cell] = 1.0


func nectar_at(cell: Vector2i) -> float:
	return _nectar.get(cell, 0.0)


## Drains a bloom. Returns false if there was nothing left to drink, so a
## caller can just try and let this decide.
func drink(cell: Vector2i) -> bool:
	if _nectar.get(cell, 0.0) <= 0.0:
		return false
	_nectar[cell] = maxf(0.0, float(_nectar[cell]) - PollinatorForaging.NECTAR_PER_DRINK)
	return true


## Refills drained blooms over time. `growth_modifier` (see
## SeasonCycle.growth_modifier) scales only the seedling growth step below --
## nectar and seed regen are unrelated resources, not "growing", and stay on
## their own flat clocks regardless of season.
func advance(delta: float, growth_modifier: float) -> void:
	for cell in _nectar:
		var level: float = _nectar[cell]
		if level < 1.0:
			_nectar[cell] = minf(1.0, level + PollinatorForaging.NECTAR_REGEN_PER_SECOND * delta)
	for cell in _seed:
		var seed_level: float = _seed[cell]
		if seed_level < 1.0:
			_seed[cell] = minf(1.0, seed_level + SEED_REGEN_PER_SECOND * delta)
	# Seedlings growing toward full size. Folded into this patch's existing
	# tick rather than given a second one -- a plant regrowing its nectar and
	# a plant growing up are the same plant living.
	if SECONDS_TO_MATURE > 0.0 and delta > 0.0:
		var growth_step := delta / SECONDS_TO_MATURE * growth_modifier
		for cell in _growth.keys():
			_growth[cell] = minf(1.0, float(_growth[cell]) + growth_step)


## What to call the plant in this cell in a hover tooltip, or "" for nothing
## worth naming (see EarthChunkManager.flower_name_at / World._update_hover_
## tooltip).
##
## Gated on the season for the same reason the RENDERER is (see
## blooming_cells): a planted-but-not-blooming flower is not drawn, so naming
## one would have the tooltip claim a rose stands on what the player can see
## is bare grass -- exactly the sim-and-picture disagreement
## concept/flora.md's "what is visible must be what is real" forbids, only
## with the lie on the other foot.
##
## A seedling says so, the same way WildCropMarker names its own growth
## stages: growth is otherwise invisible beyond the sprite being small.
func label_at(cell: Vector2i, season: String) -> String:
	if not _flowers.has(cell):
		return ""
	var species: String = _flowers[cell]
	if not FlowerSpecies.is_in_bloom(species, season):
		return ""
	var species_name := FlowerSpecies.display_name(species)
	if growth_at(cell) < 1.0:
		return "%s Seedling" % species_name
	return species_name


## The wind this patch is currently shedding on (see set_wind). Read back so a
## test can prove the live weather actually REACHES the meadow -- set_wind
## spent its whole life fully built, fully tested and called by nothing but
## its own test file, which meant every meadow in the running game shed in a
## permanent dead calm.
func wind_direction() -> Vector2:
	return _wind_direction


func wind_strength() -> float:
	return _wind_strength
